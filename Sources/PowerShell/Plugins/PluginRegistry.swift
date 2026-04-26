import Foundation

@MainActor
enum PluginRegistry {
    static func makePlugins() -> [any PowerShellPlugin] {
        [
            // 在这里添加新插件：
            // MyTeamFeaturePlugin(),
        ]
    }
}
