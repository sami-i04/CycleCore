import AppKit
import IOKit
import UserNotifications
import ServiceManagement

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
