FROM archlinux:latest

# Update system and install required packages
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm flatpak python curl gnupg xdg-desktop-portal dbus

# Copy scripts from local directory
COPY trigger-server/server.py /server.py
COPY trigger-server/test-runner.py /test-runner.py
COPY arch-flatpak/install.sh /install.sh
RUN chmod +x /server.py /test-runner.py /install.sh

ENV CONSUMER_NAME=consumer-arch

# Setup D-Bus
RUN dbus-uuidgen > /etc/machine-id

EXPOSE 9000

# Start D-Bus and then the server
CMD ["sh", "-c", "dbus-daemon --system --fork && python /server.py"]
