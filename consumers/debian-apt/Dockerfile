FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

# Install systemd and required packages
RUN apt-get update && \
    apt-get install -y systemd python3 curl gnupg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Remove unnecessary systemd units that cause container issues
RUN cd /lib/systemd/system/sysinit.target.wants/ && \
    ls | grep -v systemd-tmpfiles-setup.service | xargs rm -f && \
    rm -f /lib/systemd/system/multi-user.target.wants/* \
          /etc/systemd/system/*.wants/* \
          /lib/systemd/system/local-fs.target.wants/* \
          /lib/systemd/system/sockets.target.wants/*udev* \
          /lib/systemd/system/sockets.target.wants/*initctl* \
          /lib/systemd/system/basic.target.wants/* \
          /lib/systemd/system/anaconda.target.wants/*

# Add custom apt repository
RUN echo "deb [trusted=yes] http://deb-registry:8082/debian stable main" > /etc/apt/sources.list.d/custom.list

# Copy scripts from local directory
COPY trigger-server/server.py /server.py
COPY trigger-server/test-runner.py /test-runner.py
COPY debian-apt/install.sh /install.sh
COPY debian-apt/entrypoint.sh /entrypoint.sh
RUN chmod +x /server.py /test-runner.py /install.sh /entrypoint.sh

# Install systemd service for trigger server
COPY debian-apt/trigger-server.service /etc/systemd/system/trigger-server.service
RUN systemctl enable trigger-server.service && \
    ln -sf /lib/systemd/systemd /sbin/init

ENV CONSUMER_NAME=consumer-debian

EXPOSE 9000

# Use systemd as init
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
