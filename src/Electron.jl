__precompile__()
module Electron

using JSON, URIParser

export Application, Window, URI, windows, applications
const OptDict = Dict{String, Any}

struct JSError
    msg
end
Base.showerror(io::IO, e::JSError) = print(io, "JSError: ", e.msg)

mutable struct Application
    id::UInt
    connection::IO
    proc
    sysnotify_connection::IO
    exists::Bool

    global function _Application(id::Int, connection::IO, proc, sysnotify_connection::IO)
        new_app = new(id, connection, proc, sysnotify_connection, true)
        push!(_global_applications, new_app)
        return new_app
    end
end

mutable struct Window
    app::Application
    id::Int64
    exists::Bool

    global function _Window(app::Application, id::Int64)
        new_window = new(app, id, true)
        push!(_global_windows, new_window)
        return new_window
    end
end

const _global_applications = Vector{Application}(0)
const _global_application_next_id = Ref{Int}(1)

const _global_windows = Vector{Window}()

function __init__()
    _global_application_next_id[] = 1
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
    isempty(_global_applications) && Application()
    return _global_applications[1]
end

function windows()
    return _global_windows
end

function generate_pipe_name(name)
    return if is_windows()
        "\\\\.\\pipe\\$name"
    elseif is_unix()
        joinpath(tempdir(), name)
    end
end

function get_electron_binary_cmd()
    @static if is_apple()
        return joinpath(@__DIR__, "..", "deps", "electron", "Julia.app", "Contents", "MacOS", "Julia")
    elseif is_linux()
        return joinpath(@__DIR__, "..", "deps", "electron", "electron")
    elseif is_windows()
        return joinpath(@__DIR__, "..", "deps", "electron", "electron.exe")
    else
        error("Unknown platform.")
    end
end

"""
    function Application()

Start a new Electron application. This will start a new process
for that Electron app and return an instance of `Application` that
can be used in the construction of Electron windows.
"""
function Application()
    electron_path = get_electron_binary_cmd()
    mainjs = joinpath(@__DIR__, "main.js")
    id = _global_application_next_id[]
    _global_application_next_id[] = id + 1
    process_id = getpid()

    main_pipe_name = "juliaelectron-$process_id-$id"
    main_pipe_name_full = generate_pipe_name(main_pipe_name)
    server = listen(main_pipe_name_full)

    sysnotify_pipe_name = "juliaelectron-sysnotify-$process_id-$id"
    sysnotify_pipe_name_full = generate_pipe_name(sysnotify_pipe_name)
    sysnotify_server = listen(sysnotify_pipe_name_full)

    proc = spawn(`$electron_path $mainjs $main_pipe_name $sysnotify_pipe_name`)

    sock = accept(server)
    close(server)

    let sysnotify_sock = accept(sysnotify_server)
        close(sysnotify_server)
        sysnotify_task = @schedule begin
            try
                try
                    while true
                        try
                            line_json = readline(sysnotify_sock)
                            isempty(line_json) && break # EOF
                            cmd_parsed = JSON.parse(line_json)
                            if cmd_parsed["cmd"] == "windowclosed"
                                win_index = findfirst(i->i.app.id==id && i.id==cmd_parsed["winid"], _global_windows)
                                _global_windows[win_index].exists = false
                                deleteat!(_global_windows, win_index)
                            elseif cmd_parsed["cmd"] == "appclosing"
                                break
                            end
                        catch er
                            bt = catch_backtrace()
                            io = PipeBuffer()
                            print_with_color(Base.error_color(), io, "Electron ERROR: "; bold = true)
                            Base.showerror(IOContext(io, :limit => true), er, bt)
                            println(io)
                            write(STDERR, io)
                        end
                    end
                finally
                    # Cleanup all the windows that are associated with this application
                    win_indices = sort(find(i->i.app.id==id, _global_windows), rev=true)
                    for win_index in win_indices
                        _global_windows[win_index].exists = false
                        deleteat!(_global_windows, win_index)
                    end
                end
            finally
                # Cleanup the application instance
                app_index = findfirst(i -> i.id == id, _global_applications)
                _global_applications[app_index].exists = false
                close(_global_applications[app_index].sysnotify_connection)
                deleteat!(_global_applications, app_index)
            end
        end
        return _Application(id, sock, proc, sysnotify_sock)
    end
end

"""
    close(app::Application)

Terminates the Electron application referenced by `app`.
"""
function Base.close(app::Application)
    app.exists || error("Cannot close this application, the application does no longer exist.")
    close(app.connection)
end

function req_response(connection, cmd)
    json = JSON.json(cmd)
    c = Condition()
    t = @schedule try
        println(connection, json)
        wait(c)
    catch ex
        close(connection) # kill Application, since it probably must be in a bad state now
        rethrow(ex)
    end
    retval_json = readline(connection)
    notify(c)
    wait(t)
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
    retval = req_response(app.connection, message)
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
    retval = req_response(win.app.connection, message)
    return retval["data"]
end

"""
    function Window([app::Application,] options::Dict)

Open a new Window in the application `app`. Pass the content
of `options` to the Electron `BrowserWindow` constructor.

If `app` is not specified, use the default Electron application,
starting one if needed.
"""
function Window(app::Application, options::Dict=OptDict())
    message = OptDict("cmd" => "newwindow", "options" => options)
    retval = req_response(app.connection, message)
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
    function Window([app::Application,] uri::URI)

Open a new Window in the application `app`. Show the `content`
as a text/html file with utf-8 encoding.

If `app` is not specified, use the default Electron application,
starting one if needed.
"""
function Window(app::Application, content::AbstractString; kwargs...)
    return Window(app, URI("data:text/html;charset=utf-8," * escape(content)); kwargs...)
end

Window(a1::Application, args...; kwargs...) = throw(MethodError(Window, (a1, args...)))
Window(args...; kwargs...) = Window(default_application(), args...; kwargs...)

"""
    close(win::Window)

Close the windows referenced by `win`.
"""
function Base.close(win::Window)
    win.exists || error("Cannot close this window, the window does no longer exist.")
    message = OptDict("cmd" => "closewindow", "winid" => win.id)
    retval = req_response(win.app.connection, message)
    return nothing
end

end
