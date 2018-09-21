const version = "3.0.0"

if Sys.isapple()
    const _icons = normpath(joinpath(@__DIR__, "../res/julia-icns.icns"))
end

our_download(x) = download(x, basename(x))

cd(@__DIR__) do
    our_download("http://junolab.s3.amazonaws.com/blink/julia.png")

    rm(joinpath(@__DIR__, "electron"), force=true, recursive=true)

    if Sys.isapple()
        file = "electron-v$version-darwin-x64.zip"
        our_download("https://github.com/electron/electron/releases/download/v$version/$file")
        run(`unzip -q $file -d electron`)
        rm(file)
        run(`mv electron/Electron.app electron/Julia.app`)
        run(`mv electron/Julia.app/Contents/MacOS/Electron electron/Julia.app/Contents/MacOS/Julia`)
        run(`sed -i.bak 's/Electron/Julia/' electron/Julia.app/Contents/Info.plist`)        
        run(`cp $_icons electron/Julia.app/Contents/Resources/electron.icns`)
        run(`touch electron/Julia.app`)  # Apparently this is necessary to tell the OS to double-check for the new icons.
    end

    if Sys.iswindows()
        arch = Int == Int64 ? "x64" : "ia32"
        file = "electron-v$version-win32-$arch.zip"
        our_download("https://github.com/electron/electron/releases/download/v$version/$file")
        run(`$(joinpath(Sys.BINDIR, "7z")) x $file -oelectron -aoa`)
        rm(file)
    end

    if Sys.islinux()
        arch = Int == Int64 ? "x64" : "ia32"
        file = "electron-v$version-linux-$arch.zip"
        our_download("https://github.com/electron/electron/releases/download/v$version/$file")        
        run(`unzip -q $file -d electron`)
        rm(file)
    end
end
