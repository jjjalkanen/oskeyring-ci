## For Firefox Snap (Ubuntu)

Canonical includes a geckodriver alias in the snap itself so we can use the same trick.

 - The Binary Path: Use /snap/bin/firefox.
 - The Workaround: The TMPDIR environment variable must be set to a location that both the host and the Snap can access (usually somewhere under the current user's home directory).
```
# Bash
mkdir -p ~/tmp
export TMPDIR=~/tmp
./wpt run firefox [test_path] --binary=/snap/bin/firefox
```

## For Firefox Flatpak

Flatpak is tricky because it doesn't naturally expose the browser binary to the host's /usr/bin.

 - The Binary Path: Call it via `flatpak run org.mozilla.firefox`
 - WPT Configuration: WPT’s wptrunner expects a path to a literal executable. A "wrapper script" named firefox-flatpak can be created and WPT pointed to that:
```
# Bash
#!/bin/bash
flatpak run org.mozilla.firefox "$@"
```
 - Permissions: `Flatseal` or `flatpak override` may need to be used to give Firefox permission to access the specific directory where WPT is storing its temporary profiles.
