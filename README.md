# Electron

[![Project Status: Active - The project has reached a stable, usable state and is being actively developed.](http://www.repostatus.org/badges/latest/active.svg)](http://www.repostatus.org/#active)
[![Build Status](https://travis-ci.org/davidanthoff/Electron.jl.svg?branch=master)](https://travis-ci.org/davidanthoff/Electron.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/isid8hq7hq1vwmfn/branch/master?svg=true)](https://ci.appveyor.com/project/davidanthoff/electron-jl/branch/master)
[![codecov](https://codecov.io/gh/davidanthoff/Electron.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/davidanthoff/Electron.jl)

## Overview

[Electron.jl](https://github.com/davidanthoff/Electron.jl) wraps the cross-platform desktop application framework [Electron](https://electronjs.org/). You can use it to build GUI applications in julia.

## Alternatives

[Blink.jl](https://github.com/JunoLab/Blink.jl) provides similar functionality (and was a major inspiration for this package!). The main difference between the two packages is that [Electron.jl](https://github.com/davidanthoff/Electron.jl) opts for a more minimalistic feature set than [Blink.jl](https://github.com/JunoLab/Blink.jl). Here are some key differences between the two packages:
* [Electron.jl](https://github.com/davidanthoff/Electron.jl) does not have any web server functionality.
* [Electron.jl](https://github.com/davidanthoff/Electron.jl) has no functionality to translate julia code to JavaScript.
* [Electron.jl](https://github.com/davidanthoff/Electron.jl) uses named pipes for the communication between julia and the electron process (no more firewall warnings!).
* [Electron.jl](https://github.com/davidanthoff/Electron.jl) doesn't integrate with the Juno stack of packages, [Blink.jl](https://github.com/JunoLab/Blink.jl) does in some way (that I don't understand).
* [Electron.jl](https://github.com/davidanthoff/Electron.jl) has a high test coverage.
* [Electron.jl](https://github.com/davidanthoff/Electron.jl) always installs a private copy of Electron during the build phase.

## Installation

You can install the package with:

````julia
Pkg.add("Electron")
````

## Getting started

[Electron.jl](https://github.com/davidanthoff/Electron.jl) introduces two fundamental types: ``Application`` represents a running electron application, ``Window`` is a visible UI window. A julia process can have arbitrarily many applications running at the same time, each represented by its own ``Application`` instance. If you don't want to deal with ``Application``s you can also just ignore them, in that case [Electron.jl](https://github.com/davidanthoff/Electron.jl) will create a default application for you automatically.

To create a new application, simply call the corresponding constructor:

````julia
using Electron

app = Application()
````

This will start a new Electron process that is ready to open windows or run JavaScript code.

To create a new window in an existing application, use the ``Window`` constructor:

````julia
using Electron, URIParser

app = Application()

win = Window(app, URI("file://main.html"))
````

Note that you need to pass a URI that points to an HTML file to the ``Window`` constructor. This HTML file will be displayed in the new window.

You can update pre-existing ``Window`` using function ``load``:

````julia
load(win, URI("http://julialang.org"))
load(win, """
<img src="https://raw.githubusercontent.com/JuliaGraphics/julia-logo-graphics/master/images/julia-logo-325-by-225.png">
""")
````

You can also call the ``Window`` constructor without passing an ``Application``, in that case [Electron.jl](https://github.com/davidanthoff/Electron.jl) creates a default application for you:

````julia
using Electron, URIParser

win = Window(URI("file://main.html"))
````

You can run JavaScript code both in the main or the render thread of a specific window. To run some JavaScript in the main thread, call the ``run`` function and pass an ``Application`` instance as the first argument:

````julia
using Electron, URIParser

app = Application()

result = run(app, "Math.log(10)")
````

The second argument of the ``run`` function is JavaScript code that will simply be executed as is in Electron.

You can also run JavaScript in the render thread of any open window by passing the corresponding ``Window`` instance as the first argument to ``run``:

````julia
using Electron, URIParser

win = Window(URI("file://main.html"))

result = run(win, "Math.log(10)")
````

You can send messages from a render thread back to julia by calling the javascript function ``sendMessageToJulia``. On the julia side, every window has a ``Channel`` for these messages. You can access the channel for a given window with the ``msgchannel`` function, and then use the standard julia API to take messages out of this channel:

````julia
using Electron

win = Window()

result = run(win, "sendMessageToJulia('foo')")

ch = msgchannel(win)

msg = take!(ch)

println(msg)
````

## Examples

The following packages currently use Electron.jl:

* https://github.com/davidanthoff/DataVoyager.jl
* https://github.com/davidanthoff/ElectronDisplay.jl

Please add any other packages that depend on Electron.jl to this list via
a pull request!
