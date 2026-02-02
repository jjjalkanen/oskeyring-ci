# Known Issues

This document tracks known issues in the test_oskeyring orchestration system.

## rpm-registry: crun exec.fifo Error

**Status**: Transient startup issue

**Error Message**:
```
[rpm-registry] cannot open `/run/user/1000/crun/928060cd847eb932850145fbcfa56b58906787a1603b4583eb6c58eaaf3dd89f/exec.fifo`: No such file or directory
[rpm-registry] Error: unable to start container 928060cd847eb932850145fbcfa56b58906787a1603b4583eb6c58eaaf3dd89f: `/usr/bin/crun start 928060cd847eb932850145fbcfa56b58906787a1603b4583eb6c58eaaf3dd89f` failed: exit status 1
```

**Description**:
During container startup with rootless podman, the rpm-registry container occasionally fails to start with a crun exec.fifo error. The exec.fifo file is used by crun (the container runtime) for process management and synchronization during container startup.

**Likely Causes**:
1. **Stale container state**: Previous container runs may leave behind stale runtime state in `/run/user/1000/crun/`
2. **Race condition**: Timing issue during container initialization where the fifo is expected but not yet created
3. **Cleanup incomplete**: The cleanup script may not fully remove all runtime artifacts from previous runs
4. **Permissions issue**: Rootless podman runtime directory permissions may be incorrect

**Impact**:
- This error appears during the build/startup phase
- The error is typically transient and may resolve on subsequent attempts
- If rpm-registry fails to start, consumer-redhat will be unable to install the RPM package

**Workarounds**:
1. **Run cleanup script**: Execute `./scripts/cleanup.sh` before starting orchestration
   ```bash
   ./scripts/cleanup.sh
   podman-compose up --build
   ```

2. **Manual cleanup**: Remove stale crun state manually
   ```bash
   rm -rf /run/user/$(id -u)/crun/*
   ```

3. **Full system cleanup**: Use podman system reset (WARNING: removes all containers and images)
   ```bash
   podman system reset
   ./scripts/create-network.sh
   ```

4. **Retry**: Simply re-running the orchestration often resolves the issue

**Notes**:
- This issue is specific to rootless podman with crun runtime
- The `/run/user/1000/` path indicates rootless mode (user ID 1000)
- This is a known issue in some versions of crun/podman and typically doesn't indicate a problem with the application code

**References**:
- [crun issue tracker](https://github.com/containers/crun/issues)
- [podman issue tracker](https://github.com/containers/podman/issues)
