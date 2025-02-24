module Electron

using JSON, URIs, Sockets, Base64, Pkg.Artifacts, FilePaths, UUIDs
using RelocatableFolders

export Application, Window, URI, windows, applications, msgchannel, toggle_devtools, load, ElectronAPI

function conditional_electron_load()
    try
        return artifact"electronjs_app"
    catch error
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

const OptDict = Dict{String,Any}

struct JSError
    msg
end
Base.showerror(io::IO, e::JSError) = print(io, "JSError: ", e.msg)

mutable struct _Application{T} # forward declaration of Application
    connection::IO
    proc
    secure_cookie::Vector{UInt8}
    windows::Vector{T}
    exists::Bool

    global function _Application(::Type{T}, connection::IO, proc, secure_cookie) where {T} # internal constructor
        new_app = new{T}(connection, proc, secure_cookie, T[], true)
        push!(_global_applications, new_app)
        return new_app
    end
end

mutable struct Window
    app::_Application{Window}
    id::Int64
    exists::Bool
    msg_channel::Channel{Any}

    global function _Window(app::_Application{Window}, id::Int64; msg_channel_size=128) # internal constructor
        new_window = new(app, id, true, Channel{Any}(msg_channel_size))
        push!(app.windows, new_window)
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


const _global_applications = Vector{Application}(undef, 0)
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
    if _global_default_application[] === nothing || _global_default_application[].exists == false
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

    if electronjs_path === nothing
        return "electron"
    elseif Sys.isapple()
        return joinpath(electronjs_path, "Julia.app", "Contents", "MacOS", "Julia")
    elseif Sys.iswindows()
        return joinpath(electronjs_path, "electron.exe")
    else # assume unix layout
        return joinpath(electronjs_path, "electron")
    end
end

const MAIN_JS = @path joinpath(@__DIR__, "main.js")

"""
    function Application()

Start a new Electron application. This will start a new process
for that Electron app and return an instance of `Application` that
can be used in the construction of Electron windows.
"""
function Application(; mainjs=normpath(String(MAIN_JS)), additional_electron_args=String[])
    @assert isfile(mainjs)
    read(mainjs) # This seems to be required to not hang windows CI?!
    electron_path = get_electron_binary_cmd()

    id = replace(string(uuid1()), "-" => "")
    main_pipe_name = generate_pipe_name("jlel-$id")
    server = listen(main_pipe_name)

    id = replace(string(uuid1()), "-" => "")
    sysnotify_pipe_name = generate_pipe_name("jlel-sn-$id")
    sysnotify_server = listen(sysnotify_pipe_name)

    secure_cookie = rand(UInt8, 128)
    secure_cookie_encoded = base64encode(secure_cookie)
    # proc = open(`$electron_path --inspect-brk=5858 $mainjs $main_pipe_name $sysnotify_pipe_name $secure_cookie_encoded`, "w", stdout)
    electron_cmd = Cmd([
        electron_path,
        "--no-sandbox",
        mainjs,
        main_pipe_name,
        sysnotify_pipe_name,
        secure_cookie_encoded,
        additional_electron_args...
    ])

    new_env = copy(ENV)
    if haskey(new_env, "ELECTRON_RUN_AS_NODE")
        delete!(new_env, "ELECTRON_RUN_AS_NODE")
    end

    proc = open(Cmd(electron_cmd, env=new_env), "w", stdout)

    sock = accept(server)
    if read!(sock, zero(secure_cookie)) != secure_cookie
        close(server)
        close(sysnotify_server)
        close(sock)
        error("Electron failed to authenticate with the proper security token")
    end

    let sysnotify_sock = accept(sysnotify_server)
        if read!(sysnotify_sock, zero(secure_cookie)) != secure_cookie
            close(server)
            close(sysnotify_server)
            close(sysnotify_sock)
            close(sock)
            error("Electron failed to authenticate with the proper security token")
        end
        let app = _Application(Window, sock, proc, secure_cookie)
            @async begin
                try
                    try
                        while true
                            try
                                line_json = readline(sysnotify_sock)
                                isempty(line_json) && break # EOF
                                cmd_parsed = JSON.parse(line_json)
                                if cmd_parsed["cmd"] == "windowclosed"
                                    win_index = findfirst(w -> w.id == cmd_parsed["winid"], app.windows)
                                    app.windows[win_index].exists = false
                                    close(app.windows[win_index].msg_channel)
                                    deleteat!(app.windows, win_index)
                                elseif cmd_parsed["cmd"] == "appclosing"
                                    break
                                elseif cmd_parsed["cmd"] == "msg_from_window"
                                    win_index = findfirst(w -> w.id == cmd_parsed["winid"], app.windows)
                                    put!(app.windows[win_index].msg_channel, cmd_parsed["payload"])
                                end
                            catch er
                                bt = catch_backtrace()
                                io = PipeBuffer()
                                print_with_color(Base.error_color(), io, "Electron ERROR: "; bold=true)
                                Base.showerror(IOContext(io, :limit => true), er, bt)
                                println(io)
                                write(stderr, io)
                            end
                        end
                    finally
                        # Cleanup all the windows that are associated with this application
                        for w in app.windows
                            w.exists = false
                        end
                        empty!(app.windows)
                    end
                finally
                    # Cleanup the application instance
                    app.exists = false
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
    while length(windows(app)) > 0
        close(first(windows(app)))
    end
    app.exists = false
    close(app.connection)
end

function req_response(app::Application, cmd)
    connection = app.connection
    json = JSON.json(cmd)
    c = Condition()
    t = @async try
        println(connection, json)
        fetch(c)
    catch ex
        close(connection) # kill Application, since it probably must be in a bad state now
        rethrow(ex)
    end
    retval_json = readline(connection)
    notify(c)
    fetch(t)
    return JSON.parse(retval_json)
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
    load(win::Window, html::AbstractString)

Load `html` in the Electron window `win`.
"""
load(win::Window, html::AbstractString) =
    load(win, URI("data:text/html;charset=utf-8," * escapeuri(html)))

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
    retval = req_response(win.app, message)
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
    json_args = JSON.json(collect(args))
    run(w.app, "electron.BrowserWindow.fromId($(w.id)).$name(...$json_args)")
end

end
