# Installing the source SDK

Mojo 1.1.0 and Linux x86-64 are the tested baseline. Install the native libraries
listed in [DEPENDENCIES.md](DEPENDENCIES.md), then use a fresh installation prefix:

```sh
scripts/install --prefix "$HOME/.local/mojo-s3"
MOJO=mojo "$HOME/.local/mojo-s3/bin/mojo-s3-build" application.mojo application
./application
```

The build helper supplies the installed import directory and native linker paths.
It works outside this checkout and with spaces in the prefix. Reinstallation into
an occupied SDK prefix fails explicitly; use a new prefix for another version.
No compiled package ABI is assumed. Native libraries and the compiler are not
bundled; the deployment host still needs compatible native runtime libraries.

For vendored source, add `src` to the consumer's import path and use `scripts/build`
or supply the three native linker arguments. Pin the source commit in downstream
projects. `scripts/package` creates a versioned source archive; `scripts/check-release`
extracts it, installs it, and compiles/runs an independent consumer. `package.json`
is descriptive project metadata, not an npm package or official Mojo registry schema.

## MojoShelf evaluation

The public [MojoShelf specification](https://github.com/mojoshelf/mojoshelf/blob/main/specs/01_scope.md)
was reviewed on October 4, 2026. It is an experimental registry supporting
commit-pinned git submodules and Pixi source dependencies built with
`pixi-build-mojo`. A `shelf.toml` declares name/version and tin dependencies;
Pixi mode additionally needs a package/build configuration. Its public README
currently advertises its packaged CLI for osx-arm64 and a Cargo fallback.

A source tin could fit this SDK, but the consuming build must also supply the
native curl/crypto/XML linkage. This run did not install the CLI, test Pixi's
build backend, register a tin, or publish a version. No working `shelf add mojo-s3`
command is promised. The tested source-prefix route remains available while
registry/native-linker integration is qualified. Publication also requires a
pushed clean commit and an author token; this local-only run publishes nothing.
