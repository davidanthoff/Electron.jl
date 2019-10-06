using Pkg
using Pkg.Artifacts
using SHA

artifact_name = "electron"

platforms = [
    ("https://github.com/electron/electron/releases/download/v6.0.11/electron-v6.0.11-darwin-x64.zip", Pkg.BinaryPlatforms.MacOS(:x86_64)),
    ("https://github.com/electron/electron/releases/download/v6.0.11/electron-v6.0.11-win32-x64.zip", Pkg.BinaryPlatforms.Windows(:x86_64)),
    ("https://github.com/electron/electron/releases/download/v6.0.11/electron-v6.0.11-win32-ia32.zip", Pkg.BinaryPlatforms.Windows(:i686)),
    ("https://github.com/electron/electron/releases/download/v6.0.11/electron-v6.0.11-linux-x64.zip", Pkg.BinaryPlatforms.Linux(:x86_64)),
    ("https://github.com/electron/electron/releases/download/v6.0.11/electron-v6.0.11-linux-arm64.zip", Pkg.BinaryPlatforms.Linux(:aarch64)),
    ("https://github.com/electron/electron/releases/download/v6.0.11/electron-v6.0.11-linux-armv7l.zip", Pkg.BinaryPlatforms.Linux(:armv7l)),
    ("https://github.com/electron/electron/releases/download/v6.0.11/electron-v6.0.11-linux-ia32.zip", Pkg.BinaryPlatforms.Linux(:i686)),
    ]

for (url, platform) in platforms

    Pkg.Artifacts.PlatformEngines.probe_platform_engines!()

    # This is the path to the Artifacts.toml we will manipulate
    artifact_toml = joinpath(@__DIR__, "..", "Artifacts.toml")

    mktempdir() do temp_dir

        download_path = joinpath(temp_dir, "foo.zip")
        download(url, download_path)

        sha_of_download = open(download_path) do f
            bytes2hex(sha2_256(f))
        end

        # create_artifact() returns the content-hash of the artifact directory once we're finished creating it
        electron_hash = create_artifact() do artifact_dir
            Pkg.Artifacts.PlatformEngines.unpack(download_path, artifact_dir)
        end
        # Now bind that hash within our `Artifacts.toml`.  `force = true` means that if it already exists,
        # just overwrite with the new content-hash.  Unless the source files change, we do not expect
        # the content hash to change, so this should not cause unnecessary version control churn.
        bind_artifact!(artifact_toml, artifact_name, electron_hash, platform=platform, download_info=([url], sha_of_download))
    end
end
