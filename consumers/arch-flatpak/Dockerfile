FROM archlinux:latest

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm flatpak python curl gnupg \
        xdg-desktop-portal gnome-keyring dbus sudo git python-pip

# Pre-install the Flatpak runtime so it's cached in the image layer
RUN flatpak remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo && \
    flatpak install -y flathub org.freedesktop.Platform//23.08

RUN useradd -m consumer
RUN dbus-uuidgen > /etc/machine-id

# Portal config: tell xdg-desktop-portal to use gnome-keyring for Secret
# and nothing else (avoids needing xdg-desktop-portal-gtk which requires a display)
RUN printf '[preferred]\ndefault=none\norg.freedesktop.impl.portal.Secret=gnome-keyring\n' \
    > /usr/share/xdg-desktop-portal/portals.conf

# Allow consumer to run upgrade.sh as root without password
RUN echo 'consumer ALL=(ALL) NOPASSWD: /home/consumer/upgrade.sh' > /etc/sudoers.d/consumer

# Scripts
COPY arch-flatpak/upgrade.sh /home/consumer/upgrade.sh
RUN chmod +x /home/consumer/upgrade.sh
COPY --chown=consumer:consumer trigger-server/server.py /home/consumer/server.py
COPY --chown=consumer:consumer trigger-server/test-runner.py /home/consumer/test-runner.py
COPY --chown=consumer:consumer trigger-server/wpt-runner.py /home/consumer/wpt-runner.py

# Install WPT test suite
RUN git clone --depth 1 --branch merge_pr_58944 https://github.com/web-platform-tests/wpt.git /opt/wpt && \
    cd /opt/wpt && python3 ./wpt make-hosts-file | tee -a /etc/hosts && \
    chown -R consumer:consumer /opt/wpt

# Flatpak wrapper script for WPT to use as --binary
RUN printf '#!/bin/bash\nflatpak run org.mozilla.firefox "$@"\n' > /usr/local/bin/firefox-flatpak && \
    chmod +x /usr/local/bin/firefox-flatpak

# Startup wrapper: system dbus → session bus → portal → server
COPY arch-flatpak/start.sh /home/consumer/start.sh
RUN chmod +x /home/consumer/start.sh

ENV CONSUMER_NAME=consumer-arch
EXPOSE 9000

CMD ["/home/consumer/start.sh"]
