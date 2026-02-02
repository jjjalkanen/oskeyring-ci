FROM registry.access.redhat.com/ubi9/ubi

# Install required packages (curl already installed as curl-minimal, python3 pre-installed)
RUN dnf install -y python3 && \
    dnf clean all

# Add custom yum repository
RUN echo -e '[custom-repo]\nname=Custom Repository\nbaseurl=http://rpm-registry:8083/rpm\nenabled=1\ngpgcheck=0' > /etc/yum.repos.d/custom.repo

# Copy scripts from local directory
COPY trigger-server/server.py /server.py
COPY trigger-server/test-runner.py /test-runner.py
COPY redhat-rpm/install.sh /install.sh
RUN chmod +x /server.py /test-runner.py /install.sh

ENV CONSUMER_NAME=consumer-redhat

EXPOSE 9000

CMD ["python3", "/server.py"]
