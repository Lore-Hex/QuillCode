import XCTest
import QuillCodeCore

final class ToolErrorMessageTests: XCTestCase {
    private struct FlangeError: LocalizedError {
        var errorDescription: String? { "The widget is missing its flange." }
    }

    private struct EmptyDescriptionError: LocalizedError {
        var errorDescription: String? { "   " }
    }

    private enum DescribedError: Error, CustomStringConvertible {
        case bad(String)

        var description: String {
            switch self {
            case .bad(let detail):
                return "Bad thing: \(detail)"
            }
        }
    }

    private enum PlainError: Error {
        case somethingBroke(String)
    }

    func testLocalizedErrorSurfacesItsMessage() {
        XCTAssertEqual(ToolErrorMessage.describe(FlangeError()), "The widget is missing its flange.")
    }

    func testBlankLocalizedDescriptionFallsThrough() {
        // A whitespace-only errorDescription must not blank out the message entirely.
        XCTAssertFalse(ToolErrorMessage.describe(EmptyDescriptionError()).trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func testFoundationErrorUsesReadableDescriptionNotDomainDump() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoSuchFileError,
            userInfo: [NSLocalizedDescriptionKey: "The file could not be found."]
        )

        let message = ToolErrorMessage.describe(error)

        XCTAssertEqual(message, "The file could not be found.")
        XCTAssertFalse(message.contains("Error Domain="))
    }

    func testRealFileReadErrorIsReadable() {
        do {
            _ = try Data(contentsOf: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
            XCTFail("expected the read to throw")
        } catch {
            let message = ToolErrorMessage.describe(error)
            XCTAssertFalse(message.hasPrefix("Error Domain="), message)
        }
    }

    func testCustomStringConvertibleErrorKeepsItsDescription() {
        XCTAssertEqual(ToolErrorMessage.describe(DescribedError.bad("x")), "Bad thing: x")
    }

    func testPlainSwiftErrorFallsBackToCaseDescription() {
        XCTAssertEqual(ToolErrorMessage.describe(PlainError.somethingBroke("y")), #"somethingBroke("y")"#)
    }
}
