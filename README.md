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
[`.github/workflows/release.yml`](.github/workflows/release.yml), triggered
by pushing a `vX.Y.Z` tag or running it manually from the Actions tab. They
are currently uploaded as workflow artifacts only (90-day retention) — not
yet published anywhere public.

## Upstream credit

Files365 is a rebrand built on top of the
[Nextcloud desktop client](https://github.com/nextcloud/desktop), licensed
**GPL-2.0-or-later** (see [`COPYING`](COPYING)). All credit for the
underlying sync engine, protocol implementation, and application
architecture goes to Nextcloud GmbH and the Nextcloud contributors — see
[`AUTHORS.md`](AUTHORS.md) for the full list. This repository keeps
Nextcloud's original license and copyright headers on unmodified files, per
the terms of the GPL.
