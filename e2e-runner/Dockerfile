FROM docker:27-cli@sha256:851f91d241214e7c6db86513b270d58776379aacc5eb9c4a87e5b47115e3065c AS docker_cli
FROM golang:1.26-bookworm@sha256:dc40a13b61304647ed7e5d581d246b86413dfc29d63c6d018310feb93cd98fc0

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates iproute2 make \
    && rm -rf /var/lib/apt/lists/*
COPY --from=docker_cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker_cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose

# This runner uses the dedicated Docker-in-Docker daemon's network namespace.
# It can reach isolated test bridge addresses without exposing the host Docker
# socket or any production network to the Jenkins controller.
