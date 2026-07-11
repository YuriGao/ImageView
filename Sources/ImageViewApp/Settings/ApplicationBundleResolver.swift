import Foundation

struct ApplicationBundleInfo: Equatable {
    let url: URL
    let bundleIdentifier: String?
    let displayName: String
}

protocol ApplicationBundleResolving: AnyObject {
    func validatedRunningApplication(at url: URL?) -> ApplicationBundleInfo?
    func application(at url: URL) -> ApplicationBundleInfo?
}

final class BundleApplicationResolver: ApplicationBundleResolving {
    private let currentExecutableURL: () -> URL?

    init(currentExecutableURL: @escaping () -> URL? = { Bundle.main.executableURL }) {
        self.currentExecutableURL = currentExecutableURL
    }

    func validatedRunningApplication(at url: URL?) -> ApplicationBundleInfo? {
        guard let url,
              let info = application(at: url),
              let currentExecutable = currentExecutableURL()?.resolvingSymlinksInPath().standardizedFileURL
        else { return nil }

        let bundleURL = info.url.resolvingSymlinksInPath().standardizedFileURL
        guard currentExecutable.path.hasPrefix(bundleURL.path + "/") else { return nil }
        return info
    }

    func application(at url: URL) -> ApplicationBundleInfo? {
        let normalizedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard normalizedURL.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: normalizedURL),
              let executableURL = bundle.executableURL?.resolvingSymlinksInPath().standardizedFileURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path)
        else { return nil }

        let localized = bundle.localizedInfoDictionary
        let displayName = (localized?["CFBundleDisplayName"] as? String)
            ?? (localized?["CFBundleName"] as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? normalizedURL.deletingPathExtension().lastPathComponent
        return ApplicationBundleInfo(
            url: normalizedURL,
            bundleIdentifier: bundle.bundleIdentifier,
            displayName: displayName
        )
    }
}
