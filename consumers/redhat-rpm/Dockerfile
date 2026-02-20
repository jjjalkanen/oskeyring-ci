FROM registry.access.redhat.com/ubi9/ubi-init

ENV container=docker

RUN dnf install -y python3 systemd sudo rpm-build dbus-daemon && dnf clean all

# ubi9/ubi-init is designed for systemd in containers, but ships kernel
# pseudo-filesystem mounts in sysinit.target that cannot complete inside a
# container, blocking the entire boot chain.  Mask only those units.
# Also swap dbus-broker for dbus-daemon: dbus-broker uses inotify for config
# directory watching, which fails when the host's per-user inotify watch pool
# is heavily used (rootless Podman shares the pool with the host UID).
RUN systemctl mask \
    dev-hugepages.mount \
    dev-mqueue.mount \
    sys-fs-fuse-connections.mount \
    sys-kernel-config.mount \
    sys-kernel-debug.mount \
    sys-kernel-tracing.mount \
    dbus-broker.service && \
    rm -f /etc/systemd/system/dbus.service && \
    systemctl enable dbus-daemon.service && \
    systemctl set-default multi-user.target

RUN echo -e '[custom-repo]\nname=Custom Repository\nbaseurl=http://rpm-registry:8083/rpm\nenabled=1\ngpgcheck=0' \
    > /etc/yum.repos.d/custom.repo

# Dummy RPM v0.0.1
RUN mkdir -p /root/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS} && \
    echo '%_topdir /root/rpmbuild' > /root/.rpmmacros && \
    printf 'Name: access-keys\nVersion: 0.0.1\nRelease: 1\nSummary: Dummy placeholder\nLicense: MPL-2.0\n\n%%description\nDummy placeholder\n\n%%install\nmkdir -p %%{buildroot}/usr/bin\nprintf "#!/bin/sh\\necho dummy\\n" > %%{buildroot}/usr/bin/access-keys\nchmod +x %%{buildroot}/usr/bin/access-keys\n\n%%files\n/usr/bin/access-keys\n' \
    > /root/rpmbuild/SPECS/access-keys.spec && \
    rpmbuild -bb /root/rpmbuild/SPECS/access-keys.spec && \
    rpm -i /root/rpmbuild/RPMS/*/access-keys-0.0.1-1.*.rpm && \
    rm -rf /root/rpmbuild /root/.rpmmacros

RUN useradd -m consumer

RUN echo 'consumer ALL=(ALL) NOPASSWD: /home/consumer/upgrade.sh, /usr/bin/systemd-run' \
    > /etc/sudoers.d/consumer

COPY redhat-rpm/trigger-server.service /etc/systemd/system/trigger-server.service
RUN systemctl enable trigger-server.service

COPY redhat-rpm/upgrade.sh /home/consumer/upgrade.sh
RUN chmod +x /home/consumer/upgrade.sh
COPY --chown=consumer:consumer trigger-server/server.py /home/consumer/server.py
COPY --chown=consumer:consumer trigger-server/test-runner.py /home/consumer/test-runner.py

ENV CONSUMER_NAME=consumer-redhat
EXPOSE 9000
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
