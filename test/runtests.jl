using Electron
using Base.Test

@testset "Electron" begin

w = Window("file://test.html")

@test isa(w, Window)

end
