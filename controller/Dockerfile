FROM docker:27-cli AS docker_cli
FROM golang:1.26-bookworm AS go_toolchain
FROM eclipse-temurin:17-jdk AS java17_toolchain
FROM jenkins/jenkins:2.580.2-jdk21

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git jq make openssh-client python3 unzip \
    && rm -rf /var/lib/apt/lists/*
COPY --from=docker_cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker_cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose
COPY --from=go_toolchain /usr/local/go /usr/local/go
COPY --from=java17_toolchain /opt/java/openjdk /opt/java17
ENV PATH=/usr/local/go/bin:${PATH}

# The verification controller includes the deterministic Android build toolchain.
# Emulator/KVM and physical-LAN verification remain separate agents so this
# controller does not need elevated access to the host.
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
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager "platform-tools" "platforms;android-37.0" "build-tools;37.0.0" \
    && chown -R jenkins:jenkins "${ANDROID_HOME}" \
    && rm -rf /tmp/android-tools /tmp/android-tools.zip

COPY controller/plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
USER jenkins

