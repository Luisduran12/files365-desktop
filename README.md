<!--
  - SPDX-FileCopyrightText: 2026 Files365 contributors
  - SPDX-License-Identifier: GPL-2.0-or-later
-->

# Files365

Files365 desktop sync client — a rebrand of the Nextcloud desktop client.

## Status

🚧 **In development.** The app builds and runs; the distribution/update
server is not deployed yet, so there is no public download or auto-update
feed available today. See [`docs/SERVER_SETUP.md`](docs/SERVER_SETUP.md)
for what's needed to stand one up, and what changes (one URL) once it
exists.

## Building

This project builds with CMake + Qt6, the same way as upstream Nextcloud
desktop. See [`AGENTS.md`](AGENTS.md) and [`CONTRIBUTING.md`](CONTRIBUTING.md)
for build instructions inherited from upstream.

Release builds for macOS (`.dmg`) and Windows (installer) are produced by
[`.github/workflows/release.yml`](.github/workflows/release.yml). Pushing a
`vX.Y.Z` tag builds both platforms and, if both succeed, publishes a GitHub
Release with the two installers attached. Running the workflow manually from
the Actions tab produces workflow artifacts only (90-day retention), since
there is no tag to publish against.

## Versioning — read this before touching the release pipeline

The release version is **not** stored in the repo. It comes from the pushed
git tag, and has to be threaded all the way down into the compiled binary:

```
git tag vX.Y.Z
 └─ release.yml: version = ${GITHUB_REF_NAME#v}
     ├─ macOS:   cmake -DFILES365_RELEASE_VERSION=X.Y.Z
     └─ Windows: craft --options nextcloud-client.releaseVersion=X.Y.Z
                  └─ craft-blueprints-nextcloud passes the same -D flag
         └─ VERSION.cmake → version.h (MIRALL_VERSION_STRING)
             └─ Utility::userAgentString() → "mirall/X.Y.Z" on every request
```

That last hop is why this matters. Nextcloud servers run
`BlockLegacyClientPlugin`, which parses `mirall/<version>` out of the
User-Agent and returns **403 Forbidden** for anything below
`minimum.supported.desktop.version`. A build that loses its version reports
`mirall/0.0.0` and cannot sync with any server: it installs and launches
fine, then fails right after "Grant access" with *"This version of the
client is unsupported."* That is what shipped as v3.4.3 — the Windows leg
goes through Craft, which was never passed the flag, so `VERSION.cmake`
quietly fell back to `0.0.0-dev`.

Two guards now make that failure loud instead of silent:

- **`VERSION.cmake`** aborts the build when a tag build never received
  `FILES365_RELEASE_VERSION`, or when the value isn't a plain `X.Y.Z`.
- **`release.yml`** asks each built binary which version it reports and
  fails the job on a mismatch, before anything is packaged or published.

Local builds without the flag still work — they warn and produce
`0.0.0-dev`. Note the Windows path runs through a **fork** of the craft
blueprint
([`stable-34.0-files365`](https://github.com/Luisduran12/craft-blueprints-nextcloud/tree/stable-34.0-files365)),
which also carries the installer's Files365 branding, so a change to how the
version is injected usually needs a matching change there.

## Upstream credit

Files365 is a rebrand built on top of the
[Nextcloud desktop client](https://github.com/nextcloud/desktop), licensed
**GPL-2.0-or-later** (see [`COPYING`](COPYING)). All credit for the
underlying sync engine, protocol implementation, and application
architecture goes to Nextcloud GmbH and the Nextcloud contributors — see
[`AUTHORS.md`](AUTHORS.md) for the full list. This repository keeps
Nextcloud's original license and copyright headers on unmodified files, per
the terms of the GPL.
