module Electron

using JSON, URIs, Sockets, Base64, Artifacts, FilePaths, UUIDs
using RelocatableFolders

export Application, Window, URI, windows, applications, msgchannel, toggle_devtools, load, ElectronAPI,
    ApplicationClosedError

function conditional_electron_load()
    try
        return artifact"electronjs_app"
    catch
        return nothing
    end
end

function prep_test_env()
    if haskey(ENV, "GITHUB_ACTIONS") && ENV["GITHUB_ACTIONS"] == "true"
        if Sys.islinux()
            run(Cmd(`Xvfb :99 -screen 0 1024x768x24`), wait=false)
            ENV["DISPLAY"] = ":99"
        end
    end
end

const OptDict = Dict{String, Any}

struct JSError
    msg
end
Base.showerror(io::IO, e::JSError) = print(io, "JSError: ", e.msg)

"""
    ApplicationClosedError

Thrown when a request cannot be completed because the Electron application it was
addressed to has exited, or its connection to Julia was lost.
"""
struct ApplicationClosedError <: Exception
    msg::String
end
ApplicationClosedError() = ApplicationClosedError("The Electron application has exited.")
Base.showerror(io::IO, e::ApplicationClosedError) = print(io, e.msg)

# A single request that is handed to the task owning the connection to Electron,
# together with the channel on which its caller waits for the reply.
const _Request = Tuple{String,Channel{Any}}

mutable struct _Application{T} # forward declaration of Application
    connection::IO
    proc
    secure_cookie::Vector{UInt8}
    windows::Vector{T}
    exists::Bool
    # All communication over `connection` goes through this channel: callers put
    # requests on it, and one dedicated task (see `_start_connection_task!`) is the
    # only thing that ever reads from or writes to `connection`. The IPC protocol is
    # a strictly ordered sequence of request/response pairs, so this serialization is
    # what makes Electron.jl safe to use from several tasks at once.
    req_channel::Channel{_Request}
    # Messages that a page sent before the corresponding `Window` object existed
    # on the julia side. A preload script makes `sendMessageToJulia` available to
    # page scripts right away, so a page can send a message from e.g. an
    # `window.onload` handler before we have even learned the window's id.
    pending_msgs::Dict{Int64,Vector{Any}}

    global function _Application(::Type{T}, connection::IO, proc, secure_cookie) where {T} # internal constructor
        new_app = new{T}(connection, proc, secure_cookie, T[], true, Channel{_Request}(Inf), Dict{Int64,Vector{Any}}())
        push!(_global_applications, new_app)
        return new_app
    end
end

mutable struct Window
    app::_Application{Window}
    id::Int64
    exists::Bool
    msg_channel::Channel{Any}
    # Temporary HTML files that were created for this window (see `_html_url`). They are
    # deleted when the window is closed or when the application goes away.
    tmp_html_files::Vector{String}

    global function _Window(app::_Application{Window}, id::Int64; msg_channel_size=128) # internal constructor
        new_window = new(app, id, true, Channel{Any}(msg_channel_size), String[])
        push!(app.windows, new_window)
        # Deliver anything the page already sent before this object existed. This
        # must not yield, so that no message can slip in between the `push!`
        # above and the draining below.
        for msg in pop!(app.pending_msgs, id, Any[])
            put!(new_window.msg_channel, msg)
        end
        return new_window
    end
end

const Application = _Application{Window}

function Base.show(io::IO, app::Application)
    if app.exists
        if length(app.windows) == 1
            appstate = ", [1 window])"
        else
            appstate = ", [$(length(app.windows)) windows])"
        end
    else
        appstate = ", [dead])"
    end
    print(io, "Application(", app.connection, ", ", app.proc, appstate)
end


const _global_applications = Vector{Application}(undef,0)
const _global_default_application = Ref{Union{Nothing,Application}}(nothing)

function __init__()
    atexit() do # let Electron know we want it to die quietly and sanely
        for app in _global_applications
            if app.exists
                close(app)
            end
        end
    end
    nothing
end

function applications()
    return _global_applications
end

function default_application()
    if _global_default_application[]===nothing || _global_default_application[].exists==false
        _global_default_application[] = Application()
    end

    return _global_default_application[]
end

function windows(app::Application)
    return app.windows
end

function generate_pipe_name(name)
    return if Sys.iswindows()
        "\\\\.\\pipe\\$name"
    elseif Sys.isunix()
        joinpath(tempdir(), name)
    end
end

