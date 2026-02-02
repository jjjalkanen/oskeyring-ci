FROM ubuntu:24.04

# Install nginx and ostree/flatpak tools
RUN apt-get update && \
    apt-get install -y nginx ostree flatpak && \
    apt-get clean

# Create repository directory
RUN mkdir -p /var/www/html/flatpak-repo && \
    ostree init --mode=archive-z2 --repo=/var/www/html/flatpak-repo && \
    chmod -R 777 /var/www/html

# Configure nginx to serve the repository with PUT support
RUN echo 'server { \
    listen 8080; \
    server_name flatpak-registry; \
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

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
