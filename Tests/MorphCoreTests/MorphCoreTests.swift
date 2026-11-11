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
}
