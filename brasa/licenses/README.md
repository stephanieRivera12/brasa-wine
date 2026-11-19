# Licences and source code of this engine

This folder holds the licence of every component that ships inside the Brasa engine, one
sub-folder per component. The engine is a build of Wine (CodeWeavers' CrossOver 26.3.0 sources)
with one small patch and the libraries below, compiled for x86_64 (macOS 14 or later).

## Where the source code is

The exact source of everything below that is under the LGPL or the MPL is published, so you can
rebuild it:

- Wine with Brasa's patch and the build scripts: the `brasa-wine` repository
  (https://github.com/stephanieRivera12/brasa-wine). `brasa/deps.sh` and `brasa/build.sh` say how
  every library was compiled. Original CrossOver sources:
  https://www.codeweavers.com/crossover/source
- gmp, nettle, gnutls, freetype, SDL2 and libinotify-kqueue: the source archives of the versions
  used are attached to a release of the same repository, next to `brasa/deps.sh`.
- libtasn1 and libunistring are compiled inside libgnutls (they come with the gnutls source).
  nettle is linked statically into libgnutls.
- MoltenVK 1.2.10: the official binary, https://github.com/KhronosGroup/MoltenVK (tag v1.2.10-rc2).
- wine-mono 10.4.1 and wine-gecko 2.47.4, unchanged from https://dl.winehq.org/wine/wine-mono/ and
  https://dl.winehq.org/wine/wine-gecko/.

## Components

| Folder | Component | Licence |
|---|---|---|
| `wine` | Wine | LGPL 2.1 or later |
| `gmp` | gmp 6.3.0 | LGPL 3 or GPL 2 (dual) |
| `nettle` | nettle 3.10 | LGPL 3 or GPL 2 (dual) |
| `gnutls` | gnutls 3.8.3 | LGPL 2.1 or later |
| `libtasn1` | libtasn1, inside gnutls | LGPL 2.1 or later |
| `libunistring` | libunistring, inside gnutls | LGPL 3 or GPL 2 (dual) |
| `freetype` | freetype 2.13.3 | FreeType Licence (FTL) or GPL 2. Credit: "Portions of this software are copyright The FreeType Project (www.freetype.org). All rights reserved." |
| `moltenvk` | MoltenVK 1.2.10 | Apache 2.0 |
| `sdl2` | SDL2 2.30.12 | zlib |
| `libinotify` | libinotify-kqueue 20240724 | MIT |
| `dxmt` | DXMT v0.80 | MIT |
| `dxvk` | DXVK 1.10.3 | zlib |
| `mono` | wine-mono 10.4.1 | licence text from the wine-mono 10.4.1 tag (`COPYING`) |
| `gecko` | wine-gecko 2.47.4 | MPL and others: `LICENSE` and `license.html` from the wine-gecko 2.47.4 tag |

The DXMT and DXVK binaries are not inside this engine folder: the Brasa app adds them next to it.
Their licences are here because Brasa ships them.

Not included, ever: Apple's D3DMetal. The `winemetal` files that DXMT needs are added by the app,
not by this engine.
