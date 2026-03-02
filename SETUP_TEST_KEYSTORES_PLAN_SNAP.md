Let's now make a new version of the installed app so that it does 
roughly the following on the Ubuntu/Snap system and the same as before
on the other systems. We should add macros which detect for which
platform the release is built and then depending on build settings,
attempt to work with the Snap secure storage and print out an informative
error message if something goes wrong or if all works out, "All good"
just like before. In all cases, the happy path should print out "All good"
so that the test keeps working.
```
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
int main(void)
{
    const char *path = getenv("SNAP_DATA");          /* /var/snap/secret-demo/current */
    char file[4096]; snprintf(file, sizeof file, "%s/secret.bin", path);

    /* -- first run: create a secret -- */
    struct stat st;
    if (stat(file, &st)) {
        FILE *f = fopen(file, "wb");
        fputs("Stored secret", f);
        fclose(f);
        puts("Secret created");
        return 0;
    }

    /* -- later runs: read it back -- */
    FILE *f = fopen(file, "rb"); char buf[64] = {};
    fread(buf, 1, sizeof buf, f); fclose(f);
    printf("Secret read from SNAP_DATA: %.20s\n", buf);
}
```

This new version of the app is to be installed only on the Snap + Ubuntu 
VC, the other platforms should remain as they are now, we'll deal with them later.

Please feel free to improve the code!

Then, package the Ubuntu + Snap build of the application like
```
snapcraft --use-lxd         # produces the snap installable, say access_keyring_0.1_amd64.snap
```
and have it installed at the Ubuntu + snap system like 
```
sudo snap install --dangerous access_keyring_0.1_amd64.snap
```
and then complicate the testing by running the application twice
```
secret-demo                  # exit if we print something else than “Secret created”
secret-demo                  # should print “Stored secret”
```
Additionally, our script should try to read the data at /var/snap/secret-demo/current and fail, before reporting "All good".
