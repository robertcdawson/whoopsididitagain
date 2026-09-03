import AppIntents

struct WhoopsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteDocketItemIntent(),
            phrases: [
                "Complete \(\.$item) in \(.applicationName)",
                "Log \(\.$item) in \(.applicationName)",
                "Mark \(\.$item) done in \(.applicationName)",
            ],
            shortTitle: "Complete docket item",
            systemImageName: "checkmark.circle"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .navy
}
