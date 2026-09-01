# Files365 update server setup

The desktop client checks for new versions by making an HTTP GET request to
one URL and expecting a small XML document back. This document describes
that contract so a server can be built to satisfy it, and where to plug the
real URL in once that server exists.

## Where the URL is configured today

`NEXTCLOUD.cmake` defines a single variable that everything else derives
from:

```cmake
set( FILES365_UPDATE_URL "https://updates.files365.example.com" CACHE STRING "..." )
```

**This is the only line to change** once a real server exists. Everything
else (`config.h`, `Theme::updateCheckUrl()`, `src/gui/updater/updater.cpp`)
reads from it automatically at build time - no other file needs to be
touched.

You can also override it per-build without editing the file, e.g.:

```
cmake -S . -B build -DFILES365_UPDATE_URL=https://updates.files365.com
```

## What the client actually requests

At startup (and periodically after), the client builds a GET request to
`FILES365_UPDATE_URL` with query parameters appended
(see `Updater::getQueryParams()` in `src/gui/updater/updater.cpp`):

| Param | Example | Meaning |
|---|---|---|
| `version` | `0.0.0-dev` | Current installed client version |
| `platform` | `macos`, `win32`, `linux` | OS family |
| `osRelease` | `macos` | `QSysInfo::productType()` |
| `osVersion` | `15.5` | OS version |
| `buildArch` | `x86_64` | Architecture the client was built for |
| `currentArch` | `arm64` | Architecture actually running |
| `oem` | `Files365` | `Theme::appName()` |
| `channel` | `stable` | Update channel (user-configurable) |
| `versionsuffix` | `` | Build suffix, if any |
| `client` | (base64, Linux only) | `lsb_release -a` output |
| `msi` | `true` | Present only on Windows |

Example real request:

```
GET https://updates.files365.example.com/?version=1.0.0&platform=macos&osRelease=macos&osVersion=15.5&buildArch=arm64&currentArch=arm64&oem=Files365&channel=stable&versionsuffix=
```

The server is free to ignore all of these and always serve the same
response, or use them to decide what to offer (e.g. serve nothing - see
below - if the requesting `version` is already current).

## Required response format

Respond with `Content-Type: text/xml` (or anything Qt's `QDomDocument` will
parse) and this exact shape - element names are hardcoded in
`src/gui/updater/updateinfo.cpp` and are **not** configurable:

```xml
<?xml version="1.0"?>
<owncloudclient>
  <version>1.0.0.0</version>
  <versionstring>1.0.0</versionstring>
  <web>https://files365.example.com/changelog</web>
  <downloadurl>https://updates.files365.example.com/downloads/Files365-1.0.0-macOS.dmg</downloadurl>
</owncloudclient>
```

| Element | Meaning |
|---|---|
| `<version>` | Machine-comparable version (used to decide "is this newer than what's installed") |
| `<versionstring>` | Human-readable version shown in the update dialog |
| `<web>` | Link shown to the user (e.g. changelog / release notes page) |
| `<downloadurl>` | Direct link to the installer for the platform that requested it |

**If there is no update available, return an empty or malformed response**
(e.g. HTTP 204, or a body that isn't a valid `<owncloudclient>` document).
The client treats a parse failure as "no update info available" and stays
silent - it does not show an error to the user.

Since the request includes `platform` (`macos` / `win32` / `linux`), a
single endpoint can serve the right `<downloadurl>` per platform, or you can
route to different backend logic per platform - the client doesn't care,
it just needs one XML document back per request.

## Testing before you have real infrastructure

You don't need a real server to test this end to end. Run any static file
server locally and point a debug build at it:

```bash
# Terminal 1: serve a fake response
mkdir -p /tmp/fake-update-server && cd /tmp/fake-update-server
cat > response.xml << 'EOF'
<?xml version="1.0"?>
<owncloudclient>
  <version>99.0.0.0</version>
  <versionstring>99.0.0 (test)</versionstring>
  <web>https://example.com/changelog</web>
  <downloadurl>https://example.com/fake.dmg</downloadurl>
</owncloudclient>
EOF
python3 -m http.server 8080

# Terminal 2: build pointing at it
cmake -S . -B build -DFILES365_UPDATE_URL=http://127.0.0.1:8080/response.xml
cmake --build build --target nextcloud
```

Run the built app and check its logs for the `nextcloud.gui.updater`
category - it prints the resolved URL and whether parsing succeeded. On
success, the app should show an "update available" notification pointing at
version `99.0.0 (test)`.

`NEXTCLOUD_DEV` builds can also override the URL at runtime without
rebuilding, via the `OCC_UPDATE_URL` environment variable (see
`Updater::updateUrl()`), which is handy for quick iteration.

## Checklist for when the real server exists

1. Decide the response strategy: static XML per platform, or a small
   backend that reads the query params and returns the right XML.
2. Host the actual installer files somewhere `<downloadurl>` can point to
   (the release workflow's artifacts aren't public downloads - see the main
   `README.md` - so the installers need to be copied/published there
   separately).
3. Change **one line** in `NEXTCLOUD.cmake`:
   `FILES365_UPDATE_URL` -> your real base URL.
4. Rebuild and ship - no other source file needs to change.
5. Test with the local-server steps above pointed at the real URL before
   trusting it in a production build.
