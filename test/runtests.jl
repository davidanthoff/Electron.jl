using Electron
using URIParser
using Base.Test

@testset "Electron" begin

w = Window(URI("file://test.html"))

a = applications()[1]

@test isa(w, Window)

@test length(applications()) == 1
@test length(windows()) == 1

res = run(w, "Math.log(Math.exp(1))")

@test res==1

res = run(a, "Math.log(Math.exp(1))")

@test res ==1

close(w)

close(a)

end
