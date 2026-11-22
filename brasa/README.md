# brasa

Build scripts of the Brasa Wine engine.

## Origin

The source of this repository is `sources/wine` from CodeWeavers' `crossover-sources-26.3.0`
(https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz, linked from
https://www.codeweavers.com/crossover/source). The first commit imports it unchanged.

## What changes against CodeWeavers

Brasa adds five things; the diff against the first commit is exactly these:

- the scripts and tests in `brasa/`;
- the "per-program extra command-line options" patch in `dlls/kernelbase` (`brasa_cmdline.c`,
  `brasa_cmdline.h`, `brasa_constants.h`, one call in `process.c`, one line in `Makefile.in`);
- `loader/wine_info.plist.in`: the two lines of CodeWeavers' "CrossOver Hack 10913" now carry Brasa's
  identity (bundle identifier `app.brasa.wineloader`, bundle name `Brasa`) instead of the CrossOver
  names;
- `programs/iexplore/iexplore.inf`: the display name of the HTML engine entry is "Wine HTML engine"
  instead of "CrossOver HTML engine";
- `dlls/ntdll/unix/socket.c`: on macOS a datagram received with `IP_RECVTOS` on carries its TOS in
  a control message of type `IP_RECVTOS`, not `IP_TOS`; it now reaches the program as `IP_TOS`, as on
  Windows. Without it Steam's networking sockets assert ("No control data returned even though we
  asked for TOS") and start `steamerrorreporter64` in every game that uses them.

Every other CodeWeavers patch is kept untouched.

### Per-program command-line options

Steam shows its login only if every `steamwebhelper.exe` starts with `--no-sandbox --in-process-gpu
--disable-gpu`. `CreateProcessInternalW` appends options from the registry key
`HKCU\Software\Brasa\AppendCommandLine`: one `REG_SZ` value per program, name = exe file name
(matched case-insensitively, without the path), data = options, added after a space at the end of the
line.

```sh
wine reg add 'HKCU\Software\Brasa\AppendCommandLine' /v steamwebhelper.exe /t REG_SZ \
  /d '--no-sandbox --in-process-gpu --disable-gpu' /f
```

Ignored, with a `warn:brasa` line naming only the exe and the reason (never the data or the command
line): a type other than `REG_SZ`, an empty value, more than 1024 characters, control characters
(newline, embedded NUL, DEL), a result of 32 767 characters or more (the system cuts the line at 32 766). The program starts anyway. The key
lives in the private Wine prefix, so it grants nothing a program in that prefix could not already do.

Tests: `brasa/tests/build-tests.sh && brasa/tests/run-tests.sh <engine root>` (spawns test programs
in a throwaway prefix; prints `PASS|FAIL <case>`; `receivesTos` covers the socket change), and `brasa/tests/test-run-lib.sh` for the pure
functions of the runner.

## Where each library comes from

All are built as x86_64 (run under Rosetta 2) with macOS 14 as the minimum, none from Homebrew.

| Library | Version | Source |
|---|---|---|
| gmp | 6.3.0 | CodeWeavers' `crossover-sources/gnutls/gmp` (packed in the source offer) |
| nettle (static, inside gnutls) | 3.10 | official GNU tarball, SHA-256 in `constants.sh` |
| gnutls | 3.8.13 | official tarball (gnupg.org), SHA-256 in `constants.sh`; built with an empty system priority file (no file on the Mac changes how the engine negotiates TLS); not CodeWeavers' 3.8.3, which lacks the fixes for CVE-2026-1584, -33845, -33846, -42009 and -42010 |
| freetype | 2.13.3 | official signed tarball (savannah.gnu.org), SHA-256 in `constants.sh`; CodeWeavers' checkout has the same `src/` and `include/` but no generated `configure` |
| SDL2 | 2.30.12 | official libsdl-org release, SHA-256 in `constants.sh` |
| libinotify-kqueue | 20240724 | official release, SHA-256 in `constants.sh` |
| MoltenVK | 1.2.10 | official KhronosGroup binary (tag v1.2.10-rc2, same commit as v1.2.10), SHA-256 in `constants.sh`, x86_64 slice only |

Only the tools come from Homebrew: `mingw-w64`, `bison`, `pkgconf`.

## How to build

```sh
brasa/deps.sh    # libraries, 20-40 min the first time
brasa/build.sh   # Wine, 1-2 h the first time
brasa/tests/test-lib.sh   # tests of the pure functions of the scripts
```

- A SHA-256 constant that is empty makes `deps.sh` print the computed hash and stop. Check it
  against the official page or signature and set it in `constants.sh`.
- Autoconf cannot build in a path with spaces, so the work happens in `~/.brasa-engine-work`
  (override with `BRASA_WORK_DIR`, no spaces). `<Brasa>/build/brasa-deps`, `brasa-deps-src`,
  `brasa-wine` and `brasa-wine-stage` are links to it.
- `build.sh` stops when `configure` reports a missing font, schannel, Vulkan, inotify or MinGW
  support. The engine lands in `build/brasa-wine-stage/opt/wine-brasa/`.
- Libraries are skipped when already built (marks in `brasa-deps/.stamps`). To change the
  `configure` flags of Wine, delete `~/.brasa-engine-work/brasa-wine` first.

## Packaging

`brasa/package.sh` turns the stage into `vendor/engines/wine-brasa-26.3.0-3/` (spec 5.5): real
copies of the libraries (never links into the work folder), wine-mono and wine-gecko unpacked in
`share/wine/`, licences in `licenses/`, debug info stripped (Mach-O with `strip -S`, PE dlls with
the mingw `strip`), a `VERSION` file, and no write permission for group or others. The DXMT files
that the spike left in the stage (`winemetal.*`) are left out: the app adds DXMT itself. The first
run stops with exit 3 and prints the SHA-256 of the three mono/gecko archives, to be checked and
pinned in `constants.sh`; it then checks the result with `brasa/check-engine.sh` before moving it.

`package.sh` needs the MoltenVK source archive that `fetch-third-party-sources.sh` downloads (run that first):
it looks for MoltenVK's `NOTICE` there and ships it; if the archive is missing, or a NOTICE sits at another path, it
stops (exit 10); if upstream has none, it says so and ships none.

`brasa/check-engine.sh <engine>` exits 0 only if every Mach-O is x86_64 and links only to
`@rpath`, `@loader_path`, `/usr/lib` and `/System`, no file holds a personal or build path, the
short sonames exist, mono/gecko and the licences are present, nothing is writable by others and no
link leaves the engine. Tests: `brasa/tests/test-engine-checks.sh`, `brasa/tests/test-package.sh`.

Size of the packaged engine 26.3.0-2: 943 MB (`du -sh`, 2026-11-20), of which mono and gecko are about 440 MB. CrossOver 26.3.0 takes 998 MB.

## Source offer

`brasa/fetch-third-party-sources.sh` gathers the source of every third-party component the engine
ships (spec 5.6) into `build/brasa-third-party-sources/`, with a `SHA256SUMS` (`shasum -a 256 -c`).
It packs the CodeWeavers gmp folder that `deps.sh` compiled, copies the nettle, gnutls, freetype,
SDL2 and libinotify-kqueue archives, and downloads the MoltenVK 1.2.10, wine-mono 10.4.1 and
wine-gecko 2.47.4 source archives. Every download is pinned in `constants.sh`; an empty constant
makes the script print the hash and stop (exit 3), a wrong one deletes the file (exit 4). Wine, the
patch and these scripts are the repository itself, so they are not in the archives.
Test: `brasa/tests/test-fetch-third-party-sources.sh`.
