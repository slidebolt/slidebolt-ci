FROM docker:27-cli@sha256:851f91d241214e7c6db86513b270d58776379aacc5eb9c4a87e5b47115e3065c AS docker_cli
FROM golang:1.26-bookworm@sha256:dc40a13b61304647ed7e5d581d246b86413dfc29d63c6d018310feb93cd98fc0 AS go_toolchain
FROM eclipse-temurin:17-jdk@sha256:fbe9d94debbe24e529acfe235b98f065edea050a2dc00129b7d86261ce3248c8 AS java17_toolchain
FROM node:22-bookworm-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee AS node_toolchain
FROM jenkins/inbound-agent:latest-jdk21@sha256:25a3704f7de4d3d0becc441f5683a227556658df1473865ee94c5232355678ab

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git jq make openssh-client python3 unzip \
    && rm -rf /var/lib/apt/lists/*
COPY --from=docker_cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker_cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose
COPY --from=go_toolchain /usr/local/go /usr/local/go
COPY --from=java17_toolchain /opt/java/openjdk /opt/java17
COPY --from=node_toolchain /usr/local/ /usr/local/
ENV PATH=/usr/local/go/bin:${PATH} \
    JAVA17_HOME=/opt/java17
RUN rm -f /usr/local/bin/yarn /usr/local/bin/yarnpkg \
    && corepack disable \
    && npm install --global pnpm@10.28.1

# Android verification remains isolated on the Slidebolt agent rather than the
# shared controller. Versions and checksum are pinned for reproducibility.
ARG ANDROID_CMDLINE_TOOLS_VERSION=15859902
ARG ANDROID_CMDLINE_TOOLS_SHA256=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    PATH=/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:${PATH}
RUN curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" -o /tmp/android-tools.zip \
    && echo "${ANDROID_CMDLINE_TOOLS_SHA256}  /tmp/android-tools.zip" | sha256sum -c - \
    && mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && unzip -q /tmp/android-tools.zip -d /tmp/android-tools \
    && mv /tmp/android-tools/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest" \
    && { yes || true; } | sdkmanager --licenses >/dev/null \
    && sdkmanager "platform-tools" "platforms;android-37.0" "build-tools;37.0.0" \
    && chown -R jenkins:jenkins "${ANDROID_HOME}" \
    && rm -rf /tmp/android-tools /tmp/android-tools.zip

USER jenkins
