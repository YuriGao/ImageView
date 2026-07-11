import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import ImageViewApp

@MainActor
final class DefaultApplicationServiceTests: XCTestCase {
    func testQueryForwardsContentTypeToWorkspaceClient() {
        let expected = URL(fileURLWithPath: "/Applications/Preview.app")
        let client = WorkspaceClientSpy(defaultURL: expected)
        let service = WorkspaceDefaultApplicationService(client: client)

        XCTAssertEqual(service.defaultApplicationURL(for: .png), expected)
        XCTAssertEqual(client.queriedTypes, [.png])
    }

    func testSetForwardsApplicationURLAndContentType() async throws {
        let client = WorkspaceClientSpy()
        let service = WorkspaceDefaultApplicationService(client: client)
        let appURL = URL(fileURLWithPath: "/Applications/ImageView.app")

        try await service.setDefaultApplication(at: appURL, for: .jpeg)

        XCTAssertEqual(client.setRequests.map(\.0), [appURL])
        XCTAssertEqual(client.setRequests.map(\.1), [.jpeg])
    }

    func testSetPropagatesWorkspaceError() async {
        let client = WorkspaceClientSpy(setError: TestError.denied)
        let service = WorkspaceDefaultApplicationService(client: client)

        await XCTAssertThrowsErrorAsync {
            try await service.setDefaultApplication(
                at: URL(fileURLWithPath: "/Applications/ImageView.app"),
                for: .gif
            )
        }
    }
}

private enum TestError: Error { case denied }

@MainActor
private final class WorkspaceClientSpy: WorkspaceDefaultApplicationClient {
    var queriedTypes: [UTType] = []
    var setRequests: [(URL, UTType)] = []
    let defaultURL: URL?
    let setError: Error?

    init(defaultURL: URL? = nil, setError: Error? = nil) {
        self.defaultURL = defaultURL
        self.setError = setError
    }

    func defaultApplicationURL(for contentType: UTType) -> URL? {
        queriedTypes.append(contentType)
        return defaultURL
    }

    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {
        setRequests.append((applicationURL, contentType))
        if let setError { throw setError }
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
