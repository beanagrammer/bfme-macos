import CoreGraphics
import Foundation
let d = CGMainDisplayID()
print("current: \(CGDisplayPixelsWide(d)) x \(CGDisplayPixelsHigh(d)) points")
let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
guard let modes = CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode] else { exit(1) }
var seen = Set<String>()
for m in modes {
    let w = m.width, h = m.height, pw = m.pixelWidth, ph = m.pixelHeight
    let key = "\(w)x\(h)@\(pw)x\(ph)"
    if seen.contains(key) { continue }
    seen.insert(key)
    if w >= 2000 {
        print("points \(w)x\(h)   pixels \(pw)x\(ph)   \(pw > w ? "HiDPI" : "1:1")")
    }
}