function get_electron_binary_cmd()
    electronjs_path = conditional_electron_load()

    if electronjs_path===nothing
        return "electron"
    elseif Sys.isapple()
        return joinpath(electronjs_path, "Julia.app", "Contents", "MacOS", "Julia")
    elseif Sys.iswindows()
        return joinpath(electronjs_path, "electron.exe")
    else # assume unix layout
        return joinpath(electronjs_path, "electron")
    end
end

# We relocate the whole `js` directory rather than just `main.js`, so that
# `main.js` can reliably find `preload.js` next to it via `__dirname`.
const JS_DIR = @path joinpath(@__DIR__, "js")
const MAIN_JS = joinpath(String(JS_DIR), "main.js")

# How long we are willing to wait for the Electron process to connect back to us
# before we give up. This is only a backstop against a process that is alive but
# never connects: a process that dies is detected immediately. It is deliberately
# generous, because Electron startup can be slow on loaded CI machines.
const DEFAULT_STARTUP_TIMEOUT = 120.0

function _electron_startup_error(proc, mainjs)
    exit_code = try
        proc.exitcode
    catch
        nothing
    end
    return ErrorException(string(
        "The Electron process exited",
        exit_code === nothing ? "" : " with code $(exit_code)",
        " before it connected back to Julia, so the application could not be started.\n",
        "Any output from Electron was printed above and usually explains why.\n",
        "On Linux distributions that do not provide the standard shared libraries in the ",
        "usual locations (NixOS, for example), the bundled Electron binary cannot find its ",
        "system dependencies (such as libgobject-2.0.so.0); see the Electron.jl README for ",
        "how to run it with nix-ld or inside an FHS environment.\n",
        "main.js used: ", mainjs))
end

"""
    _accept_or_fail(server, proc, mainjs, timeout)

Wait for the Electron process to connect to `server`, but do not wait forever: if
the process exits first, or if it stays silent for `timeout` seconds, throw an
error that says so instead of blocking in `accept` (see issue #127).
"""
function _accept_or_fail(server, proc, mainjs, timeout)
    # Buffered so that whichever tasks lose the race can still finish without
    # blocking on a channel nobody reads from any more.
    outcomes = Channel{Tuple{Symbol,Any}}(4)

    @async begin
        try
            put!(outcomes, (:connected, accept(server)))
        catch err
            try
                put!(outcomes, (:accept_failed, err))
            catch
            end
        end
    end

    @async begin
        try
            wait(proc)
        catch
        end
        try
            put!(outcomes, (:process_exited, nothing))
        catch
        end
    end

    timer = Timer(timeout)
    @async begin
        try
            wait(timer)
            put!(outcomes, (:timeout, nothing))
        catch
        end
    end

    kind, payload = take!(outcomes)
    close(timer)

    if kind === :connected
        return payload
    elseif kind === :process_exited
        throw(_electron_startup_error(proc, mainjs))
    elseif kind === :timeout
        error("The Electron process did not connect back to Julia within $(timeout) seconds, giving up.")
    else
        throw(payload)
    end
end

"""
Name of the environment variable through which the base64 encoded secure cookie is handed
to the Electron process. Must be kept in sync with `main.js`.
"""
const SECURE_COOKIE_ENV_VAR = "JULIA_ELECTRON_SECURE_COOKIE"

