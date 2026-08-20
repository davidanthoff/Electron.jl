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

@testitem "run with JSONText" setup=[ElectronTestHelpers] begin
    using JSON

    app = Application()
    try
        w = Window(app)

        @test run(w, JSON.JSONText("1+1")) == 2
        @test run(app, JSON.JSONText("1+1")) == 2

        close(w)
        @test wait_until(() -> isempty(windows(app)))
    finally
        app.exists && close(app)
    end
end

@testitem "sendMessageToJulia with undefined" setup=[ElectronTestHelpers] begin
    app = Application()
    try
        w = Window(app)

        run(w, "sendMessageToJulia(undefined)")
        @test take!(msgchannel(w)) === nothing

        # The application must have survived the undefined payload (issue #144)
        @test run(w, "1+1") == 2

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
