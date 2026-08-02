import Foundation
import XCTest
@testable import ImageViewApp

final class GitHubReleaseUpdateServiceTests: XCTestCase {
    func testVersionComparisonUsesNumericComponents() throws {
        XCTAssertLessThan(
            try XCTUnwrap(AppReleaseVersion("v0.1.9")),
            try XCTUnwrap(AppReleaseVersion("0.1.10"))
        )
        XCTAssertEqual(
            try XCTUnwrap(AppReleaseVersion("1.2")),
            try XCTUnwrap(AppReleaseVersion("1.2.0"))
        )
        XCTAssertNil(AppReleaseVersion("latest"))
    }

    func testRequestUsesGitHubLatestReleaseAPIAndRecommendedHeaders() {
        let request = GitHubReleaseUpdateService.makeRequest(currentVersion: "0.1.7")

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/YuriGao/ImageView/releases/latest"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "ImageView/0.1.7")
        XCTAssertEqual(request.timeoutInterval, 15)
    }

    func testNewerReleaseSelectsNamedDMGAsset() async throws {
        let data = Data(
            """
            {
              "tag_name": "v0.1.10",
              "body": "Release notes",
              "html_url": "https://github.com/YuriGao/ImageView/releases/tag/v0.1.10",
              "assets": [
                {
                  "name": "source.zip",
                  "browser_download_url": "https://github.com/YuriGao/ImageView/releases/download/v0.1.10/source.zip"
                },
                {
                  "name": "ImageView.dmg",
                  "browser_download_url": "https://github.com/YuriGao/ImageView/releases/download/v0.1.10/ImageView.dmg"
                }
              ]
            }
            """.utf8
        )
        let response = try XCTUnwrap(HTTPURLResponse(
            url: GitHubReleaseUpdateService.latestReleaseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let service = GitHubReleaseUpdateService { _ in (data, response) }

        let result = try await service.check(currentVersion: "0.1.9")

        guard case let .updateAvailable(release, currentVersion) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(currentVersion, "0.1.9")
        XCTAssertEqual(release.tagName, "v0.1.10")
        XCTAssertEqual(
            release.downloadURL.absoluteString,
            "https://github.com/YuriGao/ImageView/releases/download/v0.1.10/ImageView.dmg"
        )
    }

    func testSameOrOlderReleaseReportsUpToDate() async throws {
        let data = Data(
            """
            {
              "tag_name": "v0.1.7",
              "body": null,
              "html_url": "https://github.com/YuriGao/ImageView/releases/tag/v0.1.7",
              "assets": []
            }
            """.utf8
        )
        let response = try XCTUnwrap(HTTPURLResponse(
            url: GitHubReleaseUpdateService.latestReleaseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let service = GitHubReleaseUpdateService { _ in (data, response) }

        let result = try await service.check(currentVersion: "0.1.7")
        XCTAssertEqual(result, .upToDate(currentVersion: "0.1.7"))
    }

    func testNonSuccessHTTPResponseFailsCleanly() async throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: GitHubReleaseUpdateService.latestReleaseURL,
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        ))
        let service = GitHubReleaseUpdateService { _ in (Data(), response) }

        do {
            _ = try await service.check(currentVersion: "0.1.7")
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? UpdateCheckError, .invalidResponse)
        }
    }
}
