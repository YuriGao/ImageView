import Combine
import Foundation

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark
}

enum ReadingDirection: String, CaseIterable {
    case leftToRight
    case rightToLeft
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

    @Published var usesContinuousReading: Bool {
        didSet { defaults.set(usesContinuousReading, forKey: Self.usesContinuousReadingKey) }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    @Published var readingDirection: ReadingDirection {
        didSet { defaults.set(readingDirection.rawValue, forKey: Self.readingDirectionKey) }
    }

    @Published var hasShownUsageHint: Bool {
        didSet { defaults.set(hasShownUsageHint, forKey: Self.hasShownUsageHintKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsFilmstrip = defaults.bool(forKey: Self.showsFilmstripKey)
        showsInspector = defaults.bool(forKey: Self.showsInspectorKey)
        confirmsDelete = defaults.object(forKey: Self.confirmsDeleteKey) as? Bool ?? true
        animatesNavigationTransitions = defaults.object(forKey: Self.animatesNavigationTransitionsKey) as? Bool ?? true
        usesContinuousReading = defaults.bool(forKey: Self.usesContinuousReadingKey)
        appearance = AppAppearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
        readingDirection = ReadingDirection(
            rawValue: defaults.string(forKey: Self.readingDirectionKey) ?? ""
        ) ?? .leftToRight
        hasShownUsageHint = defaults.bool(forKey: Self.hasShownUsageHintKey)
    }
}

private extension AppSettings {
    static let showsFilmstripKey = "showsFilmstrip"
    static let showsInspectorKey = "showsInspector"
    static let confirmsDeleteKey = "confirmsDelete"
    static let animatesNavigationTransitionsKey = "animatesNavigationTransitions"
    static let usesContinuousReadingKey = "usesContinuousReading"
    static let appearanceKey = "appearance"
    static let readingDirectionKey = "readingDirection"
    static let hasShownUsageHintKey = "hasShownUsageHint"
}
