# Changelog

All notable changes to Electron.jl are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [7.0.0] - unreleased

This release contains breaking changes. See [Migration](#migration) below.

### Added

- `isopen(app::Application)` reports whether an application is still running, the way
  `isopen(win::Window)` already did for windows.
- `run` accepts a `JSON.JSONText`, for both `Window` and `Application` targets, which gets you
  JavaScript syntax highlighting in editors that support it.
- `Application` takes a `startup_timeout` keyword (default 120 seconds), bounding how long it
  waits for the Electron process to connect back to Julia.
- `ApplicationClosedError` is a new exported exception type, thrown when a request cannot be
  completed because the Electron application has exited.
- `nodeIntegration` and `contextIsolation` can be overridden through the `webPreferences` entry of
  a window's options.
- The README has a Recipes section covering native dialogs, window event handling and opening a
  plain window.

### Changed

- **Breaking.** The secure cookie is no longer passed to the Electron process as a positional
  command line argument; it is passed in the `JULIA_ELECTRON_SECURE_COOKIE` environment variable
  instead. The Electron process now receives only `main.js`, the main pipe name and the sysnotify
  pipe name as positional arguments. Custom `mainjs` files must be updated.
- **Breaking.** HTML content larger than 64 KiB passed to `load(win, html)` or
  `Window(app, content)` is written to a temporary file and loaded over a `file://` URL rather
  than a `data:` URI. The document's origin and `window.location` differ accordingly. Content at
  or below the threshold is unaffected. Temporary files are deleted when the window is closed or
  the application exits.
- **Breaking.** A request against an application whose Electron process has exited, or whose
  connection has dropped, now throws `ApplicationClosedError`. Previously this surfaced as an
  `IOError` (broken pipe) or, in some interleavings, a `KeyError`. Calls against an object already
  known to be dead still throw the same `ErrorException` as before.
- `close(app)` waits for an in-flight request to complete rather than racing it.
- The `Pkg` dependency was replaced by the `Artifacts` standard library, which reduces load time
  and the size of bundled applications.
- `main.js` moved from `src/` to `src/js/`, alongside the new preload script. `Electron.MAIN_JS`
  still points at it.

### Fixed

- `run` is safe to call from several tasks at once. All communication with an Electron application
  now goes through a request channel owned by a single task, so concurrent calls no longer
  interleave their requests and collect each other's replies ([#38], [#43]).
- `sendMessageToJulia` is available to page scripts from the start. It is now defined by an
  Electron preload script rather than injected on `did-finish-load`, so inline `<head>` scripts,
  `window.onload` handlers and promise callbacks can call it ([#143], [#34]). Messages that arrive
  before Julia has learned the window's id are buffered and delivered once the `Window` exists,
  instead of being dropped.
- `Application()` reports an error naming the exit code when the Electron process dies at startup,
  instead of blocking in `accept` forever. This is what happens on distributions that do not
  provide the expected system libraries; the README has a note on running under `nix-ld` or an FHS
  environment on NixOS ([#127]).
- `sendMessageToJulia(undefined)` delivers `nothing` to the message channel instead of taking the
  whole application down ([#144]).
- `ElectronAPI` calls with no arguments no longer fail with a JavaScript `TypeError` under
  JSON.jl v1, which serialised the empty argument list as `{}` rather than `[]`.
- The error handler in the notification loop no longer throws an error of its own; it called
  `print_with_color`, which no longer exists in Julia.

### Security

- The secure cookie no longer appears in the process table. It is passed through the child
  process's environment and removed from `process.env` as soon as `main.js` has read it, so it
  does not leak into the renderer, GPU or other processes Electron spawns. See the corresponding
  entry under [Changed](#changed).

### Migration

#### Custom `main.js`

Only affects code passing `Application(mainjs=...)`. The positional arguments dropped from four to
three, and the cookie moved to the environment.

Before:

```js
// main.js, main_pipe_name, sysnotify_pipe_name, secure_cookie_encoded
if (mainjs_index === -1 || mainjs_index + 3 >= process.argv.length) { /* ... */ }

var main_pipe_name = process.argv[mainjs_index + 1];
var sysnotify_pipe_name = process.argv[mainjs_index + 2];
var secure_cookie_encoded = process.argv[mainjs_index + 3];
```

After:

```js
// main.js, main_pipe_name, sysnotify_pipe_name
if (mainjs_index === -1 || mainjs_index + 2 >= process.argv.length) { /* ... */ }

var main_pipe_name = process.argv[mainjs_index + 1];
var sysnotify_pipe_name = process.argv[mainjs_index + 2];

var SECURE_COOKIE_ENV_VAR = 'JULIA_ELECTRON_SECURE_COOKIE';
var secure_cookie_encoded = process.env[SECURE_COOKIE_ENV_VAR];
delete process.env[SECURE_COOKIE_ENV_VAR];  // keep it out of Electron's child processes
```

`src/js/main.js` in this repository is the reference implementation.

#### Catching errors from a dead application

`ApplicationClosedError` subtypes `Exception`, not `ErrorException`, so a handler written as
`catch err; err isa ErrorException` will no longer match. Catch it by name:

```julia
try
    run(app, "1 + 1")
catch err
    err isa ApplicationClosedError || rethrow()
    # the Electron process is gone; start a new Application if you need one
end
```

If you hold on to an `Application` and want to check before using it rather than handle an
exception, use `isopen(app)`.

#### Large HTML content

Above 64 KiB, the document is served from a temporary file, so `window.location` is a `file://`
URL instead of a `data:` URI. Page code that inspects `window.location`, or that relies on the
opaque origin of a data URI, needs adjusting. Nothing needs to be cleaned up by hand: the
temporary file is removed when the window is closed or the application exits.

#### `close(app)` ordering

`close(app)` now blocks until any request already in flight on that application has completed.
Code that closed an application while a long-running JavaScript call was outstanding will now wait
for that call instead of racing it.

## 6.1.1 – 3.0.0 (2025-11-04 – 2020-07-22)

These releases predate this changelog and were never written up. See the
[releases page](https://github.com/davidanthoff/Electron.jl/releases) and
[the full comparison](https://github.com/davidanthoff/Electron.jl/compare/v2.0.1...v6.1.1) for
what changed.

## [2.0.1] - 2019-11-30

### Fixed

- Tag the right version.

## [2.0.0] - 2019-11-30

### Added

- FilePaths integration.
- Errors in the renderer are handled.

### Changed

- Update Electron to version 7.1.2.
- Use the artifact system.

### Removed

- Support for Julia versions before 1.3.
- Support for the functionality in the contrib folder.

## [1.1.0] - 2019-11-22

### Added

- `ElectronAPI`.
- `prep_test_env` function.

### Changed

- Update Electron to version 4.2.12.

### Fixed

- A bug on Julia 1.3.

## [1.0.0] - 2019-05-20

### Changed

- Update Electron to version 4.1.4.

## [0.4.0] - 2019-01-06

### Added

- `load` function.

## [0.3.0] - 2018-10-31

### Added

- Support for callbacks from Electron to Julia.

## [0.2.0] - 2018-08-10

### Added

- Julia 0.7 support.

### Removed

- Julia 0.6 support.

## [0.1.2] - 2018-04-27

### Changed

- Update Electron to version 1.8.4.

### Fixed

- Make `build.jl` more robust.
- General reliability improvements.

## [0.1.1] - 2018-02-20

### Fixed

- A bug in `build.jl` on Windows.

## [0.1.0] - 2018-02-14

### Added

- Window and application management.
- More ways to construct windows.

## [0.0.1] - 2018-02-10

### Added

- Initial version.

[#34]: https://github.com/davidanthoff/Electron.jl/issues/34
[#38]: https://github.com/davidanthoff/Electron.jl/issues/38
[#43]: https://github.com/davidanthoff/Electron.jl/issues/43
[#127]: https://github.com/davidanthoff/Electron.jl/issues/127
[#143]: https://github.com/davidanthoff/Electron.jl/issues/143
[#144]: https://github.com/davidanthoff/Electron.jl/issues/144

[7.0.0]: https://github.com/davidanthoff/Electron.jl/compare/v6.1.1...main
[2.0.1]: https://github.com/davidanthoff/Electron.jl/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/davidanthoff/Electron.jl/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/davidanthoff/Electron.jl/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/davidanthoff/Electron.jl/compare/v0.4.0...v1.0.0
[0.4.0]: https://github.com/davidanthoff/Electron.jl/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/davidanthoff/Electron.jl/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/davidanthoff/Electron.jl/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/davidanthoff/Electron.jl/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/davidanthoff/Electron.jl/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/davidanthoff/Electron.jl/compare/v0.0.1...v0.1.0
[0.0.1]: https://github.com/davidanthoff/Electron.jl/releases/tag/v0.0.1
