FROM fedora:latest

# Install all build tools: demo app packaging + Firefox system deps
RUN dnf install -y \
    rust cargo \
    flatpak flatpak-builder ostree \
    dpkg-dev rpm-build \
    squashfs-tools \
    createrepo_c \
    python3 curl \
    gnupg \
    pkg-config \
    dbus-devel \
    git \
    bash findutils gzip make perl perl-FindBin tar unzip wget \
    && dnf clean all

# Create unprivileged builder user
RUN useradd -m builder

USER builder

WORKDIR /home/builder

# Create directories with builder ownership
RUN mkdir -p build output scripts

# Flatpak SDK as user-level install (builder can access these)
RUN flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo && \
    flatpak install --user -y flathub org.freedesktop.Sdk//23.08 org.freedesktop.Platform//23.08

# Copy build scripts
COPY --chown=builder:builder builder/scripts/ scripts/
RUN chmod u+x scripts/*.sh scripts/*.py

# Install Firefox build dependencies via mach bootstrap (as builder user).
# The firefox source and parent git repo are bind-mounted via podman build -v
# (passed through --podman-build-args in run-orchestration.sh).
# The :U flag auto-chowns to builder user, avoiding permission issues.
# --no-system-changes avoids needing sudo; system deps are pre-installed above.
# Bootstrap downloads toolchains + sccache to /home/builder/.mozbuild/.
# MOZBUILD_SKIP_VERSION_CHECK skips the git commit age check that fails during build.

# --- Firefox bootstrap disabled for orchestration refactoring ---
# WORKDIR /home/builder/firefox
# RUN pwd
# RUN ls
# ENV MOZBUILD_SKIP_VERSION_CHECK=1
# RUN \
#   --mount=type=bind,source=firefox,target=/home/builder/firefox,ro \
#   --mount=type=bind,from=main_firefox,source=.git,target=/home/builder/git_metadata,ro \
#   GIT_DIR=/home/builder/git_metadata \
#   ./mach bootstrap --application-choice "Firefox for Desktop" --no-system-changes

WORKDIR /home/builder/build

ENTRYPOINT ["/home/builder/scripts/entrypoint.sh"]

