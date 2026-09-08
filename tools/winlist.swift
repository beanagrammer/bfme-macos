import Cocoa
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    let name = w[kCGWindowName as String] as? String ?? ""
    let num = w[kCGWindowNumber as String] as? Int ?? 0
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
    if owner.lowercased().contains("wine") || name.lowercased().contains("wine") || name.lowercased().contains("bfme") || name.lowercased().contains("launcher") {
        print("id=\(num) pid=\(pid) layer=\(layer) owner=\(owner) name=\"\(name)\" bounds=\(b)")
    }
}
