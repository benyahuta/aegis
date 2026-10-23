import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ShieldCore

/// OCR runs on-device with Vision (no permission prompt). These tests draw a fake "screenshot"
/// with CoreText, encode it as PNG, and read it back.
final class OCRTests: XCTestCase {
    static func renderPNG(lines: [String], width: Int = 1_200, lineHeight: Int = 70) throws -> Data {
        let height = lineHeight * (lines.count + 1)
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        for (index, line) in lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ]
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
            context.textPosition = CGPoint(x: 30, y: height - lineHeight * (index + 1))
            CTLineDraw(ctLine, context)
        }
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testRecognizesTextTopToBottom() async throws {
        let png = try Self.renderPNG(lines: ["Unpaid toll notice", "Pay now to avoid a late fee"])
        let text = try await OCR.recognizeText(in: png)
        let lower = text.lowercased()
        XCTAssertTrue(lower.contains("toll"), text)
        XCTAssertTrue(lower.contains("late fee"), text)
        let first = try XCTUnwrap(lower.range(of: "toll"))
        let second = try XCTUnwrap(lower.range(of: "late fee"))
        XCTAssertLessThan(first.lowerBound, second.lowerBound, "lines should come back top to bottom")
    }

    func testScreenshotPipelineGradesAScam() async throws {
        let png = try Self.renderPNG(lines: [
            "WARNING! Your Mac is infected with viruses.",
            "Do not close this window.",
            "Call Apple Support now: 1-844-555-0187",
        ])
        let result = await ScamChecker.assess(imageData: png)
        XCTAssertTrue(result.firedRules.contains(.warningWithPhone), "\(result.firedRules)")
        XCTAssertNotEqual(result.verdict, .noCommonSignsFound)
    }

    func testBlankImageIsBeCareful() async throws {
        let png = try Self.renderPNG(lines: [])
        let result = await ScamChecker.assess(imageData: png)
        XCTAssertEqual(result.verdict, .beCareful)
        XCTAssertEqual(result.limitations, [.unreadableImage])
    }

    func testGarbageDataThrows() async {
        do {
            _ = try await OCR.recognizeText(in: Data("not an image".utf8))
            XCTFail("expected unreadableImage")
        } catch {
            XCTAssertEqual(error, .unreadableImage)
        }
    }
}
