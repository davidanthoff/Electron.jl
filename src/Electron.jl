__precompile__()
module Electron

using JSON, URIParser

export Application, Window, URI, windows, applications

mutable struct Application
    id::UInt
    connection
    proc
    sysnotify_connection
    exists::Bool

    function Application(id::Int, connection, proc, sysnotify_connection)
        new_app = new(id, connection, proc, sysnotify_connection, true)
        push!(_global_applications, new_app)
        return new_app
    end
end

mutable struct Window
    app::Application
    id::Int64
    exists::Bool

    function Window(app::Application, id::Int64)
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
end

function applications()
    return _global_applications
end

function windows()
    return _global_windows
end

function generate_pipe_name(name)
    if is_windows()
        "\\\\.\\pipe\\$name"
    elseif is_unix()
        joinpath(tempdir(), name)
    end
end

function get_electron_binary_cmd()
    @static if is_apple()
        return joinpath(@__DIR__, "..", "deps", "Julia.app", "Contents", "MacOS", "Julia")
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

    sysnotify_sock = accept(sysnotify_server)

    sysnotify_task = @schedule begin
        while true
            line_json = readline(sysnotify_sock)
            cmd_parsed = JSON.parse(line_json)
            if cmd_parsed["cmd"] == "windowclosed"
                win_index = findfirst(i->i.app.id==id && i.id==cmd_parsed["winid"], _global_windows)
                _global_windows[win_index].exists = false
                deleteat!(_global_windows, win_index)
            elseif cmd_parsed["cmd"] == "appclosing"
                break
            end
        end
        # Cleanup all the windows that are associated with this application
        win_indices = sort(find(i->i.app.id==id, _global_windows), rev=true)
        for win_index in win_indices
            _global_windows[win_index].exists = false
            deleteat!(_global_windows, win_index)
        end
        # Cleanup the application instance
        app_index = findfirst(i->i.id == id, _global_applications)
        _global_applications[app_index].exists = false
        close(_global_applications[app_index].sysnotify_connection)
        deleteat!(_global_applications, app_index)
    end

    return Application(id, sock, proc, sysnotify_sock)
end

"""
    close(app::Application)

Terminates the Electron application referenced by `app`.
"""
function Base.close(app::Application)
    app.exists || error("Cannot close this application, the application does no longer exist.")
    close(app.connection)
end

"""
    run(app::Application, code::AbstractString)

Run the JavaScript code that is passed in `code` in the main
application thread of the `app` Electron process. Returns the
value that the JavaScript expression returns.
"""
function Base.run(app::Application, code::AbstractString)
    app.exists || error("Cannot run code in this application, the application does no longer exist.")
    println(app.connection, JSON.json(Dict("cmd"=>"runcode", "target"=>"app", "code"=>code)))
    retval_json = readline(app.connection)
    retval = JSON.parse(retval_json)
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
    message = Dict("cmd"=>"runcode", "target"=>"window", "winid" => win.id, "code" => code)
    println(win.app.connection, JSON.json(message))
    retval_json = readline(win.app.connection)
    retval = JSON.parse(retval_json)
    return retval["data"]
end

"""
    function Window(app::Application, uri::URI)

Open a new Window in the application `app`. Show the content
that `uri` points to in that new window.
"""
function Window(app::Application, uri::URI)
    message = Dict("cmd" => "newwindow", "url" => string(uri))
    println(app.connection, JSON.json(message))
    retval_json = readline(app.connection)
    retval = JSON.parse(retval_json)
    ret_val = retval["data"]
    return Window(app, ret_val)
end

"""
    function Window(uri::URI)

Open a new Window in the default Electron application. If no
default application is running, first start one. Show the content
that `uri` points to in that new window.
"""
function Window(uri::URI)
    if length(_global_applications)==0
        Application()
    end

    return Window(_global_applications[1], uri)
end

"""
    close(win::Window)

Close the windows referenced by `win`.
"""
function Base.close(win::Window)
    win.exists || error("Cannot close this window, the window does no longer exist.")
    message = Dict("cmd"=>"closewindow", "winid" => win.id)
    println(win.app.connection, JSON.json(message))
    retval_json = readline(win.app.connection)
    retval = JSON.parse(retval_json)
    return nothing
end

end
