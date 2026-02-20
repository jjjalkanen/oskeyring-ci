# Auto-Update + Unprivileged Monitor Implementation

## Overview

This document describes the security-focused refactoring that replaced the privileged HTTP trigger server with an auto-update + unprivileged monitor architecture. Consumers now detect package updates automatically using OS-native mechanisms and run monitors as unprivileged users.

## Architecture Changes

### Old Flow (Privileged Trigger)
```
Builder → POST /trigger → server.py (root) → install.sh (root) → test → report
```

### New Flow (Auto-Update + Monitor)
```
Builder → publishes packages → auto-updater (systemd timer/background) →
  detects & installs → tests → writes results.json →
  monitor (unprivileged) → reports to builder
```

## Key Components

### 1. Monitor Server (consumers/trigger-server/server.py)
- **Runs as**: Unprivileged `consumer` user
- **Functions**:
  - Serves `GET /health` for readiness checks
  - Background thread watches for `/home/consumer/results.json`
  - Reports results to builder with 60-retry backoff (2s interval)
- **Removed**: `POST /trigger` endpoint (no longer needed)

### 2. Auto-Updater Scripts

#### Arch Flatpak (consumers/arch-flatpak/auto-updater.sh)
- **Runs as**: Root (background process in CMD)
- **Process**:
  1. Wait for flatpak-registry availability
  2. Import GPG key, add custom remote
  3. Retry `flatpak install` until successful (2s interval)
  4. Create wrapper script at `/usr/local/bin/access-keys`
  5. Run tests, write results to `/home/consumer/results.json`

#### Debian/RedHat (consumers/{debian-apt,redhat-rpm}/auto-updater.sh)
- **Runs as**: Root (via systemd service)
- **Process**:
  1. Check for package upgrades (`apt-cache policy` / `dnf repoquery`)
  2. Detect v0.0.1 → v0.1.0 upgrade
  3. Install new version
  4. Set up systemd credentials (encrypt sync.key)
  5. Run tests, write results
  6. Stop the timer (one-time execution)

### 3. Systemd Services (Debian/RedHat)

#### access-keys-updater.timer
- Starts 5s after boot
- Repeats every 2s until upgrade detected
- Accuracy: 1s

#### access-keys-updater.service
- Type: oneshot
- ExecStart: `/home/consumer/auto-updater.sh`
- Runs as root (required for package installation)

#### trigger-server.service (rewritten)
- **User**: consumer (unprivileged)
- **Group**: consumer
- ExecStart: `/usr/bin/python3 /home/consumer/server.py`
- Restart: on-failure

### 4. Consumer Dockerfiles

#### Arch Flatpak
```dockerfile
# Install system packages
# Create consumer user
# Copy auto-updater (root-owned)
# Copy monitor + test-runner (consumer-owned)
CMD: dbus + auto-updater & + su to consumer for monitor
```

#### Debian
```dockerfile
# Install systemd + packages
# Configure apt repository
# Build/install dummy v0.0.1 package
# Install systemd services (timer + monitor)
# Create consumer user
CMD: /sbin/init (systemd)
```

#### RedHat
```dockerfile
# Install systemd + packages
# Configure yum repository
# Build/install dummy v0.0.1 RPM
# Install systemd services (timer + monitor)
# Create consumer user
CMD: /sbin/init (systemd)
```

### 5. Builder Pipeline Changes

#### builder/scripts/entrypoint.sh
```bash
1. Build packages
2. Start results-collector FIRST (must be ready)
3. Health check consumers (no triggering)
4. Publish packages (triggers auto-detection)
5. Wait for results
```

#### builder/scripts/trigger-consumers.sh
- **Simplified**: Health checks only
- **Removed**: `POST /trigger` calls
- Checks all 4 consumers (60s timeout per consumer)

## Security Improvements

### Privilege Separation
| Component | Old Privilege | New Privilege |
|-----------|---------------|---------------|
| Monitor server | root | consumer (unprivileged) |
| Test runner | root | consumer (unprivileged) |
| Package installer | root via HTTP | root via systemd/background |

### Attack Surface Reduction
- ❌ **Removed**: Root HTTP server accepting POST requests
- ✅ **Added**: Unprivileged monitor with read-only file watching
- ✅ **Added**: Systemd isolation (User=, Group=)

## Testing Timeline

### Expected Behavior
```
T=0s:   Consumers start, monitors serve /health
T=2s:   Builder starts results-collector on port 9999
T=5s:   Builder checks consumer health (no triggers)
T=8s:   Builder publishes packages to registries
T=10s:  Auto-updaters detect new packages (2s polling interval)
T=15s:  Package installation completes
T=20s:  Credential setup + tests run
T=22s:  results.json written (readable by consumer user)
T=24s:  Monitors detect results, POST to builder
T=30s:  All 4 results collected, builder exits
```

### Success Indicators
1. No "Permission denied" errors from monitors
2. Auto-updaters detect v0.1.0 (Debian/RedHat) or flatpak package (Arch)
3. Tests execute successfully with correct credentials
4. Results JSON written with consumer:consumer ownership
5. Builder collector receives all 4 reports

## Files Changed

### Added (7 files)
- `consumers/arch-flatpak/auto-updater.sh`
- `consumers/debian-apt/auto-updater.sh`
- `consumers/debian-apt/access-keys-updater.service`
- `consumers/debian-apt/access-keys-updater.timer`
- `consumers/redhat-rpm/auto-updater.sh`
- `consumers/redhat-rpm/access-keys-updater.service`
- `consumers/redhat-rpm/access-keys-updater.timer`

### Modified (8 files)
- `builder/scripts/entrypoint.sh` (reordered: collector before publish)
- `builder/scripts/trigger-consumers.sh` (health checks only)
- `consumers/arch-flatpak/Dockerfile` (background auto-updater + su)
- `consumers/debian-apt/Dockerfile` (dummy package + systemd)
- `consumers/debian-apt/trigger-server.service` (User=consumer)
- `consumers/redhat-rpm/Dockerfile` (dummy package + systemd)
- `consumers/redhat-rpm/trigger-server.service` (User=consumer)
- `consumers/trigger-server/server.py` (complete rewrite)

### Deleted (5 files)
- `consumers/arch-flatpak/install.sh`
- `consumers/debian-apt/install.sh`
- `consumers/debian-apt/entrypoint.sh`
- `consumers/redhat-rpm/install.sh`
- `consumers/redhat-rpm/entrypoint.sh`

## Rollback Plan

If issues arise, revert with:
```bash
git reset --hard HEAD~1  # After commit
# or
git checkout .           # Before commit
git clean -fd
```

## Future Enhancements

1. **Credential Rotation**: Extend systemd credentials to Arch (D-Bus secrets API)
2. **Metrics**: Add Prometheus exporter to monitors
3. **Alerting**: Integrate with systemd's OnFailure= for auto-updater failures
4. **Logging**: Centralize logs to builder for debugging

## References

- Systemd credentials: https://systemd.io/CREDENTIALS/
- Flatpak sandboxing: https://docs.flatpak.org/en/latest/sandbox-permissions.html
- Snap confinement: https://snapcraft.io/docs/snap-confinement