"""
    function Application()

Start a new Electron application. This will start a new process
for that Electron app and return an instance of `Application` that
can be used in the construction of Electron windows.

# Arguments
- `mainjs`: Path to the main JavaScript file for the Electron app (default: built-in main.js)
- `sandbox`: Whether to enable Electron's sandbox (default: `false`). Set to `true` for enhanced security when possible.
- `verbose`: Enable verbose logging output (default: `false`)
- `additional_electron_args`: Additional command-line arguments to pass to Electron (default: empty)
- `startup_timeout`: How many seconds to wait for the Electron process to connect back
  to Julia before giving up (default: `$(DEFAULT_STARTUP_TIMEOUT)`). If the Electron process
  exits before that, an error is thrown right away.

# Note
For advanced Electron configuration, pass specific flags via `additional_electron_args`.
For example, to enable remote debugging: `additional_electron_args=["--remote-debugging-port=9222"]`
"""
function Application(;
    mainjs=normpath(String(MAIN_JS)),
    additional_electron_args=String[],
    sandbox::Bool=false,
    verbose::Bool=false,
    startup_timeout::Real=DEFAULT_STARTUP_TIMEOUT
)
    @assert isfile(mainjs)
    read(mainjs) # This seems to be required to not hang windows CI?!
    electron_path = get_electron_binary_cmd()

    id = replace(string(uuid1()), "-"=>"")
    main_pipe_name = generate_pipe_name("jlel-$id")
    server = listen(main_pipe_name)

    id = replace(string(uuid1()), "-"=>"")
    sysnotify_pipe_name = generate_pipe_name("jlel-sn-$id")
    sysnotify_server = listen(sysnotify_pipe_name)

    secure_cookie = rand(UInt8, 128)
    secure_cookie_encoded = base64encode(secure_cookie)
    # proc = open(`$electron_path --inspect-brk=5858 $mainjs $main_pipe_name $sysnotify_pipe_name`, "w", stdout)

    # Build command arguments, placing flags before the main.js file
    electron_cmd_args = [electron_path]

    # Add --no-sandbox flag if sandbox is disabled (default: disabled for compatibility with Ubuntu and remote SSH)
    if !sandbox
        push!(electron_cmd_args, "--no-sandbox")
    end

    # Add verbose logging flags
    if verbose
        push!(electron_cmd_args, "--verbose")
        push!(electron_cmd_args, "--enable-logging")
        push!(electron_cmd_args, "--log-level=info")
    end

    # Add the main script and its arguments
    # Note: the secure cookie is deliberately NOT passed on the command line, because
    # command lines are visible to other users in the process table. It is handed to the
    # child process via the environment instead (see `new_env` below).
    append!(electron_cmd_args, [
        mainjs,
        main_pipe_name,
        sysnotify_pipe_name
    ])

    # Add additional electron args at the end
    append!(electron_cmd_args, additional_electron_args)

    electron_cmd = Cmd(electron_cmd_args)

    new_env = copy(ENV)
    if haskey(new_env, "ELECTRON_RUN_AS_NODE")
        delete!(new_env, "ELECTRON_RUN_AS_NODE")
    end
    # The secure cookie travels in the (private) environment of the child process rather
    # than on its command line. main.js deletes it from `process.env` right after reading
    # it, so it is not inherited by anything Electron itself spawns.
    new_env[SECURE_COOKIE_ENV_VAR] = secure_cookie_encoded

    proc = open(Cmd(electron_cmd, env=new_env), "w", stdout)

    sock = nothing
    sysnotify_sock = nothing
    try
        sock = _accept_or_fail(server, proc, mainjs, startup_timeout)
        if read!(sock, zero(secure_cookie)) != secure_cookie
            error("Electron failed to authenticate with the proper security token")
        end

        sysnotify_sock = _accept_or_fail(sysnotify_server, proc, mainjs, startup_timeout)
        if read!(sysnotify_sock, zero(secure_cookie)) != secure_cookie
            error("Electron failed to authenticate with the proper security token")
        end
    catch
        # Never leave a half-started application behind.
        for x in (server, sysnotify_server, sock, sysnotify_sock)
            x === nothing && continue
            try
                close(x)
            catch
            end
        end
        try
            process_running(proc) && kill(proc)
        catch
        end
        rethrow()
    end

    let sysnotify_sock = sysnotify_sock
        let app = _Application(Window, sock, proc, secure_cookie)
            _start_connection_task!(app)
            @async begin
                try
                    try
                        while true
                            try
                                line_json = readline(sysnotify_sock)
                                isempty(line_json) && break # EOF
                                cmd_parsed = JSON.parse(line_json)
                                if cmd_parsed["cmd"] == "windowclosed"
                                    delete!(app.pending_msgs, cmd_parsed["winid"])
                                    win_index = findfirst(w -> w.id == cmd_parsed["winid"], app.windows)
                                    if win_index !== nothing
                                        app.windows[win_index].exists = false
                                        close(app.windows[win_index].msg_channel)
                                        _cleanup_tmp_html_files(app.windows[win_index])
                                        deleteat!(app.windows, win_index)
                                    end
                                elseif cmd_parsed["cmd"] == "appclosing"
                                    break
                                elseif cmd_parsed["cmd"] == "msg_from_window"
                                    win_index = findfirst(w -> w.id == cmd_parsed["winid"], app.windows)
                                    # `get` rather than indexing: a `main.js` that predates
                                    # the `undefined` fix leaves the key out entirely, and
                                    # that must not take the whole application down.
                                    payload = get(cmd_parsed, "payload", nothing)
                                    if win_index === nothing
                                        # The page sent this before we learned about
                                        # the window; hold on to it until the
                                        # `Window` object is constructed.
                                        msgs = get!(() -> Any[], app.pending_msgs, cmd_parsed["winid"])
                                        push!(msgs, payload)
                                    else
                                        put!(app.windows[win_index].msg_channel, payload)
                                    end
                                end
                            catch er
                                bt = catch_backtrace()
                                io = PipeBuffer()
                                printstyled(io, "Electron ERROR: "; color = Base.error_color(), bold = true)
                                Base.showerror(IOContext(io, :limit => true), er, bt)
                                println(io)
                                write(stderr, io)
                            end
                        end
                    finally
                        # Cleanup all the windows that are associated with this application
                        for w in app.windows
                            w.exists = false
                            _cleanup_tmp_html_files(w)
                        end
                        empty!(app.windows)
                    end
                finally
                    # Cleanup the application instance
                    app.exists = false
                    # Make sure nobody is left waiting for a reply that can never
                    # arrive now that the application is gone.
                    close(app.req_channel)
                    close(sysnotify_sock)
                    app_index = findfirst(a -> a === app, _global_applications)
                    deleteat!(_global_applications, app_index)
                end
            end
            return app
        end
    end
