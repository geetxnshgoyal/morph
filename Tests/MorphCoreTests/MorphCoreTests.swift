import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MorphCore

final class MorphCoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("morph-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    /// A zip whose sizes and offsets lie must be refused or read as empty, never crash (the iPhone reads DOCX with this).
    func testBrokenZipDoesNotCrash() throws {
        let good = folder.appendingPathComponent("good.docx")
        try Zip.write([("word/document.xml", Data("<w:document/>".utf8))], to: good)
        XCTAssertEqual(try Zip.read(good)["word/document.xml"], Data("<w:document/>".utf8))

        let bytes = [UInt8](try Data(contentsOf: good))
        let central = bytes.count - 22 - 46 - "word/document.xml".utf8.count
        // Each case rewrites one field of the central directory with 0xFFFFFFFF, or cuts the file short.
        for (offset, length) in [(central + 42, 4), (central + 20, 4), (central + 24, 4), (central + 28, 2), (bytes.count - 6, 4)] {
            var broken = bytes
            for i in offset..<(offset + length) { broken[i] = 0xFF }
            let url = folder.appendingPathComponent("broken-\(offset).docx")
            try Data(broken).write(to: url)
            XCTAssertNil((try? Zip.read(url))?["word/document.xml"], "field at \(offset)")
        }
        let cut = folder.appendingPathComponent("cut.docx")
        try Data(bytes.prefix(bytes.count - 30)).write(to: cut)
        XCTAssertThrowsError(try Zip.read(cut))
    }

    /// A folder named like a tar option is archived, not obeyed.
    func testTarGzOfFolderNamedLikeAnOption() async throws {
        let odd = folder.appendingPathComponent("--version")
        try FileManager.default.createDirectory(at: odd, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: odd.appendingPathComponent("x.txt"))
        let out = try await ArchiveOps.tarGz([odd], options: Options())
        XCTAssertGreaterThan(Runner.size(of: out), 0)
    }

    /// Every image conversion this Mac offers makes a file from a plain PNG.
    func testImageConversions() async throws {
        let png = folder.appendingPathComponent("photo.png")
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let destination = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let actions = Library.actions(for: [png], group: .convert)
        XCTAssertFalse(actions.isEmpty)
        for action in actions {
            let result = await Runner.run(action, inputs: [png], record: false)
            XCTAssertEqual(result.failures, [], action.id)
            XCTAssertFalse(result.outputs.isEmpty, action.id)
        }
    }

    func testOutputNamesFromOtherAppsStayInFolder() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for base in ["../../x", "/etc/passwd", "..", "", "a/b"] {
            let url = Output.unique(in: dir, base: base, ext: "txt")
            XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path, dir.standardizedFileURL.path, base)
        }
    }

    func testHTMLLosesRemoteReferences() {
        let html = #"<img src="https://e.com/a.png"><img src='//e.com/b'><link href=http://e.com/c.css><div style="background:url( 'https://e.com/d')"></div><img srcset="x.png 1x, https://e.com/2x.png 2x"><style>@import "https://e.com/e.css";</style><img src="local.png">"#
        let clean = DocOps.withoutRemoteReferences(html)
        let loads = #"(\b(src|href|srcset)\s*=\s*["']?\s*(https?:)?//)|(url\(\s*["']?\s*(https?:)?//)|@import"#
        XCTAssertNil(clean.range(of: loads, options: [.regularExpression, .caseInsensitive]), clean)
        XCTAssertTrue(clean.contains("local.png"))
    }

    func testOutputSkipsDanglingSymlink() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("photo.jpg").path, withDestinationPath: "/tmp/\(UUID().uuidString)")
        XCTAssertEqual(Output.unique(in: dir, base: "photo", ext: "jpg").lastPathComponent, "photo 2.jpg")
    }

    /// Hand-built tar with "../escaped.txt" and "/abs.txt": bsdtar must keep both inside the folder.
    func testTarExtractionStaysInFolder() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func entry(_ name: String, _ body: String) -> Data {
            var h = [UInt8](repeating: 0, count: 512)
            func put(_ s: String, _ at: Int) { for (i, b) in s.utf8.enumerated() { h[at + i] = b } }
            put(name, 0); put("0000644", 100); put("0000000", 108); put("0000000", 116)
            put(String(format: "%011o", body.utf8.count), 124); put("00000000000", 136); put("0", 156); put("ustar", 257); put("00", 263)
            put("        ", 148)
            put(String(format: "%06o", h.reduce(0) { $0 + Int($1) }) + "\0 ", 148)
            var d = Data(h); d.append(Data(body.utf8)); d.append(Data(count: (512 - body.utf8.count % 512) % 512)); return d
        }
        var tar = entry("../escaped.txt", "x"); tar.append(entry("/abs-\(UUID().uuidString).txt", "y")); tar.append(Data(count: 1024))
        let archive = dir.appendingPathComponent("evil.tar"); try tar.write(to: archive)
        let folder = try? await ArchiveOps.extract(archive, options: Options())
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.deletingLastPathComponent().appendingPathComponent("escaped.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("escaped.txt").path))
        if let folder { XCTAssertTrue(folder.path.hasPrefix(dir.path)) }
    }
}
