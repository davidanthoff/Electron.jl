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
