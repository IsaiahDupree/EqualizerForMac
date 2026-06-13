// Print the on-screen window ID of an app by owner name (for screencapture -l<id>).
// Usage: window_id SonanceEQ
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "SonanceEQ"
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for info in infos {
    guard let name = info[kCGWindowOwnerName as String] as? String, name.contains(owner) else { continue }
    guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }  // normal window
    if let number = info[kCGWindowNumber as String] as? Int {
        print(number)
        exit(0)
    }
}
exit(2)
