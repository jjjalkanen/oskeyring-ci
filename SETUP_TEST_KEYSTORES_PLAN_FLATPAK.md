Let's now make a new version of the installed app so that it does 
roughly the following on the Arch/Flatpak system and the same as before
on the other systems. We should add macros which detect for which
platform the release is built and then depending on build settings,
attempt to work with the Snap secure storage and print out an informative
error message if something goes wrong or if all works out, "All good"
just like before. In all cases, the happy path should print out "All good"
so that the test keeps working.
```
#include <portal/portal.h>          /* libportal ≥1.6 */
#include <stdio.h>

int main(void)
{
    GError *error = NULL;
    g_autoptr(XdpPortal) p = xdp_portal_new_sync(NULL, &error);
    if (!p) { g_printerr("portal: %s\n", error->message); return 1; }

    /* Here we should have write section like we do for snap */
    /* We should use the same "Secret created" payload for consistency */
    /* If the thing doesn't exist, we should create it and exit */
    /* like we do for snap. */

    /* Ask the Secret portal for the 1-KiB “bag” associated with this app-id */
    g_autoptr(GBytes) bytes =
        xdp_portal_secret_retrieve_sync(p, 1024, NULL, &error);
    if (!bytes) { g_printerr("retrieve: %s\n", error->message); return 1; }

    /* If the data already exists, we should retrieve it,
     * just like we do for snap. We should report errors and print out the same thing
     * as we print out with snap. */

    gsize len;
    const char *data = g_bytes_get_data(bytes, &len);
    printf("got %zu secret bytes – first 8: %.8s\n", len, data);
}

```

This new version of the app is to be installed only on the Flatpak + Arch
podman container, the other platforms should remain as they are now, we'll deal with them later.

Please feel free to improve the code and make it Rust!

We will also need following kind of manifest for Flatpak:
```
{
  "id" : "io.example.SecretDemo",
  "runtime" : "org.freedesktop.Platform",
  "runtime-version" : "24.08",
  "sdk" : "org.freedesktop.Sdk",
  "command" : "secret-demo",
  "finish-args" : [
    /* No need to poke holes: the Secret portal is available automatically
       inside every flatpak sandbox. */
  ],
  "modules" : [
    {
      "name" : "secret-demo",
      "buildsystem" : "simple",
      "build-commands" : [
        "cc secret-demo.c `pkg-config --cflags --libs libportal-gtk4` -o secret-demo"
      ],
      "sources" : [ "secret-demo.c" ]
    }
  ]
}
```

Please verify that the manifest aligns with good practices and make the names uniform.

Then, package the Flatpak + Arch build of the application like
```
flatpak-builder build-dir io.example.SecretDemo.json
```
and have it installed at the Flatpak + Arch system like
```
flatpak install --user build-dir/io.example.SecretDemo.flatpak
```
and then complicate the testing by running the application twice
```
flatpak run io.example.SecretDemo                  # exit if we print something else than “Secret created”
flatpak run io.example.SecretDemo                  # should print “Stored secret”
```
Additionally, our script should try to read the data and fail, before reporting "All good".
