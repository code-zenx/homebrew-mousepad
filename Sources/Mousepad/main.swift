import AppKit

// No storyboard, no nib. Everything is built in code so it compiles with the
// command line tools alone.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = DocumentController()   // the first NSDocumentController created becomes `.shared`
app.setActivationPolicy(.regular)
app.run()
