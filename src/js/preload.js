// Electron.jl preload script.
//
// A preload script runs before any script of the loaded page, so
// `sendMessageToJulia` is available to inline `<head>` scripts, to
// `window.onload` handlers and to promise callbacks. This is what makes
// Electron.jl usable from ordinary page code (see issues #34 and #143).
//
// This script must work both with and without context isolation, because
// users can override `nodeIntegration`/`contextIsolation` via the
// `webPreferences` option of `Window`.

const { contextBridge, ipcRenderer } = require('electron')

function sendMessageToJulia(message) {
    ipcRenderer.send('msg-for-julia-process', message)
}

if (process.contextIsolated) {
    // With context isolation the preload script runs in a separate world, so
    // the function has to be bridged explicitly into the page's world.
    try {
        contextBridge.exposeInMainWorld('sendMessageToJulia', sendMessageToJulia)
    } catch (err) {
        console.error('Electron.jl: could not expose sendMessageToJulia:', err)
    }
} else {
    // Without context isolation the preload script shares the page's world,
    // so a plain global assignment is enough.
    window.sendMessageToJulia = sendMessageToJulia
    if (typeof global !== 'undefined') {
        global.sendMessageToJulia = sendMessageToJulia
    }
}
