#!/usr/bin/env bash
set -euo pipefail

kind="${1:?package kind is required}"
source_dir="${2:?source directory is required}"
cd "$source_dir"

case "$kind" in
  go)
    if grep -R --include='go.mod' -nE '=>[[:space:]]*(\.\.?/|/)' .; then
      echo 'local go.mod replacement is not releasable' >&2
      exit 1
    fi
    go test ./...
    go build ./...
    ;;
  node)
    npm ci
    npm test
    npm run build
    ;;
  zigbee-host)
    npm ci
    npm test
    ;;
  ui)
    pnpm install --frozen-lockfile
    pnpm run lint
    pnpm run build
    docker build -f apps/api/Dockerfile --target prod -t "slidebolt-ci/ui-api:${BUILD_TAG:-local}" .
    docker build -f apps/web/Dockerfile --target prod -t "slidebolt-ci/ui-web:${BUILD_TAG:-local}" .
    ;;
  android)
    JAVA_HOME="${JAVA17_HOME:?JAVA17_HOME is required}" PATH="$JAVA17_HOME/bin:$PATH" \
      ./gradlew --no-daemon check bddTest assembleDebug
    ;;
  *)
    echo "unknown package kind: $kind" >&2
    exit 2
    ;;
esac
