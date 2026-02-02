FROM ubuntu:24.04

# Install nginx and dpkg tools for repository management
RUN apt-get update && \
    apt-get install -y nginx dpkg-dev gzip && \
    apt-get clean

# Create apt repository structure
RUN mkdir -p /var/www/html/debian/pool/main && \
    mkdir -p /var/www/html/debian/dists/stable/main/binary-amd64 && \
    chmod -R 777 /var/www/html

# Configure nginx to serve the apt repository with PUT support
RUN echo 'server { \
    listen 8082; \
    server_name deb-registry; \
    root /var/www/html; \
    client_max_body_size 500M; \
    client_body_temp_path /tmp; \
    location / { \
        autoindex on; \
        add_header Access-Control-Allow-Origin *; \
        dav_methods PUT DELETE MKCOL COPY MOVE; \
        dav_access user:rw group:rw all:r; \
        create_full_put_path on; \
        limit_except GET HEAD POST PUT DELETE MKCOL COPY MOVE { \
            deny all; \
        } \
    } \
}' > /etc/nginx/sites-available/default

EXPOSE 8082

CMD ["nginx", "-g", "daemon off;"]
