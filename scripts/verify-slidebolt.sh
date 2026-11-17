#!/usr/bin/env bash
set -euo pipefail

ref="${1:-v1.0.64}"
root="${WORKSPACE:-$(pwd)}/work"
ci_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="$root/release"
e2e_dir="$root/sb-e2e"
image="slidebolt-ci/slidebolt:${BUILD_TAG:-local}"
runner_image="slidebolt-ci/e2e-runner:${BUILD_TAG:-local}"
askpass=""

cleanup() {
  [[ -z "$askpass" ]] || rm -f "$askpass"
}
trap cleanup EXIT

mkdir -p "$root"
if [[ -d "$release_dir/.git" ]]; then
  git -C "$release_dir" fetch --tags --prune origin
else
  git clone https://github.com/slidebolt/release.git "$release_dir"
fi
git -C "$release_dir" checkout --detach "$ref"

if [[ -d "$e2e_dir/.git" ]]; then
  git -C "$e2e_dir" fetch --prune origin
else
  if [[ -n "${GITHUB_READ_TOKEN:-}" ]]; then
    askpass="$(mktemp)"
    chmod 700 "$askpass"
    cat >"$askpass" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' x-access-token ;;
  *) printf '%s\n' "$GITHUB_READ_TOKEN" ;;
esac
EOF
    GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 git clone https://github.com/slidebolt/sb-e2e.git "$e2e_dir"
  else
    git clone https://github.com/slidebolt/sb-e2e.git "$e2e_dir"
  fi
fi
git -C "$e2e_dir" checkout --detach origin/main

cp "$release_dir/.env.example" "$release_dir/.env"
python3 - "$release_dir/.env" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace("UI_DB_PASSWORD=", "UI_DB_PASSWORD=ci", 1)
s = s.replace("UI_SESSION_SECRET=", "UI_SESSION_SECRET=ci", 1)
p.write_text(s)
PY
docker compose -f "$release_dir/compose.yml" config -q
docker compose -f "$release_dir/compose.yml" -f "$release_dir/compose.speech.yml" config -q
ZIGBEE_ADAPTER=/dev/null docker compose -f "$release_dir/compose.yml" -f "$release_dir/compose.zigbee.yml" config -q

"$release_dir/build.sh" --tag "$image"
docker run --rm --entrypoint /bin/sh "$image" -euc '
  for b in sb-messenger sb-storage sb-logging sb-api sb-script sb-virtual sb-media sb-speech \
           asterisk-host plugin-asterisk plugin-androidtv plugin-homeassistant; do
    test -x "/app/.bin.image/$b"
  done
  test -x /usr/local/bin/sb-manager
  test -x /usr/local/bin/sb
  test -f /app/ui/apps/api/dist/index.js
  test -f /usr/share/nginx/html/index.html
  nginx -t
  grep -q "\"mode\":\"tags\"" /app/build-manifest.json
'

docker pull andrius/asterisk@sha256:6f748f08ea128b3a3ca364a2c790a684dab4e71257c79fbbfb9e19e1756854b1
docker build --pull -t "$runner_image" "$ci_root/e2e-runner"

# Jenkins talks to a dedicated Docker-in-Docker daemon. A process in the
# controller cannot route to bridge addresses created inside that daemon, so
# execute the harness in a disposable runner sharing the daemon's network
# namespace. The e2e directory is mounted at the identical absolute path: its
# Compose bind mounts are therefore resolved consistently by the daemon.
docker run --rm \
  --network host \
  --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
  --mount type=bind,src="$e2e_dir",dst="$e2e_dir" \
  --mount type=volume,src=slidebolt-ci-go-cache,dst=/go/pkg/mod \
  --workdir "$e2e_dir" \
  -e SB_E2E_IMAGE="$image" \
  "$runner_image" \
  bash -euc 'make unit; make test SUITE=core IMAGE="$SB_E2E_IMAGE"; make test SUITE=portability IMAGE="$SB_E2E_IMAGE"'

