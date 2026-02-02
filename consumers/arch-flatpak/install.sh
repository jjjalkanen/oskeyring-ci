#!/bin/bash
set -e

echo "[consumer-arch] Installing access-keys from flatpak..."

# Wait for registry to be available
timeout 60 bash -c 'until curl -s http://flatpak-registry:8080/ > /dev/null; do sleep 1; done'

# Download and import GPG key
echo "[consumer-arch] Importing GPG key..."
curl -o /tmp/flatpak-gpg.pub http://flatpak-registry:8080/flatpak-repo/flatpak-gpg.pub
gpg --import /tmp/flatpak-gpg.pub

# Add remote with GPG key
echo "[consumer-arch] Adding flatpak remote..."
flatpak remote-add --if-not-exists --gpg-import=/tmp/flatpak-gpg.pub custom-repo http://flatpak-registry:8080/flatpak-repo

# Install the flatpak
echo "[consumer-arch] Installing flatpak application..."
flatpak install -y custom-repo org.example.access-keys

# Create wrapper script to run the flatpak
cat > /usr/local/bin/access-keys << 'EOF'
#!/bin/bash
flatpak run org.example.access-keys
EOF
chmod +x /usr/local/bin/access-keys

echo "[consumer-arch] Installation complete"
