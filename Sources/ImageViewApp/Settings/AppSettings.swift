import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    @Published var pinsHUD: Bool {
        didSet { defaults.set(pinsHUD, forKey: Self.pinsHUDKey) }
    }

    @Published var showsFilmstrip: Bool {
        didSet { defaults.set(showsFilmstrip, forKey: Self.showsFilmstripKey) }
    }

    @Published var showsInspector: Bool {
        didSet { defaults.set(showsInspector, forKey: Self.showsInspectorKey) }
    }

    @Published var confirmsDelete: Bool {
        didSet { defaults.set(confirmsDelete, forKey: Self.confirmsDeleteKey) }
    }

    @Published var usesBlackFullscreenBackground: Bool {
        didSet { defaults.set(usesBlackFullscreenBackground, forKey: Self.usesBlackFullscreenBackgroundKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinsHUD = defaults.bool(forKey: Self.pinsHUDKey)
        showsFilmstrip = defaults.bool(forKey: Self.showsFilmstripKey)
        showsInspector = defaults.bool(forKey: Self.showsInspectorKey)
        confirmsDelete = defaults.object(forKey: Self.confirmsDeleteKey) as? Bool ?? true
        usesBlackFullscreenBackground = defaults.object(forKey: Self.usesBlackFullscreenBackgroundKey) as? Bool ?? true
    }
}

private extension AppSettings {
    static let pinsHUDKey = "pinsHUD"
    static let showsFilmstripKey = "showsFilmstrip"
    static let showsInspectorKey = "showsInspector"
    static let confirmsDeleteKey = "confirmsDelete"
    static let usesBlackFullscreenBackgroundKey = "usesBlackFullscreenBackground"
}
