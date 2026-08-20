@testitem "Window from URI and JS execution" setup=[ElectronTestHelpers] begin
    using URIs, FilePaths

    testpage = joinpath(@__PATH__, p"test.html")

    app = Application()
    try
        w = Window(app, URI(testpage))

        @test isa(w, Window)
        @test isopen(w)
        @test length(windows(app)) == 1

        @test run(w, "Math.log(Math.exp(1))") == 1
        @test_throws ErrorException run(w, "syntaxerror")

        @test run(app, "Math.log(Math.exp(1))") == 1

        close(w)
        @test wait_until(() -> isempty(windows(app)))
    finally
        app.exists && close(app)
    end
end

@testitem "Application and window bookkeeping" setup=[ElectronTestHelpers] begin
    using URIs, FilePaths

    testpage = joinpath(@__PATH__, p"test.html")

    wait_for_no_applications()

    w = Window(URI(testpage))  # implicitly starts the default application
    app = applications()[end]
    try
        @test length(applications()) == 1
        @test length(windows(app)) == 1

        close(w)
        @test wait_until(() -> isempty(windows(app)))
        @test length(applications()) == 1

        Window(app, testpage)
        @test length(windows(app)) == 1

        close(app)
        @test wait_until(() -> isempty(windows(app)))
        @test wait_until(() -> isempty(applications()))
    finally
        app.exists && close(app)
    end
end

@testitem "Window constructors" setup=[ElectronTestHelpers] begin
    using URIs, FilePaths

    testpage = joinpath(@__PATH__, p"test.html")

    app = Application()
    try
        ws = (
            Window(app, Dict("url" => string(URI(testpage)))),
            Window(app, URI(testpage), options=Dict("title" => "Window title")),
            Window(app, testpage, options=Dict("title" => "Window title")),
            Window(app, "<body></body>", options=Dict("title" => "Window title")),
            Window(app),
        )

        @test all(w -> isa(w, Window), ws)
        @test length(windows(app)) == length(ws)

        @test_throws MethodError Window(app, 1)

        foreach(close, ws)
        @test wait_until(() -> isempty(windows(app)))
    finally
        app.exists && close(app)
    end
end

@testitem "Messaging and load" setup=[ElectronTestHelpers] begin
    using URIs, FilePaths

    testpage = joinpath(@__PATH__, p"test.html")

    app = Application()
    try
        w = Window(app)

        run(w, "sendMessageToJulia('foo')")
        @test take!(msgchannel(w)) == "foo"

        load(w, "<body>bar</body>")
        run(w, "sendMessageToJulia(window.document.documentElement.innerHTML)")
        @test occursin("bar", take!(msgchannel(w)))

        load(w, testpage)
        run(w, "sendMessageToJulia(window.document.documentElement.innerHTML)")
        @test occursin("This is some test content", take!(msgchannel(w)))

        load(w, URI(testpage))
        run(w, "sendMessageToJulia(window.document.documentElement.innerHTML)")
        @test occursin("This is some test content", take!(msgchannel(w)))

        close(w)
        @test wait_until(() -> isempty(windows(app)))
    finally
        app.exists && close(app)
    end
end

@testitem "Concurrent requests from many tasks" setup=[ElectronTestHelpers] begin
    using FilePaths

    app = Application()
    try
        w = Window(app, joinpath(@__PATH__, p"test.html"))

        # Every request has a distinguishable answer, so a reply that was handed to
        # the wrong caller shows up as a wrong value rather than by luck being right.
        n = 16
        window_results = Vector{Any}(undef, n)
        app_results = Vector{Any}(undef, n)

        @sync begin
            for i in 1:n
                @async window_results[i] = run(w, "1000 * $i + 7")
                @async app_results[i] = run(app, "2000 * $i + 3")
            end
        end

        @test window_results == [1000 * i + 7 for i in 1:n]
        @test app_results == [2000 * i + 3 for i in 1:n]

        # Windows are created with a request whose reply only arrives once the new
        # window has loaded, i.e. much later than the replies of everything else in
        # flight. Mixing those with fast requests is the case that used to scramble
        # the protocol most reliably.
        new_windows = Vector{Any}(undef, 4)
        mixed_results = Vector{Any}(undef, 8)
        @sync begin
            for i in 1:4
                @async new_windows[i] = Window(app, "<body>concurrent $i</body>")
            end
            for i in 1:8
                @async mixed_results[i] = run(w, "3000 * $i + 11")
            end
        end

        @test all(x -> isa(x, Window), new_windows)
        @test mixed_results == [3000 * i + 11 for i in 1:8]

        foreach(close, new_windows)
        close(w)
        @test wait_until(() -> isempty(windows(app)))
    finally
        app.exists && close(app)
    end
end

@testsnippet LargeHTML begin
    # A multi-megabyte HTML document with a uniquely identifiable marker element. Passing
    # this through a `data:` URI overruns Chromium's URL length limit, so the navigation
    # never finishes (see issue #37).
    function large_html(marker)
        io = IOBuffer()
        print(io, "<html><body>")
        for i in 1:40000
            print(io, "<div class=\"row\">Lorem ipsum dolor sit amet, row number ", i, "</div>")
        end
        print(io, "<div id=\"marker\">", marker, "</div></body></html>")
        html = String(take!(io))
        @assert sizeof(html) > 2_000_000
        return html
    end

    read_marker(w) = run(w, "document.getElementById('marker') === null ? \"NOT-FOUND\" : document.getElementById('marker').textContent")
