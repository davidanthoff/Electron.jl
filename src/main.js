const {app, BrowserWindow} = require('electron')
const path = require('path')
const url = require('url')
const net = require('net')
const os = require('os')
const readline = require('readline')

// Window creation
var windows = {}

function createWindow(connection, opts) {
    win = new BrowserWindow(opts)
    windows[win.id] = win
    win.loadURL(opts.url ? opts.url : "about:blank")
    win.setMenu(null)
    // win.webContents.openDevTools()

    // Create a local variable that we'll use in
    // the closed event handler because the property
    // .id won't be accessible anymore when the window
    // has been closed.
    var win_id = win.id

    win.on('closed', function() {
        sysnotify_connection.write(JSON.stringify({cmd: "windowclosed", winid: win_id}) + '\n')
        delete windows[win_id]
    })

    win.webContents.on("did-finish-load", function() {
        connection.write(JSON.stringify({data: win.id}) + '\n')
    })
}

function generatePipeName(name) {
    if (process.platform === 'win32') {
        return '\\\\.\\pipe\\' + name
    }
    else {
        return path.join(os.tmpdir(), name)
    }
}

function process_command(connection, cmd) {
    if (cmd.cmd=='runcode' && cmd.target=='app') {
        retval = eval(cmd.code)
        connection.write(JSON.stringify({data: retval}) + '\n')
    }
    else if (cmd.cmd=='runcode' && cmd.target=='window') {
        win = windows[cmd.winid]
        win.webContents.executeJavaScript(cmd.code, true)
        .then(function(result) {
                connection.write(JSON.stringify({data: result}) + '\n')
            }).catch(function(err) {
                connection.write(JSON.stringify({error: err}) + '\n')
            })
    }
    else if (cmd.cmd=='closewindow') {
        win = windows[cmd.winid]
        win.destroy()
        connection.write(JSON.stringify({})+'\n')
    }
    else if (cmd.cmd == 'newwindow') {
        createWindow(connection, cmd.options)
    }
}

sysnotify_connection = null

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.
app.on('ready', function() {
    connection = net.connect(generatePipeName(process.argv[2]))
    connection.setEncoding('utf8')

    sysnotify_connection = net.connect(generatePipeName(process.argv[3]))
    sysnotify_connection.setEncoding('utf8')

    connection.on('end', function() {
        sysnotify_connection.write(JSON.stringify({cmd: "appclosing"}) + '\n')
        app.quit()
    })

    const rl = readline.createInterface({input: connection, terminal: false, historySize: 0, crlfDelay: Infinity})

    rl.on('line', function(line) {
        cmd_as_json = JSON.parse(line)
        process_command(connection, cmd_as_json)
    })
})

app.on('window-all-closed', function() {

})
