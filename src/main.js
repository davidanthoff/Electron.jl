const {app, BrowserWindow} = require('electron')
const path = require('path')
const url = require('url')
const net = require('net')
const os = require('os')
const readline = require('readline')

function createWindow(connection, opts) {
    var win = new BrowserWindow(opts)
    win.loadURL(opts.url ? opts.url : "about:blank")
    win.setMenu(null)
    // win.webContents.openDevTools()

    // Create a local variable that we'll use in
    // the closed event handler because the property
    // .id won't be accessible anymore when the window
    // has been closed.
    var win_id = win.id

    win.webContents.on("did-finish-load", function() {
        connection.write(JSON.stringify({data: win_id}) + '\n')

        win.on('closed', function() {
            sysnotify_connection.write(JSON.stringify({cmd: "windowclosed", winid: win_id}) + '\n')
        })
    })
}

function process_command(connection, cmd) {
    if (cmd.cmd == 'runcode' && cmd.target == 'app') {
        var retvar;
        try {
            retval = {data: eval(cmd.code)}
        } catch (errval) {
            retval = {error: JSON.stringify(errval)}
        }
        connection.write(JSON.stringify(retval) + '\n')
    }
    else if (cmd.cmd == 'runcode' && cmd.target == 'window') {
        var win = BrowserWindow.fromId(cmd.winid)
        win.webContents.executeJavaScript(cmd.code, true)
            .then(function(result) {
                connection.write(JSON.stringify({data: result}) + '\n')
            }).catch(function(err) { // TODO: electron doesn't seem to call this and merely crashes instead
                connection.write(JSON.stringify({error: err}) + '\n')
            })
    }
    else if (cmd.cmd == 'closewindow') {
        var win = BrowserWindow.fromId(cmd.winid)
        win.destroy()
        connection.write(JSON.stringify({}) + '\n')
    }
    else if (cmd.cmd == 'newwindow') {
        createWindow(connection, cmd.options)
    }
}

sysnotify_connection = null
secure_cookie = ""

function secure_connect(addr) {
    var connection = net.connect(addr);
    connection.setEncoding('utf8')
    connection.write(secure_cookie);
    return connection;
}

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.
app.on('ready', function() {
    var chunks = [];
    process.stdin.on('data', function(chunk) { chunks.push(chunk); });
    process.stdin.on('end', function() {
        secure_cookie = Buffer.concat(chunks);

        var connection = secure_connect(process.argv[2])
        sysnotify_connection = secure_connect(process.argv[3])

        connection.on('end', function() {
            // TODO: simply reconnect
            sysnotify_connection.write(JSON.stringify({cmd: "appclosing"}) + '\n')
            app.quit()
        })

        const rloptions = {input: connection, terminal: false, historySize: 0, crlfDelay: Infinity}
        const rl = readline.createInterface(rloptions)

        rl.on('line', function(line) {
            cmd_as_json = JSON.parse(line)
            process_command(connection, cmd_as_json)
        })
    })
})

app.on('window-all-closed', function() {

})
