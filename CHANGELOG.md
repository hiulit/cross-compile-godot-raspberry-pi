# CHANGELOG

## [Unreleased]

* Up to date.

## [1.1.0] - 2021-03-08

### Added

- New option `--pack`: Packs all the binaries of the same Godot version and the same Raspberry Pi version.
- Auto add `-stable` suffix to versions, if not present.

### Changed

- Abbreviation for `--use-lto` to `-L`.
- Now `--use-lto` doesn't accept any parameters.

### Fixed

- Added `builtin_freetype=yes` to the SCons parameters to be able to compile `3.1` and `3.1.1`.
- Don't apply the audio fix if version is `master` or lower than `3.2.4`.
- The `--scons_jobs "all"` parameter wasn't being set correctly when coming from the config file.
- Platform name for each binary type wasn't being set correctly.
- Exit script if `git checkout` fails.

## [1.0.0] - 2021-03-03

- Released stable version.
