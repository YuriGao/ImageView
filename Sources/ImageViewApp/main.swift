import AppKit
import Foundation

let arguments = CommandLine.arguments
let benchmarkURL: URL? = arguments.firstIndex(of: "--benchmark-open").flatMap { index in
    let valueIndex = arguments.index(after: index)
    guard arguments.indices.contains(valueIndex) else { return nil }
    return URL(fileURLWithPath: arguments[valueIndex])
}
let settings = AppSettings(
    showsFilmstripOverride: arguments.contains("--benchmark-show-filmstrip") ? true : nil
)

let app = NSApplication.shared
let delegate = AppDelegate(settings: settings, initialURLs: benchmarkURL.map { [$0] } ?? [])
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