end

"""
    close(app::Application)

Terminates the Electron application referenced by `app`.
"""
function Base.close(app::Application)
    app.exists || error("Cannot close this application, the application does no longer exist.")
    while length(windows(app))>0
        try
            close(first(windows(app)))
        catch err
            # The application may have gone away while we were closing its windows.
            err isa ApplicationClosedError || rethrow()
            break
        end
    end
    app.exists = false
    # Shut the request task down first, so that it unwinds cleanly instead of
    # running into the closed connection, and so that anything still queued gets
    # failed with a proper error.
    close(app.req_channel)
    close(app.connection)
    return nothing
end

"""
    _start_connection_task!(app::Application)

Start the one task that owns `app.connection`. It takes requests off
`app.req_channel`, writes each one to the connection, reads the matching reply
line and hands it back to the caller through the reply channel that came with the
request. Because it never has more than one request in flight, the strictly
ordered request/response protocol cannot be scrambled by concurrent callers.

Every request that is queued or in flight when the connection fails, or when the
application shuts down, is answered with an `ApplicationClosedError` so that no
caller is left waiting forever.
"""
function _start_connection_task!(app::Application)
    @async begin
        failure = nothing
        try
            for (json, reply_channel) in app.req_channel
                try
                    println(app.connection, json)
                    flush(app.connection)
                    reply = readline(app.connection)
                    # main.js always terminates a reply with a newline, so an empty
                    # line can only mean that the connection was closed.
                    if isempty(reply)
                        failure = ApplicationClosedError()
                        put!(reply_channel, failure)
                        break
                    end
                    put!(reply_channel, reply)
                catch err
                    failure = err isa ApplicationClosedError ? err :
                        ApplicationClosedError("The Electron application has exited (the connection to it failed: $(sprint(showerror, err))).")
                    put!(reply_channel, failure)
                    break
                end
            end
        finally
            # No further requests can be accepted, and everything that is still
            # queued has to be failed rather than left hanging.
            failure === nothing && (failure = ApplicationClosedError())
            close(app.req_channel)
            while true
                request = try
                    take!(app.req_channel)
                catch
                    break
                end
                put!(request[2], failure)
            end
            # The application must be considered dead now. Closing the connection
            # makes Electron quit, which in turn triggers the regular cleanup in the
            # sysnotify task.
            try
                close(app.connection)
            catch
            end
        end
    end
    return nothing
end

function req_response(app::Application, cmd)
    json = JSON.json(cmd)
    reply_channel = Channel{Any}(1)
    try
        put!(app.req_channel, (json, reply_channel))
    catch err
        err isa InvalidStateException || rethrow()
        throw(ApplicationClosedError())
    end
    reply = try
        take!(reply_channel)
    catch err
        err isa InvalidStateException || rethrow()
        throw(ApplicationClosedError())
    end
    reply isa Exception && throw(reply)
    return JSON.parse(reply)
end

"""
    run(app::Application, code::AbstractString)

Run the JavaScript code that is passed in `code` in the main
application thread of the `app` Electron process. Returns the
value that the JavaScript expression returns.
"""
Base.run(app::Application, code::AbstractString) = run(app, String(code))
function Base.run(app::Application, code::String)
    app.exists || error("Cannot run code in this application, the application does no longer exist.")
    message = OptDict("cmd" => "runcode", "target" => "app", "code" => code)
    retval = req_response(app, message)
    haskey(retval, "error") && throw(JSError(retval["error"]))
    return retval["data"]
