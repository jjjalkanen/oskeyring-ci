FROM ubuntu:24.04

# Install nginx and createrepo for RPM repository management
RUN apt-get update && \
    apt-get install -y nginx createrepo-c rpm && \
    apt-get clean

# Create rpm repository directory
RUN mkdir -p /var/www/html/rpm/packages && \
    chmod -R 777 /var/www/html

# Configure nginx to serve the rpm repository with PUT support
RUN echo 'server { \
    listen 8083; \
    server_name rpm-registry; \
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

EXPOSE 8083

CMD ["nginx", "-g", "daemon off;"]
