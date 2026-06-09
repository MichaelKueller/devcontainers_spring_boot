#FROM ghcr.io/coder/podman:ubuntu



FROM node:22 AS node

FROM ubuntu:24.04
COPY --from=node /usr/local /usr/local

LABEL org.opencontainers.image.description="Base Ubuntu image for rootless podman in Coder. See https://coder.com/docs/v2/latest/templates/docker-in-docker#rootless-podman"

USER root

# Install dependencies
RUN apt-get update && apt-get install -y sudo gnupg2 curl vim fuse-overlayfs libvshadow-utils openssh-client btop libcap2-bin uidmap slirp4netns git

# Install podman
RUN mkdir -p /etc/apt/keyrings
RUN curl -fsSL https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/xUbuntu_24.04/Release.key \
  | gpg --dearmor \
  | tee /etc/apt/keyrings/devel_kubic_libcontainers_unstable.gpg > /dev/null
RUN echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/devel_kubic_libcontainers_unstable.gpg]\
    https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/xUbuntu_24.04/ /" \
  | tee /etc/apt/sources.list.d/devel:kubic:libcontainers:unstable.list > /dev/null
RUN apt-get update && apt-get -y install podman

RUN setcap cap_setuid+ep /usr/bin/newuidmap
RUN setcap cap_setgid+ep /usr/bin/newgidmap
RUN chmod 0755 /usr/bin/newuidmap
RUN chmod 0755 /usr/bin/newgidmap

RUN useradd podman
RUN echo "podman:100000:65536" > /etc/subuid
RUN echo "podman:100000:65536" > /etc/subgid
RUN echo "podman ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers

ADD containers.conf /etc/containers/containers.conf
ADD storage.conf /etc/containers/storage.conf
RUN chmod 644 /etc/containers/containers.conf && \
  chmod 644 /etc/containers/storage.conf

RUN mkdir -p /home/podman/.local/share/containers && \
    chown podman:podman -R /home/podman && \
    chmod 644 /etc/containers/containers.conf

RUN mkdir -p /var/lib/shared/overlay-images \
             /var/lib/shared/overlay-layers \
             /var/lib/shared/vfs-images \
             /var/lib/shared/vfs-layers && \
    touch /var/lib/shared/overlay-images/images.lock && \
    touch /var/lib/shared/overlay-layers/layers.lock && \
    touch /var/lib/shared/vfs-images/images.lock && \
    touch /var/lib/shared/vfs-layers/layers.lock

ENV _CONTAINERS_USERNS_CONFIGURED=""

# Alias "docker" to "podman"
RUN ln -s /usr/bin/podman /usr/bin/docker

RUN chsh -s /bin/bash podman


## Podman Compose
RUN echo 'export COMPOSE_CMD=podman-compose' >> ~/.bashrc
            
# Podman-Compose - install system-wide as root
RUN apt install -y podman-compose

# Symlink as docker-compose so devcontainers-cli finds it
RUN ln -sf /usr/local/bin/podman-compose /usr/local/bin/docker-compose

# Also symlink podman as docker
RUN ln -sf /usr/bin/podman /usr/local/bin/docker

ENV COMPOSE_DOCKER_CLI_BUILD=0
ENV DOCKER_BUILDKIT=0

#echo 'export DOCKER_HOST=tcp://127.0.0.1:2375' >> ~/.bashrc
#podman system service --time=0 tcp:127.0.0.1:2375 &


## Remove: NodeJS is now installed from the node image, so this is not needed anymore. If we need to install additional npm packages globally, we can do that in a later step.
# Install Node.js and npm. It is a prerequisite for devcontainers-cli
# Needs to be done as podman user, otherwise npm will be installed globally and not in the user's home directory
# Make sure retry logic is in place to handle transient network issues during the installation process
# RUN curl \
#     --fail \
#     --silent \
#     --show-error \
#     --location \
#     --retry 5 \
#     --retry-delay 10 \
#     --retry-all-errors \
#     https://deb.nodesource.com/setup_22.x | bash -


# RUN apt install -y nodejs

RUN chown -R 1000:1000 "$(npm root -g)" \
 && chown 1000:1000 /usr/bin

USER podman
RUN mkdir -p ~/.npm-global
RUN npm config set prefix "$HOME/.npm-global"
ENV PATH="/home/podman/.npm-global/bin:$PATH"
RUN echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bashrc


ENV SHELL=/bin/bash