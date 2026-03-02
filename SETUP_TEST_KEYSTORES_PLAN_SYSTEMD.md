Let's now make a new version of the installed app so that it does
roughly the following on the Debian and RedHat systems and the same as before
on the other systems. We should add macros which detect for which
platform the release is built and then depending on build settings,
attempt to work with the systemd based secure storage and print out an informative
error message if something goes wrong or if all works out, "All good"
just like before. In all cases, the happy path should print out "All good"
so that the test keeps working.

With systemd, no special libraries are expected and we can just query the
CREDENTIALS_DIRECTORY and then first read it, if we get nothing, write "Stored secret"
to it, just as in the other cases, and return, otherwise return the read value,
just like in the other cases. Here's an example program along these lines:
```
#include <stdio.h>
#include <stdlib.h>

int main() {
    const char *dir = getenv("CREDENTIALS_DIRECTORY");
    if (!dir) { fprintf(stderr, "no CREDENTIALS_DIRECTORY\n"); return 1; }

    char path[4096];
    snprintf(path, sizeof(path), "%s/demo-master", dir);

    FILE *f = fopen(path, "rb");
    if (!f) { perror("fopen"); return 1; }

    unsigned char buf[64];
    size_t n = fread(buf, 1, sizeof(buf), f);
    fclose(f);

    printf("CREDENTIALS_DIRECTORY=%s\n", dir);
    printf("Read %zu bytes from demo-master\n", n);
    return 0;
}

```

Please feel free to improve the code and make it Rust! Even if we have multiple of these test apps
right now, we are going to want to unify them eventually.

Another way to access the credentials in the app could be
```
std::ifstream s(std::getenv("CREDENTIALS_DIRECTORY")+std::string("/sync-key"));
```

When we install or update the app, we should also create the encrypted credential with
```
printf '%s' "0123456789abcdef…" > /tmp/raw.key
sudo systemd-creds encrypt --name=sync_key /tmp/raw.key ~/.local/share/demo/sync.cred
```
and then also ship a demo secret service
```
[Service]
LoadCredentialEncrypted=sync-key:~/.local/share/demo/sync.cred
KeyringMode=private
DynamicUser=yes
PrivateMounts=yes
```

Here, ~/.local/share/demo/ means that the credential should be stored by user so that the unprivileged
demo application above can access and update it.

In fact, it might be even better to avoid the service by launching transient units,
```
systemd-run --user --scope --property=LoadCredentialEncrypted=... --property=PrivateMounts=yes --property=KeyringMode=private /path/to/demo/app
```

The update takes place in a way similar to
```
# 1. Generate a new key
openssl rand -hex 32 > /tmp/new-sync.key

# 2. Encrypt it (same path, atomic if you want)
systemd-creds encrypt --name=sync-key \
  /tmp/new-sync.key ~/.local/share/demo/sync.cred.new

# 3. Swap in
mv ~/.local/share/demo/sync.cred.new ~/.local/share/demo/sync.cred

# 4. Next launch of demo app gets the new key
systemctl --user restart demo_secret.service
```

In fact, it might be best to version the credentials in a way similar to
```
~/.local/share/demo/sync.cred.v1
~/.local/share/demo/sync.cred.v2
# Update the drop-in:
LoadCredentialEncrypted=sync-key:/etc/firefox/sync.cred.v2
```

And then during an update, we should do `daemon-reexec` or `systemctl --user restart demo`

This new version of the app is to be installed on the Debian + apt and RedHat + rpm
podman containers having systemd, the other platforms should remain as they are now, they should be good already.

Additionally, our script should try to read the data and fail, before reporting "All good".
