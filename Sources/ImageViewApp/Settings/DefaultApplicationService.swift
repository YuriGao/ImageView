import AppKit
import UniformTypeIdentifiers

@MainActor
protocol DefaultApplicationServicing: AnyObject {
    func defaultApplicationURL(for contentType: UTType) -> URL?
    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws
}

@MainActor
protocol WorkspaceDefaultApplicationClient: AnyObject {
    func defaultApplicationURL(for contentType: UTType) -> URL?
    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws
}

@MainActor
final class WorkspaceDefaultApplicationService: DefaultApplicationServicing {
    private let client: WorkspaceDefaultApplicationClient

    init(client: WorkspaceDefaultApplicationClient = NSWorkspace.shared) {
        self.client = client
    }

    func defaultApplicationURL(for contentType: UTType) -> URL? {
        client.defaultApplicationURL(for: contentType)
    }

    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {
        try await client.setDefaultApplication(at: applicationURL, for: contentType)
    }
}

extension NSWorkspace: WorkspaceDefaultApplicationClient {
    func defaultApplicationURL(for contentType: UTType) -> URL? {
        urlForApplication(toOpen: contentType)
    }

    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setDefaultApplication(at: applicationURL, toOpen: contentType) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
