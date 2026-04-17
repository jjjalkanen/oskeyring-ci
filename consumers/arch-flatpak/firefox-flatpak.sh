#!/bin/bash
# Wrapper that forwards CREDENTIALS_DIRECTORY into the flatpak sandbox
# and grants filesystem access to temp directories used by idb-verify.py.
FLATPAK_ARGS=()

if [ -n "$CREDENTIALS_DIRECTORY" ]; then
    FLATPAK_ARGS+=(--env=CREDENTIALS_DIRECTORY="$CREDENTIALS_DIRECTORY")
    FLATPAK_ARGS+=(--filesystem="$CREDENTIALS_DIRECTORY":ro)
fi

# Grant access to /tmp so Firefox can use temp profile directories
FLATPAK_ARGS+=(--filesystem=/tmp)

exec flatpak run "${FLATPAK_ARGS[@]}" org.mozilla.firefox "$@"
