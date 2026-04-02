FROM docker.io/jrei/systemd-ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

# Install systemd and snapd
RUN apt-get update && \
    apt-get install -y snapd fuse squashfuse sudo python3 curl git python3-pip python3-venv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Enable snapd services
RUN systemctl enable snapd.socket snapd.service

RUN useradd -m consumer

# Sudoers: upgrade.sh (snap install needs root)
RUN echo 'consumer ALL=(ALL) NOPASSWD: /home/consumer/upgrade.sh' \
    > /etc/sudoers.d/consumer

# Install systemd service for trigger server
COPY ubuntu-snap/trigger-server.service /etc/systemd/system/trigger-server.service
RUN systemctl enable trigger-server.service

# Scripts
COPY ubuntu-snap/upgrade.sh /home/consumer/upgrade.sh
COPY ubuntu-snap/entrypoint.sh /home/consumer/entrypoint.sh
COPY ubuntu-snap/install.sh /home/consumer/install.sh
RUN chmod +x /home/consumer/upgrade.sh /home/consumer/entrypoint.sh /home/consumer/install.sh
COPY --chown=consumer:consumer trigger-server/server.py /home/consumer/server.py
COPY --chown=consumer:consumer trigger-server/test-runner.py /home/consumer/test-runner.py
COPY --chown=consumer:consumer trigger-server/wpt-runner.py /home/consumer/wpt-runner.py

# Install WPT test suite
RUN git clone --depth 1 --branch merge_pr_58944 https://github.com/web-platform-tests/wpt.git /opt/wpt && \
    cd /opt/wpt && python3 ./wpt make-hosts-file | tee -a /etc/hosts && \
    chown -R consumer:consumer /opt/wpt

ENV CONSUMER_NAME=consumer-ubuntu

EXPOSE 9000

# Use systemd as init
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
