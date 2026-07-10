import Combine
import Foundation

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsFilmstrip = defaults.bool(forKey: Self.showsFilmstripKey)
        showsInspector = defaults.bool(forKey: Self.showsInspectorKey)
        confirmsDelete = defaults.object(forKey: Self.confirmsDeleteKey) as? Bool ?? true
        animatesNavigationTransitions = defaults.object(forKey: Self.animatesNavigationTransitionsKey) as? Bool ?? true
    }
}

private extension AppSettings {
    static let showsFilmstripKey = "showsFilmstrip"
    static let showsInspectorKey = "showsInspector"
    static let confirmsDeleteKey = "confirmsDelete"
    static let animatesNavigationTransitionsKey = "animatesNavigationTransitions"
}
