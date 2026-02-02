FROM docker.io/jrei/systemd-ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

# Install systemd and snapd
RUN apt-get update && \
    apt-get install -y snapd fuse squashfuse python3 curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Enable snapd services
RUN systemctl enable snapd.socket snapd.service

# Copy scripts from local directory
COPY trigger-server/server.py /server.py
COPY trigger-server/test-runner.py /test-runner.py
COPY ubuntu-snap/install.sh /install.sh
COPY ubuntu-snap/entrypoint.sh /entrypoint.sh
RUN chmod +x /server.py /test-runner.py /install.sh /entrypoint.sh

# Install systemd service for trigger server
COPY ubuntu-snap/trigger-server.service /etc/systemd/system/trigger-server.service
RUN systemctl enable trigger-server.service

ENV CONSUMER_NAME=consumer-ubuntu

EXPOSE 9000

# Use systemd as init
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
