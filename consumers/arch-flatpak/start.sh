#!/bin/bash
set -e

# 1. Populate WPT hosts (Podman overwrites /etc/hosts at container start)
cd /opt/wpt && python3 ./wpt make-hosts-file >> /etc/hosts

# 2. Start system D-Bus (needed by flatpak)
mkdir -p /run/dbus
dbus-daemon --system --fork

# 3. Launch everything inside a session bus via dbus-run-session.
#    This sets DBUS_SESSION_BUS_ADDRESS for all child processes,
#    including flatpak run invoked by the test-runner.
#
#    XDG_CURRENT_DESKTOP=GNOME is required because the gnome-keyring
#    portal config (.portal file) has UseIn=gnome — without this,
#    xdg-desktop-portal won't use gnome-keyring as the Secret backend.
exec su -s /bin/bash consumer -c '
    export XDG_CURRENT_DESKTOP=GNOME
    export WPT_FIREFOX_BINARY=/usr/local/bin/firefox-flatpak
    exec dbus-run-session -- bash -c "
        # 4. Start gnome-keyring-daemon with an unlocked login keyring.
        #    --unlock reads a password from stdin and creates the login
        #    collection if it does not exist. Use a dummy password since
        #    this is a test container.
        echo test | gnome-keyring-daemon --unlock --components=secrets &
        sleep 2

        # 5. Start xdg-desktop-portal (discovers gnome-keyring for Secret portal)
        /usr/lib/xdg-desktop-portal &
        sleep 2

        # 6. Run the trigger server
        exec python3 /home/consumer/server.py
    "
'
