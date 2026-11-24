# Contributing to Perch

Thanks for wanting to help. Perch aims to feel like part of the Mac: small, fast, native, and quiet until something is worth showing. Contributions that keep it that way are very welcome.

## Ways to help

- **Report a bug** with the [bug form](https://github.com/DmanOnline/perch/issues/new?template=bug_report.yml). Your Perch and macOS version and your Mac model help most.
- **Vote on ideas**: a thumbs-up on an existing idea counts. The most wanted ones move up the [roadmap](README.md#roadmap).
- **Suggest a moment** with the [idea form](https://github.com/DmanOnline/perch/issues/new?template=feature_request.yml).
- **Ask or share** in [Discussions](https://github.com/DmanOnline/perch/discussions).
- **Send a pull request.** For anything bigger than a fix, open an issue first so we can agree on the shape before you spend the time.

## Building

You need macOS 15 or later and Xcode 26 or later.

```bash
brew install xcodegen
git clone https://github.com/DmanOnline/perch.git
cd perch
xcodegen generate
open Perch.xcodeproj
```

Run the tests with:

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination platform=macOS
```

Builds are signed ad hoc by default. If you have your own signing certificate, put its name in `Config/Local.xcconfig` (not in git) as `CODE_SIGN_IDENTITY`, so macOS keeps your permissions between builds.

## How the code is laid out

| Folder | What lives there |
|---|---|
| `Perch/Core` | The module contract, the arbiter that decides who gets the notch, preferences, haptics |
| `Perch/Notch` | The notch window, its animation, gestures and full-screen detection |
| `Perch/Modules` | One folder per module: Music, Timer, Shelf, Battery, Devices, HUD, Mirror, Privacy |
| `Perch/Settings` | The settings and welcome windows |
| `PerchTests` | Unit tests |

A new feature is usually a new module: something that conforms to `PerchModule`, says what it wants to show through an `Activity` with a priority, and brings its own compact view, open view and settings.

## What a good pull request looks like

- **One clear idea** per pull request.
- **Tests for logic.** Views do not need tests; parsing, timing and decisions do.
- **A screenshot or GIF** for anything you can see, and a note on how it animates.
- **No work while idle.** Perch uses 0% CPU when nothing changes; please keep it that way. No timers that run for nothing, no polling where a notification exists.
- **No new dependencies** without talking about it first.
- **Private APIs** are fine when there is no public way, as long as the code says why and fails gracefully when Apple removes them.

## License

Perch is GPL-3.0. By contributing you agree that your work is released under the same license.
