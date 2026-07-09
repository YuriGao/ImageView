import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var pinsHUD: Bool {
        didSet { UserDefaults.standard.set(pinsHUD, forKey: "pinsHUD") }
    }

    @Published var confirmsDelete: Bool {
        didSet { UserDefaults.standard.set(confirmsDelete, forKey: "confirmsDelete") }
    }

    @Published var usesBlackFullscreenBackground: Bool {
        didSet { UserDefaults.standard.set(usesBlackFullscreenBackground, forKey: "usesBlackFullscreenBackground") }
    }

    init() {
        pinsHUD = UserDefaults.standard.bool(forKey: "pinsHUD")
        confirmsDelete = UserDefaults.standard.object(forKey: "confirmsDelete") as? Bool ?? true
        usesBlackFullscreenBackground = UserDefaults.standard.object(forKey: "usesBlackFullscreenBackground") as? Bool ?? true
    }
}
