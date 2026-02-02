FROM fedora:latest

# Install all build tools needed for different package formats
RUN dnf install -y \
    rust cargo \
    flatpak flatpak-builder ostree \
    dpkg-dev rpm-build \
    squashfs-tools \
    createrepo_c \
    python3 curl \
    gnupg \
    && dnf clean all

# Add Flathub remote and install Flatpak SDK/Platform
RUN flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo && \
    flatpak install -y flathub org.freedesktop.Sdk//23.08 org.freedesktop.Platform//23.08

# Create build directory
RUN mkdir -p /build /output

# Copy build scripts
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh /scripts/*.py

WORKDIR /build

ENTRYPOINT ["/scripts/entrypoint.sh"]
