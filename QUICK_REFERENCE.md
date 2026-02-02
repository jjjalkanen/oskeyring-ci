# Quick Reference Card

## One-Line Commands

```bash
# Setup and run everything
./scripts/create-network.sh && podman-compose up --build

# Or use the wrapper
./scripts/run-orchestration.sh

# Verify setup
./scripts/verify-setup.sh

# View all logs
podman-compose logs -f

# Stop everything
podman-compose down

# Complete cleanup
podman-compose down && podman network rm podman-build-network
```

## Container Access

```bash
# Exec into containers
podman exec -it builder bash
podman exec -it consumer-arch bash
podman exec -it flatpak-registry sh

# View specific logs
podman logs builder
podman logs consumer-debian
podman logs deb-registry
```

## Health Checks

```bash
# Check consumer health endpoints
curl http://localhost:9001/health  # Arch
curl http://localhost:9002/health  # Ubuntu
curl http://localhost:9003/health  # Debian
curl http://localhost:9004/health  # RHEL

# Check registries
curl http://localhost:8080/  # Flatpak
curl http://localhost:8081/  # Snap
curl http://localhost:8082/  # Debian
curl http://localhost:8083/  # RPM
```

## Manual Testing

```bash
# Trigger individual consumer
curl -X POST http://localhost:9001/trigger

# Check package installation
podman exec consumer-arch flatpak list
podman exec consumer-ubuntu snap list
podman exec consumer-debian dpkg -l | grep access-keys
podman exec consumer-redhat rpm -qa | grep access-keys

# Run test manually
podman exec consumer-debian access-keys
```

## Network & Connectivity

```bash
# List network
podman network ls

# Inspect network
podman network inspect podman-build-network

# Test connectivity between containers
podman exec builder ping flatpak-registry
podman exec consumer-arch curl http://flatpak-registry:8080
```

## Port Mapping Reference

| Service | Internal Port | External Port | Purpose |
|---------|--------------|---------------|---------|
| flatpak-registry | 8080 | 8080 | Flatpak repo |
| snap-registry | 8081 | 8081 | Snap store |
| deb-registry | 8082 | 8082 | APT repo |
| rpm-registry | 8083 | 8083 | RPM repo |
| consumer-arch | 9000 | 9001 | Trigger endpoint |
| consumer-ubuntu | 9000 | 9002 | Trigger endpoint |
| consumer-debian | 9000 | 9003 | Trigger endpoint |
| consumer-redhat | 9000 | 9004 | Trigger endpoint |
| builder | 9999 | 9999 | Results collector |

## File Locations Inside Containers

### Builder
- Source code: `/build/`
- Build output: `/output/`
- Scripts: `/scripts/`

### Registries
- Flatpak: `/usr/share/nginx/html/flatpak-repo/`
- Snap: `/usr/share/nginx/html/snaps/`
- Debian: `/usr/share/nginx/html/debian/`
- RPM: `/usr/share/nginx/html/rpm/`

### Consumers
- Trigger server: `/server.py`
- Test runner: `/test-runner.py`
- Install script: `/install.sh`

## Common Issues

| Issue | Solution |
|-------|----------|
| Network not found | `./scripts/create-network.sh` |
| Containers can't talk | Check they're on same network |
| Build fails | Check builder logs: `podman logs builder` |
| Consumer doesn't respond | Check health: `curl localhost:9001/health` |
| Tests timeout | Increase timeout in results-collector.py |
| Port conflict | Change port mappings in docker-compose.yml |

## Project Structure

```
test_oskeyring/
├── app/                    # Rust application
├── builder/                # Build & orchestration container
│   ├── Dockerfile
│   └── scripts/            # Build, publish, trigger, collect
├── registries/             # Package repositories
│   ├── flatpak/
│   ├── snap/
│   ├── deb/
│   └── rpm/
├── consumers/              # Test consumers
│   ├── trigger-server/     # Shared HTTP server
│   ├── arch-flatpak/
│   ├── ubuntu-snap/
│   ├── debian-apt/
│   └── redhat-rpm/
├── scripts/                # Helper scripts
├── docker-compose.yml      # Main orchestration
└── README.md               # Full documentation
```

## Pipeline Stages

1. **Build** - Compile Rust application
2. **Package** - Create 4 package formats
3. **Publish** - Upload to registries
4. **Collect** - Start results server
5. **Trigger** - Notify consumers
6. **Test** - Consumers install & test
7. **Report** - Send results to builder
8. **Summary** - Display final results

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

## Environment Variables

### In Consumers
- `CONSUMER_NAME` - Identifier for logging and reporting

## Useful Podman Commands

```bash
# List all containers
podman ps -a

# List all images
podman images

# Remove all stopped containers
podman container prune

# Remove all unused images
podman image prune -a

# View resource usage
podman stats

# Follow logs for all services
podman-compose logs -f

# Rebuild specific service
podman-compose build builder

# Restart specific service
podman-compose restart consumer-arch
```

## Documentation Files

- `README.md` - Main documentation
- `TROUBLESHOOTING.md` - Debug guide
- `IMPLEMENTATION_SUMMARY.md` - What was built
- `QUICK_REFERENCE.md` - This file
- `CLAUDE.md` - Development guidance
