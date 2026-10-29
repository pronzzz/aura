import AppKit

@main
enum AuraMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared

        // `Aura --snapshot <dir>` renders the notch states to PNGs (used for docs) and exits.
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let next = CommandLine.arguments.index(after: index)
            let dir = next < CommandLine.arguments.endIndex ? CommandLine.arguments[next] : "Snapshots"
            Runtime.isSnapshot = true
            Pref.registerDefaults()
            SnapshotRenderer.renderAll(to: URL(fileURLWithPath: dir))
            exit(0)
        }

        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
