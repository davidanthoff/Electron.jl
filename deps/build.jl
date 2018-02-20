import BinDeps

const version = "1.8.2"

if is_apple()
    const _icons = normpath(joinpath(@__DIR__, "../res/julia-icns.icns"))
end

download(x) = run(BinDeps.download_cmd(x, basename(x)))

cd(@__DIR__) do
    download("http://junolab.s3.amazonaws.com/blink/julia.png")

    if is_apple()
        file = "electron-v$version-darwin-x64.zip"
        download("https://github.com/electron/electron/releases/download/v$version/$file")
        run(`unzip -q $file`)
        rm(file)
        run(`mv Electron.app Julia.app`)
        run(`mv Julia.app/Contents/MacOS/Electron Julia.app/Contents/MacOS/Julia`)
        run(`sed -i.bak 's/Electron/Julia/' Julia.app/Contents/Info.plist`)
        run(`cp $_icons Julia.app/Contents/Resources/electron.icns`)
        run(`touch Julia.app`)  # Apparently this is necessary to tell the OS to double-check for the new icons.
    end

    if is_windows()
        arch = Int == Int64 ? "x64" : "ia32"
        file = "electron-v$version-win32-$arch.zip"
        download("https://github.com/electron/electron/releases/download/v$version/$file")
        run(`7z x $file -oelectron -aoa`)
        rm(file)
    end

    if is_linux()
        arch = Int == Int64 ? "x64" : "ia32"
        file = "electron-v$version-linux-$arch.zip"
        download("https://github.com/electron/electron/releases/download/v$version/$file")
        run(`unzip -q $file -d electron`)
        rm(file)
    end
end
