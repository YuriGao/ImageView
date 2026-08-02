import Foundation

struct AppReleaseVersion: Comparable, Equatable, Sendable {
    let components: [Int]

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }
        normalized = String(normalized.split(separator: "-", maxSplits: 1).first ?? "")
        let fields = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !fields.isEmpty,
              fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              fields.compactMap({ Int($0) }).count == fields.count else {
            return nil
        }
        components = fields.compactMap { Int($0) }
    }

    static func < (lhs: AppReleaseVersion, rhs: AppReleaseVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppReleaseVersion, rhs: AppReleaseVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct GitHubRelease: Decodable, Equatable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let body: String?
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case assets
    }

    var downloadURL: URL {
        assets.first { $0.name.caseInsensitiveCompare("ImageView.dmg") == .orderedSame }?.browserDownloadURL
            ?? assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL
            ?? htmlURL
    }
}

enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(release: GitHubRelease, currentVersion: String)
    case upToDate(currentVersion: String)
}

enum UpdateCheckError: LocalizedError, Equatable {
    case invalidResponse
    case invalidVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case let .invalidVersion(version):
            return "Invalid release version: \(version)"
        }
    }
}

struct GitHubReleaseUpdateService: Sendable {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/YuriGao/ImageView/releases/latest"
    )!

    private let loadData: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        loadData: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) {
        self.loadData = loadData
    }

    func check(currentVersion: String) async throws -> UpdateCheckResult {
        let request = Self.makeRequest(currentVersion: currentVersion)

        let (data, response) = try await loadData(request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.invalidResponse
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let current = AppReleaseVersion(currentVersion) else {
            throw UpdateCheckError.invalidVersion(currentVersion)
        }
        guard let latest = AppReleaseVersion(release.tagName) else {
            throw UpdateCheckError.invalidVersion(release.tagName)
        }
        return latest > current
            ? .updateAvailable(release: release, currentVersion: currentVersion)
            : .upToDate(currentVersion: currentVersion)
    }

    static func makeRequest(currentVersion: String) -> URLRequest {
        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ImageView/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        return request
    }
}
