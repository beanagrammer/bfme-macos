import Cocoa

// backdrop <pgrep-pattern>
//
// Fills the screen with black behind the game window. BFME must render 16:9 for
// the Arena's hardcoded coordinates, and most Macs are not 16:9, so a strip is
// always left over. Without this it is a hole showing whatever happens to be
// behind; with it the game reads as a normal letterboxed fullscreen game.
//
// Shown only while the game is running AND Wine is the frontmost application,
// so switching away with Cmd-Tab does not leave a black sheet over everything.
// Exits by itself once the game has been gone for a while, so nothing has to
// remember to clean it up.

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: backdrop <pgrep-pattern>\n".data(using: .utf8)!)
    exit(2)
}
let pattern = args[1]

func processExists(_ pattern: String) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-f", pattern]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

func wineIsFrontmost() -> Bool {
    guard let front = NSWorkspace.shared.frontmostApplication else { return false }
    let name = (front.executableURL?.lastPathComponent ?? front.localizedName ?? "").lowercased()
    return name.contains("wine")
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)          // no Dock icon, never steals focus

let screen = NSScreen.main ?? NSScreen.screens[0]
let window = NSWindow(contentRect: screen.frame,
                      styleMask: .borderless,
                      backing: .buffered,
                      defer: false)
window.backgroundColor = .black
window.isOpaque = true
window.hasShadow = false
window.ignoresMouseEvents = true             // clicks pass through to whatever is under
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
// Wine puts a fullscreen window at NSStatusWindowLevel + 1 (CGWindow layer 27),
// and the menu bar sits at 24. Status level (25) is therefore above the menu bar
// and every ordinary window, but still underneath the game.
window.level = .statusBar
window.setFrame(screen.frame, display: false)

var missingSince: Date? = nil
var everSeen = false
var visible = false
let started = Date()

Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
    let running = processExists(pattern)

    if running {
        everSeen = true
        missingSince = nil
    } else if everSeen {
        // Only start counting down once the game has actually been seen: under
        // the Arena it is launched minutes after this helper starts.
        if missingSince == nil {
            missingSince = Date()
        } else if Date().timeIntervalSince(missingSince!) > 20 {
            window.orderOut(nil)
            app.terminate(nil)
        }
    } else if Date().timeIntervalSince(started) > 6 * 3600 {
        // Nothing ever showed up; do not linger forever.
        app.terminate(nil)
    }

    let shouldShow = running && wineIsFrontmost()
    if shouldShow != visible {
        visible = shouldShow
        if shouldShow {
            window.setFrame((NSScreen.main ?? screen).frame, display: true)
            window.orderFront(nil)
        } else {
            window.orderOut(nil)
        }
    }
}

app.run()
