# Electron.jl unreleased

* **Breaking**: the secure cookie is no longer passed to the Electron process as a
  positional command line argument, it is now passed in the environment variable
  `JULIA_ELECTRON_SECURE_COOKIE` instead (command lines are visible to other users in the
  process table). The Electron process now receives only `main.js`, the main pipe name and
  the sysnotify pipe name as positional arguments. Anyone shipping a custom `mainjs` has to
  read the cookie from `process.env.JULIA_ELECTRON_SECURE_COOKIE` (and should
  `delete process.env.JULIA_ELECTRON_SECURE_COOKIE` right afterwards) instead of taking it
  from `process.argv`.
* Large HTML content passed to `load(win, html)` and `Window(app, content)` is now written
  to a temporary file and loaded via a `file://` URL instead of a `data:` URL, which fixes
  hangs and blank windows for payloads above a few hundred kilobytes. The temporary files
  are deleted when the window is closed or the application exits.

# Electron.jl v2.0.1 Release Notes
* Tag the right version

# Electron.jl v2.0.0 Release Notes
* Update Electron to version 7.1.2
* Use artifact system
* Drop pre Julia 1.3 support
* Drop support for functionality in contrib folder
* Handle errors in renderer
* Add FilePaths integration

# Electron.jl v1.1.0 Release Notes
* Add ElectronAPI
* Fix a bug on Julia 1.3
* Update Electron to version 4.2.12
* Add prep_test_env function

# Electron.jl v1.0.0 Release Notes
* Update Electron to version 4.1.4

# Electron.jl v0.4.0 Release Notes
* Add load function

# Electron.jl v0.3.0 Release Notes
* Add support for callbacks from Electron to julia

# Electron.jl v0.2.0 Release Notes
* Drop julia 0.6 support, add julia 0.7 support

# Electron.jl v0.1.2 Release Notes
* Update electron version to 1.8.4
* Make build.jl more robust
* General reliability improvements

# Electron.jl v0.1.1 Release Notes
* Fix bug in build.jl on Windows

# Electron.jl v0.1.0 Release Notes
* Window and application management added
* More ways to construct windows added
# Electron.jl v0.0.1 Release Notes
* Initial version
