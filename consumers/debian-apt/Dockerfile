FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

RUN apt-get update && \
    apt-get install -y systemd sudo python3 curl gnupg git python3-pip python3-venv dbus libnss3-tools && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# systemd cleanup for container use
RUN cd /lib/systemd/system/sysinit.target.wants/ && \
    ls | grep -v systemd-tmpfiles-setup.service | xargs rm -f && \
    rm -f /lib/systemd/system/multi-user.target.wants/* \
          /etc/systemd/system/*.wants/* \
          /lib/systemd/system/local-fs.target.wants/* \
          /lib/systemd/system/sockets.target.wants/*udev* \
          /lib/systemd/system/sockets.target.wants/*initctl* \
          /lib/systemd/system/basic.target.wants/* \
          /lib/systemd/system/anaconda.target.wants/*

RUN systemctl mask systemd-ask-password-console.path systemd-ask-password-wall.path 2>/dev/null || true

# Re-enable D-Bus system daemon (removed by multi-user.target.wants cleanup above)
RUN systemctl enable dbus.service

RUN echo "deb [trusted=yes] http://deb-registry:8082/debian stable main" \
    > /etc/apt/sources.list.d/custom.list

# Dummy package v0.0.1 so apt upgrade can detect v0.1.0
RUN mkdir -p /tmp/dummy/DEBIAN /tmp/dummy/usr/bin && \
    printf '#!/bin/sh\necho dummy\n' > /tmp/dummy/usr/bin/access-keys && \
    chmod +x /tmp/dummy/usr/bin/access-keys && \
    printf 'Package: access-keys\nVersion: 0.0.1\nArchitecture: amd64\nMaintainer: Test <test@example.com>\nDescription: Dummy placeholder\n' \
        > /tmp/dummy/DEBIAN/control && \
    dpkg-deb --build /tmp/dummy /tmp/access-keys_0.0.1_amd64.deb && \
    dpkg -i /tmp/access-keys_0.0.1_amd64.deb && \
    rm -rf /tmp/dummy /tmp/access-keys_0.0.1_amd64.deb

RUN useradd -m consumer

# Sudoers: upgrade.sh + systemd-run (needed by test-runner.py for credential test)
RUN echo 'consumer ALL=(ALL) NOPASSWD: /home/consumer/upgrade.sh, /usr/bin/systemd-run' \
    > /etc/sudoers.d/consumer

# Container-specific workaround: fix mount propagation for systemd
# credential loading. Not needed on real systems.
# See https://github.com/systemd/systemd/issues/38103
COPY debian-apt/container-init.service /etc/systemd/system/container-init.service
RUN systemctl enable container-init.service

# Trigger server service (runs as consumer user)
COPY debian-apt/trigger-server.service /etc/systemd/system/trigger-server.service
RUN systemctl enable trigger-server.service && \
    ln -sf /lib/systemd/systemd /sbin/init

# Scripts
COPY debian-apt/upgrade.sh /home/consumer/upgrade.sh
RUN chmod +x /home/consumer/upgrade.sh
COPY --chown=consumer:consumer trigger-server/server.py /home/consumer/server.py
COPY --chown=consumer:consumer trigger-server/test-runner.py /home/consumer/test-runner.py
COPY --chown=consumer:consumer trigger-server/wpt-runner.py /home/consumer/wpt-runner.py
COPY --chown=consumer:consumer trigger-server/idb-verify.py /home/consumer/idb-verify.py

# Install WPT test suite
RUN git clone --depth 1 --branch merge_pr_58944 https://github.com/web-platform-tests/wpt.git /opt/wpt && \
    cd /opt/wpt && python3 ./wpt make-hosts-file | tee -a /etc/hosts && \
    chown -R consumer:consumer /opt/wpt

ENV CONSUMER_NAME=consumer-debian
EXPOSE 9000
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
