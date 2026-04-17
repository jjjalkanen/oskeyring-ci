# Firefox Credential Daemon — Security Hardening

Summary of hardening applied to the `firefox-credential-server` daemon and supporting infrastructure.

## Systemd Sandboxing

The service unit now runs with a restrictive security profile:

- **NoNewPrivileges** — prevents privilege escalation via setuid/setgid binaries
- **ProtectSystem=strict** — mounts the entire filesystem read-only (except `RuntimeDirectory`)
- **ProtectHome / PrivateTmp** — hides user home directories; isolates `/tmp`
- **MemoryDenyWriteExecute** — blocks W+X memory mappings (prevents shellcode injection)
- **LockPersonality** — locks the execution domain
- **RestrictNamespaces** — prevents namespace creation (no container escape)
- **RestrictAddressFamilies=AF_UNIX** — only Unix sockets allowed (no network access)
- **SystemCallFilter=@system-service** — whitelist-based syscall filtering
- **SystemCallArchitectures=native** — blocks compat-mode syscall ABIs
- **LimitNOFILE=64** — caps file descriptors to prevent fd exhaustion

## Key Memory Protection

- Key is stored in a `Zeroizing<Vec<u8>>` wrapper that guarantees zeroing on drop
- `mlock()` pins the key in RAM, preventing it from being swapped to disk
- `prctl(PR_SET_DUMPABLE, 0)` disables core dumps and blocks `ptrace` attachment

## Connection Hardening

- **Write timeout (5s)** — prevents slow/malicious clients from blocking the accept loop
- **Per-UID rate limiting (100ms)** — mitigates socket flooding from any single user
- **Socket permissions 0o666** — corrected from 0o777 (execute bit is meaningless for sockets)

## Upgraded Binary Tolerance

The `/proc/pid/exe` check now strips the ` (deleted)` suffix that the kernel appends when a binary is replaced on disk while still running. Firefox processes that survive a package upgrade are no longer rejected.

## Temporary Key File Elimination

Key generation in RPM `%post`, `consumers/redhat-rpm/upgrade.sh`, and `consumers/debian-apt/upgrade.sh` no longer writes the raw key to `/tmp`. The key is piped directly from `/dev/urandom` into `systemd-creds encrypt`, eliminating the window where an unencrypted key is visible on the filesystem.

## Client-Side Daemon Authentication

The Firefox C++ client (`EncryptionKeyManager.cpp`) now verifies:

1. **Socket ownership** — `CreateProvider()` checks `st_uid == 0` on the socket file before selecting the socket backend
2. **Daemon identity** — `RetrieveKey()` calls `getsockopt(SO_PEERCRED)` after connecting and rejects any daemon not running as root (UID 0)

This prevents a non-root attacker from racing to place a rogue socket and serving a chosen key.

## Remaining Architectural Limitations

These are known trade-offs, not bugs:

- The daemon runs as root because `LoadCredentialEncrypted` decryption requires it; sandboxing constrains the root process instead
- The encryption key is system-wide (machine-bound, not per-user) — this is the design intent for single-user desktops
- The TOCTOU window between `SO_PEERCRED` and `/proc/pid/exe` readlink is inherent to this verification approach; the window is sub-microsecond and unexploitable in practice
