@testitem "ElectronAPI" begin
    app = Application()
    try
        win = Window(app)

        @test (ElectronAPI.setBackgroundColor(win, "#000"); true)
        @test ElectronAPI.isFocused(win) isa Bool

        bounds = ElectronAPI.getBounds(win)
        boundskeys = ["width", "height", "x", "y"]
        @test Set(boundskeys) <= Set(keys(bounds))
        @test all(isa.(get.(Ref(bounds), boundskeys, nothing), Real))

        close(win)
    finally
        app.exists && close(app)
    end
end
