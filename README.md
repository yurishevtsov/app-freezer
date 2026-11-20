# AppFreezer

A tiny macOS app that freezes and resumes running apps, so you can see how
things behave when an app hangs (for example, under memory pressure).

Freezing an app sends `SIGSTOP` to its main process and to every helper
process that runs from inside its `.app` bundle. Resuming sends `SIGCONT`.
It is the same as `killall -STOP "App Name"` / `killall -CONT "App Name"`,
plus the helpers (Chrome, Electron apps, and so on).

- Window and menu bar item (snowflake) to freeze/resume any app
- Shows apps frozen from Terminal too (reads the real process state)
- Quitting AppFreezer resumes every app it froze
- System, light, or dark appearance (moon/sun icon in the window header)

Requires macOS 14 (Sonoma) or later.

## Install

```bash
brew tap yurishevtsov/app-freezer https://github.com/yurishevtsov/app-freezer
brew trust yurishevtsov/app-freezer
brew install --cask app-freezer
```

Homebrew 7 only loads casks from taps you trust, hence `brew trust`.

The app is ad-hoc signed, not notarized by Apple. The cask removes the
quarantine flag after install so macOS lets it open.

## Build from source

```bash
./build.sh
open AppFreezer.app
```

Only the Xcode Command Line Tools are needed. `build.sh` makes a universal
(Apple silicon + Intel) app. It generates `AppIcon.icns` with
`make-icon.swift` if the file is missing.

## Release

```bash
git tag v1.2.0
git push origin v1.2.0
```

The [release workflow](.github/workflows/release.yml) builds the app,
publishes a GitHub release with `AppFreezer.zip`, and updates the version
and checksum in [`Casks/app-freezer.rb`](Casks/app-freezer.rb).

## Caveats

- Helpers that live outside the app bundle keep running. Safari's web
  content processes are an example.
- Freezing a terminal app freezes only the terminal, not the shells in it.
- Freezing the app that runs your current tools (for example, Claude) will
  freeze those tools too.
