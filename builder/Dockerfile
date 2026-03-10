FROM fedora:latest

# Install packaging tools and utilities only (no build toolchain)
RUN dnf install -y \
    flatpak flatpak-builder ostree \
    dpkg-dev rpm-build \
    squashfs-tools \
    createrepo_c \
    python3 curl \
    gnupg \
    git \
    wget zip \
    && dnf clean all

# Create unprivileged builder user
RUN useradd -m builder

USER builder

WORKDIR /home/builder

# Create directories with builder ownership
RUN mkdir -p output scripts

# Flatpak SDK as user-level install (needed for flatpak build-init/build-export)
RUN flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo && \
    flatpak install --user -y flathub org.freedesktop.Sdk//23.08 org.freedesktop.Platform//23.08

# Copy build scripts
COPY --chown=builder:builder builder/scripts/ scripts/
RUN chmod u+x scripts/*.sh scripts/*.py

# Copy upstream Firefox installer templates (used by publish scripts)
COPY --chown=builder:builder firefox/browser/installer/linux/app/ firefox/browser/installer/linux/app/

WORKDIR /home/builder

ENTRYPOINT ["/home/builder/scripts/entrypoint.sh"]
