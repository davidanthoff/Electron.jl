__precompile__()
module Electron

using JSON

export Application, Window

struct Application
    id::UInt
    connection
    proc
end

struct Window
    app::Application
    id::Int
end

const _global_application = Ref{Nullable{Application}}(Nullable{Application}())
const _global_application_next_id = Ref{Int}(1)

function __init__()
    _global_application[] = Nullable{Application}()
    _global_application_next_id[] = 1
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

function Application()
    electron_path = get_electron_binary_cmd()
    mainjs = joinpath(@__DIR__, "main.js")
    id = _global_application_next_id[]
    _global_application_next_id[] = id + 1
    process_id = getpid()
    pipe_name = "juliaelectron-$process_id-$id"
    named_pipe_name = generate_pipe_name(pipe_name)

    server = listen(named_pipe_name)

    proc = spawn(`$electron_path $mainjs $pipe_name`)

    sock = accept(server)

    return Application(id, sock, proc)
end

function Base.close(app::Application)
    close(app.connection)
end

function Base.run(app::Application, code::AbstractString)
    println("STEP A")
    println(app.connection, JSON.json(Dict("target"=>"app", "code"=>code)))
    println("STEP B")
    retval_json = readline(app.connection)
    println("STEP C")
    retval = JSON.parse(retval_json)
    println("STEP D")
    return retval["data"]
end

function Base.run(win::Window, code::AbstractString)
    message = Dict("target"=>"window", "winid" => win.id, "code" => code)
    println(win.app.connection, JSON.json(message))
    retval_json = readline(win.app.connection)
    retval = JSON.parse(retval_json)
    return retval["data"]
end

function Window(app::Application, url::AbstractString)
    json_options = JSON.json(Dict("url"=>url))
    code = "createWindow($json_options)"
    ret_val = run(app, code)
    return Window(app, ret_val)
end

function Window(url::AbstractString)
    if isnull(_global_application[])
        _global_application[] = Nullable(Application())
    end

    return Window(get(_global_application[]), url)
end

end
