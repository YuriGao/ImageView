import Foundation
import XCTest
@testable import ImageViewApp

final class ApplicationBundleResolverTests: XCTestCase {
    func testRejectsNilNonexistentAndOrdinaryAppDirectory() throws {
        let root = temporaryDirectory()
        let fake = root.appendingPathComponent("Fake.app", isDirectory: true)
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        let resolver = BundleApplicationResolver(currentExecutableURL: { root.appendingPathComponent("ImageView") })

        XCTAssertNil(resolver.validatedRunningApplication(at: nil))
        XCTAssertNil(resolver.validatedRunningApplication(at: root.appendingPathComponent("Missing.app")))
        XCTAssertNil(resolver.validatedRunningApplication(at: fake))
    }

    func testRejectsBundleThatDoesNotContainCurrentExecutable() throws {
        let root = temporaryDirectory()
        let app = try makeBundle(at: root, name: "Fake", identifier: "com.example.fake")
        let resolver = BundleApplicationResolver(currentExecutableURL: { root.appendingPathComponent("Elsewhere/ImageView") })

        XCTAssertNil(resolver.validatedRunningApplication(at: app))
    }

    func testAcceptsRealBundleContainingCurrentExecutableAndReadsDisplayName() throws {
        let root = temporaryDirectory()
        let app = try makeBundle(at: root, name: "Fake", identifier: "com.example.fake", displayName: "Localized Fake")
        let executable = app.appendingPathComponent("Contents/MacOS/Fake")
        let resolver = BundleApplicationResolver(currentExecutableURL: { executable })

        let info = try XCTUnwrap(resolver.validatedRunningApplication(at: app))
        XCTAssertEqual(info.bundleIdentifier, "com.example.fake")
        XCTAssertEqual(info.displayName, "Localized Fake")
    }

    func testApplicationNameFallsBackToBundleFilename() throws {
        let root = temporaryDirectory()
        let app = try makeBundle(
            at: root,
            name: "Filename Fallback",
            identifier: "com.example.fallback",
            includesDisplayMetadata: false
        )
        let resolver = BundleApplicationResolver()

        XCTAssertEqual(resolver.application(at: app)?.displayName, "Filename Fallback")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeBundle(
        at root: URL,
        name: String,
        identifier: String,
        displayName: String? = nil,
        includesDisplayMetadata: Bool = true
    ) throws -> URL {
        let app = root.appendingPathComponent("\(name).app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "CFBundleExecutable": name,
            "CFBundleIdentifier": identifier
        ]
        if includesDisplayMetadata {
            plist["CFBundleName"] = name
            plist["CFBundleDisplayName"] = displayName ?? name
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        FileManager.default.createFile(atPath: macOS.appendingPathComponent(name).path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macOS.appendingPathComponent(name).path)
        return app
    }
}
