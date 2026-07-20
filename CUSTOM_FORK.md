# Custom fork notes

This is a personal fork of [FluffyChat](https://github.com/krille-chan/fluffychat),
customized for Leigh's own use (Delay Send, bridge unification, cross-bridge
contact search). See `~/.claude/plans/in-this-project-i-spicy-hinton.md` on
the desktop this was built on for the full design.

## Branch strategy

- `main` tracks `upstream/main` (krille-chan/fluffychat) untouched.
- `custom` carries all local customizations as a small number of isolated
  commits, based on `main`. To pull upstream fixes:

  ```
  git fetch upstream
  git checkout custom
  git rebase upstream/main
  ```

## Baseline

- Forked from upstream commit `518b0d929` (2026-07-18).
- Built and verified (Linux + Android, unmodified) with:
  - Flutter 3.44.6 (stable channel), managed via `fvm`
  - Dart 3.12.2
  - Rust 1.97.1 (stable, via `rustup` — required for `flutter_vodozemac`'s
    native crypto build; a plain `rustc`/`cargo` without `rustup` on PATH is
    not sufficient, cargokit specifically looks for `rustup`)
  - Android SDK 37.0.0, NDK 28.2.13676358, Build-Tools 36.0.0/37.0.0

## Signing

Release builds are signed with a personal upload keystore at
`~/.android/matrix-flutter-release.jks` (not committed — gitignored via
`android/key.properties` + `android/.gitignore`). Password/details are in
`~/.android/matrix-flutter-keystore-info.txt` (local-only, mode 600). This
key must be reused for every future release build, or installed updates
will fail to apply (Android requires matching signatures to upgrade
in-place).
