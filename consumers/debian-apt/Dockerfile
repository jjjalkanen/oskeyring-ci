FROM debian:bookworm

# Install required packages
RUN apt-get update && \
    apt-get install -y python3 curl gnupg && \
    apt-get clean

# Add custom apt repository
RUN echo "deb [trusted=yes] http://deb-registry:8082/debian stable main" > /etc/apt/sources.list.d/custom.list

# Copy scripts from local directory
COPY trigger-server/server.py /server.py
COPY trigger-server/test-runner.py /test-runner.py
COPY debian-apt/install.sh /install.sh
RUN chmod +x /server.py /test-runner.py /install.sh

ENV CONSUMER_NAME=consumer-debian

EXPOSE 9000

CMD ["python3", "/server.py"]
