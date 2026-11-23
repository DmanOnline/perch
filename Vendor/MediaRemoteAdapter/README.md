# MediaRemoteAdapter (vendored)

Source copy of [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter),
used under its BSD 3-Clause license (see `LICENSE` in this directory).

## Why

`MediaRemote.framework` is private and, since macOS 15.4, only answers
processes Apple entitles. `/usr/bin/perl` is one of them. Perch runs
`bin/mediaremote-adapter.pl` under it; the script loads
`MediaRemoteAdapter.framework`, which Perch embeds in `Contents/Frameworks`,
and streams Now Playing as JSON lines (`Perch/Modules/Music/NowPlayingService.swift`).

## Pin

- Upstream tag `v0.8.0`, commit `65714990277cb4d0415ebaf7fff6be3229362b28`.
- `include/`, `src/` (minus `src/test/*.m`, the test client) and
  `bin/mediaremote-adapter.pl` are byte-identical to that commit.
- Built from source by the `MediaRemoteAdapter` target in `project.yml`.
  No prebuilt binaries are checked in.

## Updating

1. Check out the new tag upstream.
2. Replace `include/`, `src/` (drop `src/test/*.m` again), `bin/` and `LICENSE`.
3. Add any new `.m` files' frameworks to `OTHER_LDFLAGS` in `project.yml` if needed.
4. Build, run Perch, play something, and check play/pause, skip and seek.
5. Update the pin above in the same commit.
