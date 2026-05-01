import Foundation

@MainActor
enum PluginRegistry {
    static func makePlugins() -> [any PowerShellPlugin] {
        [
            SplitPlugin(),
        ]
    }
}