end

"""
    run(win::Window, code::AbstractString)

Run the JavaScript code that is passed in `code` in the render
thread of the `win` Electron windows. Returns the value that
the JavaScript expression returns.
"""
function Base.run(win::Window, code::AbstractString)
    win.exists || error("Cannot run code in this window, the window does no longer exist.")
    message = OptDict("cmd" => "runcode", "target" => "window", "winid" => win.id, "code" => code)
    retval = req_response(win.app, message)
    @assert haskey(retval, "status")
    if retval["status"] == "success"
        return get(retval, "data", nothing)
    elseif retval["status"] == "error"
        @assert haskey(retval, "error")
        error("JSError: $(JSON.json(retval["error"]))")
    else
        error("Internal error.")
    end
end

"""
    run(app::Application, code::JSON.JSONText)

Run the JavaScript code that is wrapped in `code` in the main
application thread of the `app` Electron process. Returns the
value that the JavaScript expression returns.
"""
Base.run(app::Application, code::JSON.JSONText) = run(app, JSON.json(code))

"""
    run(win::Window, code::JSON.JSONText)

Run the JavaScript code that is wrapped in `code` in the render
thread of the `win` Electron window. Returns the value that
the JavaScript expression returns.
"""
Base.run(win::Window, code::JSON.JSONText) = run(win, JSON.json(code))

"""
    load(win::Window, uri::URI)

Load `uri` in the Electron window `win`.
"""
function load(win::Window, uri::URI)
    win.exists || error("Cannot load URI in this window, the window does no longer exist.")
    message = OptDict("cmd" => "loadurl", "winid" => win.id, "url" => string(uri))
    req_response(win.app, message)
    return nothing
end

"""
    load(win::Window, path::AbstractPath)

Load `path` in the Electron window `win`.
"""
function load(win::Window, path::AbstractPath)
    win.exists || error("Cannot load path in this window, the window does no longer exist.")
    message = OptDict("cmd" => "loadurl", "winid" => win.id, "url" => string(URI(path)))
    req_response(win.app, message)
    return nothing
end

"""
Maximum size (in bytes) of an HTML string that is passed to Electron as a `data:` URI.

Chromium refuses to navigate to overly long URLs (its limit is on the order of a couple of
megabytes, and it is neither documented nor stable across versions); the navigation then
silently never finishes, which leaves the Julia side waiting forever for `did-finish-load`.
`escapeuri` additionally inflates the payload by up to a factor of three, so the URL that is
actually handed to Chromium can be much larger than the HTML itself.

64 KiB of HTML is therefore a deliberately conservative cut-off: even in the worst case it
produces a URL of well under 200 KB, which is far below anything Chromium is unhappy about,
while still keeping the cheap in-memory `data:` path for the overwhelming majority of uses
(small snippets, `"<body></body>"`-style test pages, ...). Everything above that is written
to a temporary file and loaded via a `file://` URL, which has no size limit.
"""
const MAX_DATA_URI_HTML_SIZE = 64 * 1024

# Write `html` to a temporary file and return its path. The caller is responsible for
# registering the path with a `Window` so that it gets deleted again on teardown.
function _write_temp_html(html::AbstractString)
    path = string(tempname(), ".html")
    open(path, "w") do io
        write(io, html)
    end
    return path
end

# Delete temporary files, never throwing. On Windows the Electron process may still hold a
# recently loaded file open for a moment, so failures are retried in the background.
function _delete_tmp_files(paths::AbstractVector{<:AbstractString})
    isempty(paths) && return nothing
    remaining = String[]
    for p in paths
        try
            rm(p, force=true)
        catch
            push!(remaining, p)
        end
    end
    if !isempty(remaining)
        @async begin
            for _ in 1:50
                sleep(0.2)
                all(p -> (try rm(p, force=true); true catch; false end), remaining) && break
            end
        end
    end
    return nothing
end

_cleanup_tmp_html_files(win::Window) = (_delete_tmp_files(win.tmp_html_files); empty!(win.tmp_html_files); nothing)

