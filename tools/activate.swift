// Bring a process to the front and say, truthfully, whether it worked.
//
//   activate <pid> [x y]
//
// Wine's game window belongs to a process with no app bundle. Neither
// NSRunningApplication.activate() nor System Events' "set frontmost" will
// raise it: macOS does not let a command-line tool with no activation policy
// take focus from the terminal that launched it. A real mouse click at the
// window does, because that is the ordinary way a person focuses a window.
//
// This matters beyond convenience. Synthesised keystrokes go to whatever is
// frontmost, so a tool that assumes activation worked types into the user's
// terminal instead of the game. Exit status is the check: 0 only if the pid
// really is frontmost afterwards.
import AppKit

let args = CommandLine.arguments
guard args.count > 1, let pid = Int32(args[1]) else {
    FileHandle.standardError.write("usage: activate <pid> [x y]\n".data(using: .utf8)!)
    exit(2)
}
guard let app = NSRunningApplication(processIdentifier: pid) else {
    FileHandle.standardError.write("no running application with pid \(pid)\n".data(using: .utf8)!)
    exit(1)
}

func frontmost() -> NSRunningApplication? { NSWorkspace.shared.frontmostApplication }

func settled(_ tries: Int) -> Bool {
    for _ in 0..<tries {
        usleep(100_000)
        if frontmost()?.processIdentifier == pid { return true }
    }
    return false
}

let policy: String
switch app.activationPolicy {
case .regular:    policy = "regular"
case .accessory:  policy = "accessory"
case .prohibited: policy = "prohibited"
@unknown default: policy = "unknown"
}
FileHandle.standardError.write("pid \(pid) bundle=\(app.bundleIdentifier ?? "none") policy=\(policy)\n".data(using: .utf8)!)

app.activate(options: [.activateAllWindows])
if settled(10) {
    print("frontmost pid=\(pid) \(app.localizedName ?? "?") (activate)")
    exit(0)
}

// Fall back to a click, which needs a point inside the window.
if args.count > 3, let x = Double(args[2]), let y = Double(args[3]) {
    let pt = CGPoint(x: x, y: y)
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                       mouseCursorPosition: pt, mouseButton: .left)
    let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                     mouseCursorPosition: pt, mouseButton: .left)
    down?.post(tap: .cghidEventTap)
    usleep(80_000)
    up?.post(tap: .cghidEventTap)
    if settled(20) {
        print("frontmost pid=\(pid) \(app.localizedName ?? "?") (click at \(Int(x)),\(Int(y)))")
        exit(0)
    }
}

let f = frontmost()
print("FAILED: frontmost is pid=\(f?.processIdentifier ?? -1) \(f?.localizedName ?? "?")")
exit(1)
