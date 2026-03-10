FROM registry.access.redhat.com/ubi9/ubi-init

ENV container=docker

RUN dnf install -y python3 systemd sudo rpm-build dbus-daemon && dnf clean all

# Mask problematic systemd units for container use (UBI9 ubi-init pattern)
RUN systemctl mask systemd-remount-fs.service dev-hugepages.mount \
    sys-fs-fuse-connections.mount systemd-logind.service getty.target \
    console-getty.service systemd-udev-trigger.service \
    systemd-udevd.service systemd-random-seed.service \
    systemd-machine-id-commit.service

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

# Container-specific workaround: fix mount propagation for systemd
# credential loading. Not needed on real systems.
# See https://github.com/systemd/systemd/issues/38103
COPY redhat-rpm/container-init.service /etc/systemd/system/container-init.service
RUN systemctl enable container-init.service

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