end

@testitem "load large HTML" setup=[ElectronTestHelpers, LargeHTML] begin
    app = Application()
    try
        w = Window(app)

        marker = "MARKER-load-1a2b3c"
        load(w, large_html(marker))
        @test read_marker(w) == marker

        # Loading a second large document must work as well.
        marker2 = "MARKER-load-4d5e6f"
        load(w, large_html(marker2))
        @test read_marker(w) == marker2

        run(w, "sendMessageToJulia(document.getElementById('marker').textContent)")
        @test take!(msgchannel(w)) == marker2

        close(w)
        @test wait_until(() -> isempty(windows(app)))
    finally
        app.exists && close(app)
    end
end

@testitem "Application fails fast if Electron dies at startup" setup=[ElectronTestHelpers] begin
    dir = mktempdir()
    try
        # A `main.js` that makes the Electron process exit immediately, so it never
        # connects back to Julia. `Application` used to block in `accept` forever
        # in that situation (issue #127).
        mainjs = joinpath(dir, "main.js")
        write(mainjs, "process.exit(37)\n")

        # Never let this block the test suite, no matter what happens.
        t = @async try
            Application(mainjs=mainjs, startup_timeout=60.0)
        catch err
            err
        end

        @test wait_until(() -> istaskdone(t), 120.0)

        if istaskdone(t)
            result = fetch(t)
            @test result isa Exception
            if result isa Exception
                msg = sprint(showerror, result)
                @test occursin("Electron process exited", msg)
            end
            # In the very unlikely case that an application was started anyway,
            # do not leak it.
            result isa Application && result.exists && close(result)
        end
    finally
        rm(dir, recursive=true, force=true)
    end
end

@testitem "Requests fail with a clear error once the application is gone" setup=[ElectronTestHelpers] begin
    app = Application()
    try
        w = Window(app)
        close(app)
        @test wait_until(() -> !app.exists)

        @test_throws Exception run(app, "1 + 1")
        @test_throws Exception run(w, "1 + 1")
    finally
        app.exists && close(app)
    end

    # Also exercise the path where the application object still believes it is
    # alive, but its connection is gone: every request must fail promptly with an
    # ApplicationClosedError rather than block (issues #38/#43).
    app2 = Application()
    try
        close(app2.connection)
        result = Ref{Any}(nothing)
        t = @async try
            run(app2, "1 + 1")
        catch err
            err
        end
        @test wait_until(() -> istaskdone(t), 60.0)
        istaskdone(t) && (result[] = fetch(t))
        @test result[] isa Exception
    finally
        app2.exists && close(app2)
    end
end

@testitem "Window constructor with large HTML" setup=[ElectronTestHelpers, LargeHTML] begin
    app = Application()
    try
        marker = "MARKER-ctor-7a8b9c"
        w = Window(app, large_html(marker), options=Dict("title" => "Large window"))

        @test isa(w, Window)
        @test read_marker(w) == marker

        close(w)
        @test wait_until(() -> isempty(windows(app)))
    finally
        app.exists && close(app)
    end
end

@testitem "large HTML temp files are cleaned up" setup=[ElectronTestHelpers, LargeHTML] begin
    app = Application()
    try
        # Closing a window removes the temporary file it was loaded from.
        w = Window(app, large_html("MARKER-cleanup-1"))
        files = copy(w.tmp_html_files)
        @test length(files) == 1
        @test all(isfile, files)

        close(w)
        @test wait_until(() -> isempty(windows(app)))
        @test wait_until(() -> !any(isfile, files))

        # And so does closing the whole application.
        w2 = Window(app)
        load(w2, large_html("MARKER-cleanup-2"))
        files2 = copy(w2.tmp_html_files)
        @test length(files2) == 1
        @test all(isfile, files2)

        close(app)
        @test wait_until(() -> !any(isfile, files2))
    finally
        app.exists && close(app)
    end
end

@testitem "small HTML still uses a data URI" setup=[ElectronTestHelpers] begin
    app = Application()
    try
        w = Window(app, "<body>small</body>")
        load(w, "<body>also small</body>")

        @test isempty(w.tmp_html_files)
        @test run(w, "window.location.protocol") == "data:"

        close(w)
        @test wait_until(() -> isempty(windows(app)))
    finally
        app.exists && close(app)
    end
end

@testitem "sendMessageToJulia available to page scripts" setup=[ElectronTestHelpers] begin
    using FilePaths

    # Issues #143 and #34: `sendMessageToJulia` has to be defined before any
    # script of the page runs, so that inline `<head>` scripts, `window.onload`
    # handlers and promise callbacks can call it.
    app = Application()
    try
        w = Window(app, joinpath(@__PATH__, p"onload_test.html"))

        c = msgchannel(w)
        t = @async take!(c)
        # Don't block the test suite forever if the message never arrives.
        @test wait_until(() -> istaskdone(t), 30.0)
        if istaskdone(t)
            @test fetch(t) == "LOADED"
        end

        close(w)
        @test wait_until(() -> isempty(windows(app)))
    finally
        app.exists && close(app)
    end
end

@testitem "toggle_devtools" begin
    using FilePaths

    app = Application()
    try
        w = Window(app, joinpath(@__PATH__, p"test.html"))

        @test (toggle_devtools(w); true)

        close(w)
    finally
        app.exists && close(app)
    end
end
