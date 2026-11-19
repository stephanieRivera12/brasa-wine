# brasa

Build scripts of the Brasa Wine engine.

## Origin

The source of this repository is `sources/wine` from CodeWeavers' `crossover-sources-26.3.0`
(https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz, linked from
https://www.codeweavers.com/crossover/source). The first commit imports it unchanged.

## What changes against CodeWeavers

Brasa adds two things: the scripts and tests in `brasa/`, and the "per-program extra command-line
options" patch in `dlls/kernelbase` (`brasa_cmdline.c`, `brasa_cmdline.h`, `brasa_constants.h`, one
call in `process.c`, one line in `Makefile.in`). The diff against the first commit is exactly that.

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
in a throwaway prefix; prints `PASS|FAIL <case>`), and `brasa/tests/test-run-lib.sh` for the pure
functions of the runner.

## Where each library comes from

All are built as x86_64 (run under Rosetta 2) with macOS 14 as the minimum, none from Homebrew.

| Library | Version | Source |
|---|---|---|
| gmp | 6.3.0 | `crossover-sources/gnutls/gmp` |
| nettle (static, inside gnutls) | 3.10 | official GNU tarball, SHA-256 in `constants.sh` |
| gnutls | 3.8.3 | `crossover-sources/gnutls/gnutls` |
| freetype | 2.13.3 | `crossover-sources/freetype` |
| SDL2 | 2.30.12 | official libsdl-org release, SHA-256 in `constants.sh` |
| libinotify-kqueue | 20240724 | official release, SHA-256 in `constants.sh` |
| MoltenVK | 1.2.10 | official KhronosGroup release, x86_64 slice only |

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
