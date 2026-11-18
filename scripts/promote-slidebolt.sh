#!/usr/bin/env bash
set -euo pipefail
set +x

version="${1:-}"
proof="${2:-candidate-proof.json}"
repo="${GITHUB_RELEASE_REPOSITORY:-slidebolt/release}"
registry_image="${SLIDEBOLT_REGISTRY_IMAGE:-ghcr.io/slidebolt/release}"
root="${WORKSPACE:-$(pwd)}/promotion"
release_dir="$root/release"
artifacts_dir="$root/artifacts"
docker_config="$(mktemp -d)"
push_output="$(mktemp)"
export DOCKER_CONFIG="$docker_config"

cleanup() {
  docker logout ghcr.io >/dev/null 2>&1 || true
  rm -rf "$docker_config"
  rm -f "$push_output"
}
trap cleanup EXIT

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
valid_version() { [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
api() {
  curl --fail-with-body --silent --show-error \
    -H "Authorization: Bearer $GITHUB_RELEASE_TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' "$@"
}
api_asset() {
  curl --fail-with-body --silent --show-error \
    -H "Authorization: Bearer $GITHUB_RELEASE_TOKEN" \
    -H 'Accept: application/octet-stream' \
    -H 'X-GitHub-Api-Version: 2022-11-28' "$@"
}

valid_version "$version" || die 'version must look like v1.2.3'
[[ -f "$proof" ]] || die "candidate proof not found: $proof"
commit="$(jq -er '.releaseCommit | select(test("^[0-9a-f]{40}$"))' "$proof")" \
  || die 'candidate proof has no valid release commit'
: "${GITHUB_RELEASE_TOKEN:?github-release-publisher credential is required}"
: "${GITHUB_PUBLISHER_USER:?github-release-publisher username is required}"

mkdir -p "$root" "$artifacts_dir"
git clone --filter=blob:none https://github.com/slidebolt/release.git "$release_dir"
git -C "$release_dir" checkout --detach "$commit"
[[ "$(git -C "$release_dir" rev-parse HEAD)" == "$commit" ]] || die 'release commit mismatch'
remote_main="$(git -C "$release_dir" ls-remote origin refs/heads/main | awk '{print $1}')"
[[ "$remote_main" == "$commit" ]] || die 'candidate is no longer release/main'
if git -C "$release_dir" ls-remote --exit-code origin "refs/tags/$version" >/dev/null 2>&1; then
  die "tag already exists: $version"
fi

# The catalog generator both waits for every component asset and proves each
# downloaded executable can serialize its setup contract. Component Actions
# can finish in any order; final publication cannot begin until all are ready.
deadline=$((SECONDS + ${COMPONENT_WAIT_SECONDS:-1200}))
until (
  cd "$release_dir/tools/catalog"
  go run . \
    --manifest ../../quickstart-components.json \
    --versions ../../versions.env \
    --output "$artifacts_dir/quickstart-catalog.json" \
    --release "$version"
); do
  (( SECONDS < deadline )) || die 'component release assets did not become ready'
  printf 'Component assets are not complete; retrying in 30 seconds.\n' >&2
  sleep 30
done

# Re-run the full final-product proof at the exact candidate commit. The
# verifier names the resulting local image from BUILD_TAG.
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-slidebolt.sh" "$commit"
local_image="slidebolt-ci/slidebolt:${BUILD_TAG:-local}"
docker run --rm --entrypoint /bin/cat "$local_image" /app/build-manifest.json \
  > "$artifacts_dir/build-manifest.json"
jq -e --arg commit "$commit" '.mode == "tags" and .repos.release == $commit' \
  "$artifacts_dir/build-manifest.json" >/dev/null

tar -czf "$artifacts_dir/slidebolt-${version}-install.tar.gz" -C "$release_dir" \
  .env.example compose.yml compose.speech.yml compose.zigbee.yml README.md docs
(
  cd "$artifacts_dir"
  sha256sum build-manifest.json quickstart-catalog.json "slidebolt-${version}-install.tar.gz" > SHA256SUMS
)

printf '%s' "$GITHUB_RELEASE_TOKEN" | docker login ghcr.io -u "$GITHUB_PUBLISHER_USER" --password-stdin >/dev/null
version_image="$registry_image:$version"
resuming=false
if docker manifest inspect "$version_image" >/dev/null 2>&1; then
  [[ "${RESUME_PARTIAL:-false}" == 'true' ]] \
    || die "immutable registry tag already exists: $version_image"
  resuming=true
  docker pull "$version_image" >/dev/null
  image_ref="$(docker image inspect "$version_image" --format '{{range .RepoDigests}}{{println .}}{{end}}' | grep -m1 "^${registry_image}@sha256:")"
  image_digest="${image_ref##*@}"
  [[ "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die 'existing registry image has no valid digest'
  docker run --rm --entrypoint /bin/cat "$version_image" /app/build-manifest.json \
    > "$root/existing-build-manifest.json"
  jq -S '{mode,repos}' "$artifacts_dir/build-manifest.json" > "$root/expected-repos.json"
  jq -S '{mode,repos}' "$root/existing-build-manifest.json" > "$root/existing-repos.json"
  cmp "$root/expected-repos.json" "$root/existing-repos.json" \
    || die 'existing immutable image was built from different component commits'
else
  docker tag "$local_image" "$version_image"
  docker push "$version_image" | tee "$push_output"
  image_digest="$(sed -nE 's/.*digest: (sha256:[0-9a-f]+).*/\1/p' "$push_output" | tail -1)"
  [[ -n "$image_digest" ]] || die 'registry did not report an image digest'
fi
printf '%s@%s\n' "$registry_image" "$image_digest" > "$artifacts_dir/IMAGE"
(cd "$artifacts_dir" && sha256sum IMAGE >> SHA256SUMS)

release_json="$root/release.json"
if [[ "$resuming" == true ]]; then
  api "https://api.github.com/repos/$repo/releases?per_page=100" \
    | jq -e --arg tag "$version" --arg commit "$commit" \
      '[.[] | select(.tag_name == $tag and .draft == true and .target_commitish == $commit)] | select(length == 1) | .[0]' \
      > "$release_json" \
    || die 'exactly one matching draft release was not found'
  release_id="$(jq -er .id "$release_json")"
  remote_dir="$root/remote-artifacts"
  mkdir -p "$remote_dir"
  jq -e '[.assets[].name] | sort == (["IMAGE", "SHA256SUMS", "build-manifest.json", "quickstart-catalog.json", ("slidebolt-" + $tag + "-install.tar.gz")] | sort)' \
    --arg tag "$version" "$release_json" >/dev/null \
    || die 'draft release has an unexpected asset set'
  while read -r name asset_id; do
    api_asset -L "https://api.github.com/repos/$repo/releases/assets/$asset_id" > "$remote_dir/$name"
  done < <(jq -r '.assets[] | [.name, (.id|tostring)] | @tsv' "$release_json")
  (cd "$remote_dir" && sha256sum -c SHA256SUMS) \
    || die 'draft release asset checksum verification failed'
  cmp "$remote_dir/IMAGE" "$artifacts_dir/IMAGE" \
    || die 'draft release points at a different registry digest'
  cmp "$remote_dir/build-manifest.json" "$root/existing-build-manifest.json" \
    || die 'draft manifest differs from the immutable image manifest'
  cp "$remote_dir"/* "$artifacts_dir"/
else
  jq -n --arg tag "$version" --arg commit "$commit" --arg digest "$image_digest" \
    '{tag_name:$tag,target_commitish:$commit,name:$tag,draft:true,prerelease:false,generate_release_notes:true,body:("Container: `ghcr.io/slidebolt/release:"+$tag+"`\n\nDigest: `"+$digest+"`")}' \
    > "$root/create-release.json"
  api -X POST "https://api.github.com/repos/$repo/releases" \
    -H 'Content-Type: application/json' --data-binary "@$root/create-release.json" > "$release_json"
  release_id="$(jq -er .id "$release_json")"
  upload_url="$(jq -er .upload_url "$release_json" | sed 's/{.*//')"

  for file in "$artifacts_dir"/*; do
    name="$(basename "$file")"
    api -X POST "${upload_url}?name=${name}" -H 'Content-Type: application/octet-stream' \
      --data-binary "@$file" >/dev/null
  done
fi

# Verify every uploaded draft asset through the authenticated API before
# exposing the release or moving latest.
while read -r expected name; do
  asset_id="$(api "https://api.github.com/repos/$repo/releases/$release_id/assets" | \
    jq -er --arg name "$name" '.[] | select(.name == $name) | .id')"
  actual="$(api_asset -L \
    "https://api.github.com/repos/$repo/releases/assets/$asset_id" | sha256sum | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "published checksum mismatch: $name"
done < "$artifacts_dir/SHA256SUMS"

api -X PATCH "https://api.github.com/repos/$repo/releases/$release_id" \
  -H 'Content-Type: application/json' --data-binary '{"draft":false}' >/dev/null
docker tag "$version_image" "$registry_image:latest"
docker push "$registry_image:latest"
printf 'Published %s at %s@%s\n' "$version" "$registry_image" "$image_digest"
