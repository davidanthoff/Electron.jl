const {app, BrowserWindow} = require('electron')
const path = require('path')
const url = require('url')
const net = require('net')
const os = require('os')

// Window creation
var windows = {}

function createWindow(opts) {
    win = new BrowserWindow(opts)
    windows[win.id] = win
    if (opts.url) {
        win.loadURL(opts.url)
    }
    win.setMenu(null)

    // Create a local variable that we'll use in
    // the closed event handler because the property
    // .id won't be accessible anymore when the window
    // has been closed.
    var win_id = win.id

    win.on('closed', function() {
        delete windows[win_id]
    })

    return win.id
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
    if (cmd.target=='app') {
        retval = eval(cmd.code)
        connection.write(JSON.stringify({data: retval}) + '\n')
    }
    else if (cmd.target=='window') {
        win = windows[cmd.winid]
        win.webContents.executeJavaScript(cmd.code).then(function(result) {
            connection.write(JSON.stringify({data: result}) + '\n')
        })
    }
}

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.
app.on('ready', function() {
    buffer = ['']

    connection = net.connect(generatePipeName(process.argv[2]))
    connection.setEncoding('utf8')

    connection.on('end', function() {
        app.quit()
    })

    connection.on('data', function(data) {
        lines = data.split('\n')
        buffer[0] += lines[0]
        for (var i = 1; i < lines.length; i++)
          buffer[buffer.length] = lines[i]

        while (buffer.length > 1) {
            cmd_as_json = JSON.parse(buffer.shift())
            process_command(connection, cmd_as_json)
        }
    });

})
