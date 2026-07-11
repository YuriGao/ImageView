import Combine
import Foundation

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    @Published var showsFilmstrip: Bool {
        didSet { defaults.set(showsFilmstrip, forKey: Self.showsFilmstripKey) }
    }

    @Published var showsInspector: Bool {
        didSet { defaults.set(showsInspector, forKey: Self.showsInspectorKey) }
    }

    @Published var confirmsDelete: Bool {
        didSet { defaults.set(confirmsDelete, forKey: Self.confirmsDeleteKey) }
    }

    @Published var animatesNavigationTransitions: Bool {
        didSet { defaults.set(animatesNavigationTransitions, forKey: Self.animatesNavigationTransitionsKey) }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsFilmstrip = defaults.bool(forKey: Self.showsFilmstripKey)
        showsInspector = defaults.bool(forKey: Self.showsInspectorKey)
        confirmsDelete = defaults.object(forKey: Self.confirmsDeleteKey) as? Bool ?? true
        animatesNavigationTransitions = defaults.object(forKey: Self.animatesNavigationTransitionsKey) as? Bool ?? true
        appearance = AppAppearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
    }
}

private extension AppSettings {
    static let showsFilmstripKey = "showsFilmstrip"
    static let showsInspectorKey = "showsInspector"
    static let confirmsDeleteKey = "confirmsDelete"
    static let animatesNavigationTransitionsKey = "animatesNavigationTransitions"
    static let appearanceKey = "appearance"
}
