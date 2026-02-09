FROM registry.access.redhat.com/ubi9/ubi-init

ENV container=docker

# Install required packages (python3 and systemd already present in ubi-init)
RUN dnf install -y python3 systemd && \
    dnf clean all

# Add custom yum repository
RUN echo -e '[custom-repo]\nname=Custom Repository\nbaseurl=http://rpm-registry:8083/rpm\nenabled=1\ngpgcheck=0' > /etc/yum.repos.d/custom.repo

# Copy scripts from local directory
COPY trigger-server/server.py /server.py
COPY trigger-server/test-runner.py /test-runner.py
COPY redhat-rpm/install.sh /install.sh
COPY redhat-rpm/entrypoint.sh /entrypoint.sh
RUN chmod +x /server.py /test-runner.py /install.sh /entrypoint.sh

# Install systemd service for trigger server
COPY redhat-rpm/trigger-server.service /etc/systemd/system/trigger-server.service
RUN systemctl enable trigger-server.service

ENV CONSUMER_NAME=consumer-redhat

EXPOSE 9000

# Use systemd as init
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