"""
    load(win::Window, html::AbstractString)

Load `html` in the Electron window `win`.
"""
function load(win::Window, html::AbstractString)
    if sizeof(html) <= MAX_DATA_URI_HTML_SIZE
        return load(win, URI("data:text/html;charset=utf-8," * escapeuri(html)))
    end
    win.exists || error("Cannot load HTML in this window, the window does no longer exist.")
    path = _write_temp_html(html)
    previous = copy(win.tmp_html_files)
    push!(win.tmp_html_files, path)
    try
        load(win, Path(path))
    finally
        # The previously displayed temporary page has been navigated away from, so its
        # backing file can go. Anything that could not be deleted right away stays
        # registered on the window and is retried at teardown.
        _delete_tmp_files(previous)
        filter!(isfile, win.tmp_html_files)
    end
    return nothing
end

"""
    function Window([app::Application,] options::Dict)

Open a new Window in the application `app`. Pass the content
of `options` to the Electron `electron.BrowserWindow` constructor.

If `app` is not specified, use the default Electron application,
starting one if needed.
"""
function Window(app::Application, options::Dict=OptDict())
    message = OptDict("cmd" => "newwindow", "options" => options)
    retval = req_response(app, message)
    ret_val = retval["data"]
    return _Window(app, ret_val)
end

"""
    function Window([app::Application,] uri::URI)

Open a new Window in the application `app`. Show the content
that `uri` points to in that new window.

If `app` is not specified, use the default Electron application,
starting one if needed.
"""
function Window(app::Application, uri::URI; options::Dict=OptDict())
    internal_options = OptDict()
    merge!(internal_options, options)
    internal_options["url"] = string(uri)
    return Window(app, internal_options)
end

"""
    function Window([app::Application,] path::AbstractPath)

Open a new Window in the application `app`. Show the content
that `path` points to in that new window.

If `app` is not specified, use the default Electron application,
starting one if needed.
"""
function Window(app::Application, path::AbstractPath; options::Dict=OptDict())
    return Window(app, URI(path); options=options)
end

"""
    function Window([app::Application,] content::AbstractString)

Open a new Window in the application `app`. Show the `content`
as a text/html file with utf-8 encoding.

If `app` is not specified, use the default Electron application,
starting one if needed.
"""
function Window(app::Application, content::AbstractString; kwargs...)
    # See `MAX_DATA_URI_HTML_SIZE`: large payloads cannot be passed as a `data:` URI.
    if sizeof(content) > MAX_DATA_URI_HTML_SIZE
        path = _write_temp_html(content)
        local win
        try
            win = Window(app, Path(path); kwargs...)
        catch
            _delete_tmp_files([path])
            rethrow()
        end
        push!(win.tmp_html_files, path)
        return win
    end
    return Window(app, URI("data:text/html;charset=utf-8," * escapeuri(content)); kwargs...)
end

Window(a1::Application, args...; kwargs...) = throw(MethodError(Window, (a1, args...)))
Window(args...; kwargs...) = Window(default_application(), args...; kwargs...)

function toggle_devtools(w::Window)
    run(w.app, "electron.BrowserWindow.fromId($(w.id)).webContents.toggleDevTools()")
end

"""
    close(win::Window)

Close the windows referenced by `win`.
"""
function Base.close(win::Window)
    win.exists || error("Cannot close this window, the window does no longer exist.")
    message = OptDict("cmd" => "closewindow", "winid" => win.id)
    req_response(win.app, message)
    # The window is gone at this point, so any temporary HTML file we created for it can be
    # removed. (The removal from `app.windows` happens asynchronously, and the sysnotify
    # handler cleans up as well, so this is safe to do twice.)
    _cleanup_tmp_html_files(win)
    return nothing
end

Base.isopen(win::Window) = win.exists

msgchannel(win::Window) = win.msg_channel

"""
    ElectronAPI

A shim object for calling Electron API functions.

See:
* <https://electronjs.org/docs/api/browser-window>

# Examples
```jldoctest
julia> using Electron

julia> win = Window();

julia> ElectronAPI.setBackgroundColor(win, "#000");

julia> ElectronAPI.show(win);
```
"""
ElectronAPI

struct ElectronAPIType end
const ElectronAPI = ElectronAPIType()

struct ElectronAPIFunction <: Function
    name::Symbol
end

Base.getproperty(::ElectronAPIType, name::Symbol) = ElectronAPIFunction(name)

function (api::ElectronAPIFunction)(w::Window, args...)
    name = api.name
    # `Any[]` rather than `collect(args)`: for a zero-argument call the latter is a
    # `Vector{Union{}}`, which JSON.jl v1 serializes as `{}` instead of `[]`, and the
    # spread below then fails with a JS TypeError.
    json_args = JSON.json(Any[args...])
    run(w.app, "electron.BrowserWindow.fromId($(w.id)).$name(...$json_args)")
end

end
