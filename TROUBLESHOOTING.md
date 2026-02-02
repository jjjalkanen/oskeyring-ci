# Troubleshooting Guide

## Common Issues and Solutions

### Network Issues

**Problem**: `Error: network podman-build-network not found`

**Solution**: Create the network first:
```bash
./scripts/create-network.sh
```

**Problem**: Containers can't communicate with each other

**Solution**:
- Verify all containers are on the same network
- Check container names resolve: `podman exec builder ping flatpak-registry`
- Ensure network wasn't removed: `podman network ls`

### Build Issues

**Problem**: `cargo: command not found` in builder

**Solution**: The builder Dockerfile installs Rust, but if it fails, check:
```bash
podman logs builder
```

**Problem**: Package builds fail

**Solution**: Check individual publish scripts in builder logs. Common issues:
- Missing build dependencies
- Incorrect paths
- Registry not accessible

### Registry Issues

**Problem**: Registry containers fail to start

**Solution**:
- Check registry logs: `podman logs flatpak-registry`
- Verify ports aren't already in use: `ss -tlnp | grep 808[0-3]`
- Rebuild with no cache: `podman-compose build --no-cache`

**Problem**: Packages not appearing in registries

**Solution**:
- Check builder publish script logs
- Verify registry is running: `curl http://localhost:8080`
- Exec into registry to check files: `podman exec flatpak-registry ls -la /usr/share/nginx/html/`

### Consumer Issues

**Problem**: Consumer containers fail to start

**Solution**:
- Check consumer logs: `podman logs consumer-arch`
- Verify trigger server scripts copied correctly
- Check Python is available: `podman exec consumer-arch python --version`

**Problem**: Consumers don't respond to triggers

**Solution**:
- Check consumer health: `curl http://localhost:9001/health`
- Verify trigger server is running: `podman exec consumer-arch ps aux | grep python`
- Check for port conflicts: `ss -tlnp | grep 9000`

**Problem**: Package installation fails

**Solution**:
- Check install.sh script logs
- Verify registry URL is reachable from consumer: `podman exec consumer-arch curl http://flatpak-registry:8080`
- Check package exists in registry
- Review package manager configuration in Dockerfile

**Problem**: Ubuntu snap consumer fails

**Solution**: Snap requires privileged mode and systemd. The docker-compose.yml already sets `privileged: true`. If issues persist:
- Check if snapd is running: `podman exec consumer-ubuntu systemctl status snapd`
- May need to run in a different container runtime or adjust snap installation method

### Results Collection Issues

**Problem**: Results collector times out

**Solution**:
- Check builder logs: `podman logs builder`
- Verify all consumers are running: `podman ps`
- Check if consumers can reach builder: `podman exec consumer-arch curl http://builder:9999`
- Default timeout is 600 seconds (10 minutes)

**Problem**: Not all consumers report back

**Solution**:
- Check which consumers are missing from summary
- Check those consumer logs for errors
- Verify trigger was sent: Check builder logs for trigger messages
- Manually trigger: `curl -X POST http://localhost:9001/trigger`

### Testing Issues

**Problem**: Tests fail with "access-keys binary not found"

**Solution**:
- Check package installation succeeded
- Verify binary path: `podman exec consumer-debian which access-keys`
- Check install.sh script for correct binary location
- For Flatpak: Check wrapper script was created

**Problem**: Tests fail with incorrect output

**Solution**:
- Manually run test: `podman exec consumer-arch access-keys`
- Check expected output in test-runner.py
- Verify Rust application builds correctly

## Debugging Commands

### View all container logs
```bash
podman-compose logs
```

### View specific container log
```bash
podman logs builder
podman logs consumer-arch
podman logs flatpak-registry
```

### Exec into a container
```bash
podman exec -it builder bash
podman exec -it consumer-debian bash
```

### Check network connectivity
```bash
# From builder to registry
podman exec builder curl http://flatpak-registry:8080

# From consumer to registry
podman exec consumer-arch curl http://flatpak-registry:8080

# From consumer to builder
podman exec consumer-arch curl http://builder:9999
```

### Manually trigger a consumer
```bash
curl -X POST http://localhost:9001/trigger  # Arch
curl -X POST http://localhost:9002/trigger  # Ubuntu
curl -X POST http://localhost:9003/trigger  # Debian
curl -X POST http://localhost:9004/trigger  # RHEL
```

### Check package in registry
```bash
# Flatpak
podman exec flatpak-registry ls -la /usr/share/nginx/html/flatpak-repo/

# Snap
podman exec snap-registry ls -la /usr/share/nginx/html/snaps/

# Debian
podman exec deb-registry ls -la /usr/share/nginx/html/debian/pool/main/

# RPM
podman exec rpm-registry ls -la /usr/share/nginx/html/rpm/packages/
```

### Check if package is installed in consumer
```bash
# Arch (Flatpak)
podman exec consumer-arch flatpak list

# Ubuntu (Snap)
podman exec consumer-ubuntu snap list

# Debian (APT)
podman exec consumer-debian dpkg -l | grep access-keys

# RHEL (RPM)
podman exec consumer-redhat rpm -qa | grep access-keys
```

## Complete Reset

If you need to start fresh:

```bash
# Stop and remove all containers
podman-compose down

# Remove all images
podman rmi $(podman images -q)

# Remove network
podman network rm podman-build-network

# Clean up any volumes (if added later)
podman volume prune

# Start fresh
./scripts/run-orchestration.sh
```

## Performance Issues

**Problem**: Build takes too long

**Solution**:
- Use layer caching effectively
- Consider using `--parallel` flag if podman-compose supports it
- Pre-pull base images: `podman pull fedora:latest archlinux:latest ubuntu:24.04 debian:bookworm`

**Problem**: High resource usage

**Solution**:
- Limit container resources in docker-compose.yml using `mem_limit` and `cpus`
- Run fewer consumers simultaneously
- Use lighter base images where possible

## Getting Help

1. Check logs first: `podman-compose logs`
2. Run verification: `./scripts/verify-setup.sh`
3. Review README.md for architecture details
4. Check individual component logs
5. Test components in isolation before full orchestration
