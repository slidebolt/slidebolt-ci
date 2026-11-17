# slidebolt-ci

Standalone, LAN-owned verification and release automation for SlideBolt. The
Jenkins controller talks only to the dedicated Docker-in-Docker daemon in this
stack; it never mounts the production Docker socket.

## Start

```bash
cp .env.example .env
# Set a real JENKINS_ADMIN_PASSWORD and, optionally, an external CI_DATA_ROOT.
docker compose build
docker compose up -d
```

Open `http://127.0.0.1:18080` by default. The configuration creates five jobs:

- `slidebolt-bootstrap-verify`: rebuilds an existing release from its published
  component tags and runs the isolated core and portability suites.
- `slidebolt-candidate`: polls `release/main` and verifies candidates without
  publishing.
- `slidebolt-promote`: intentionally disabled until the bootstrap proof is
  reviewed and publishing credentials are installed.
- `android-verify`: polls `slidebolt-client-android/main` and runs its full
  host build and BDD suite.
- `android-promote`: disabled signing gate that produces verified phone/TV APK
  and AAB artifacts plus SHA-256 checksums after its four Android signing
  credential IDs are installed.

The controller runs current Jenkins LTS on Java 21 and pins a separate Java 17
toolchain for Android, Gradle through each repository's wrapper, and Android
SDK 37 for reproducible build-only verification. Emulator/KVM and
real-device LAN discovery are deliberately separate future agents; neither is
required to compile, test, lint, or package the phone and TV APKs.
The controller has one executor so heavyweight final-product builds cannot
compete with one another. Additional emulator or LAN agents add capacity
without weakening that serialization boundary.

## Storage and secrets

`CI_DATA_ROOT` holds Jenkins state, the isolated Docker daemon, workspaces, and
caches. Set it to a large local filesystem in the untracked `.env` file.

Do not put credentials in this repository. Add publishing, SlideBolt admin,
and Android signing credentials through Jenkins Credentials after bootstrap.
The portable configuration refers only to credential IDs.

Before running SlideBolt verification, create a Jenkins **Secret text**
credential named `github-read-token` with read access to the private
`slidebolt/sb-e2e` repository. The pipeline exposes it only through a masked
`GIT_ASKPASS` helper and removes that helper after checkout.

## Bootstrap proof from the command line

The same verification used by Jenkins is directly runnable:

```bash
scripts/verify-slidebolt.sh v1.0.64
```

It builds from `release/versions.env`, validates the image, and runs `sb-e2e`
without reaching production or real LAN devices.

