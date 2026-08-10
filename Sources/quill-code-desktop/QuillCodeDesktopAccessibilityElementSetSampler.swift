import Foundation

struct QuillCodeDesktopAccessibilityRequiredElementSample {
    var elementsByIdentifier: [String: QuillCodeDesktopAccessibilityElementSnapshot]
    var missingIdentifiers: Set<String>
    var sampleCount: Int

    var isComplete: Bool {
        missingIdentifiers.isEmpty
    }
}

@MainActor
enum QuillCodeDesktopAccessibilityElementSetSampler {
    static func waitForRequiredElements(
        _ identifiers: Set<String>,
        maximumAttempts: Int = 100,
        retryIntervalNanoseconds: UInt64 = 50_000_000,
        elements: () -> [QuillCodeDesktopAccessibilityElementSnapshot]
    ) async -> QuillCodeDesktopAccessibilityRequiredElementSample {
        guard !identifiers.isEmpty else {
            return .init(elementsByIdentifier: [:], missingIdentifiers: [], sampleCount: 0)
        }

        let attemptCount = max(1, maximumAttempts)
        var latest = requiredElements(identifiers, in: [], sampleCount: 0)
        for attempt in 0..<attemptCount {
            latest = requiredElements(
                identifiers,
                in: elements(),
                sampleCount: attempt + 1
            )
            if latest.isComplete {
                return latest
            }
            guard attempt + 1 < attemptCount, !Task.isCancelled else { break }
            try? await Task.sleep(nanoseconds: retryIntervalNanoseconds)
        }
        return latest
    }

    private static func requiredElements(
        _ identifiers: Set<String>,
        in elements: [QuillCodeDesktopAccessibilityElementSnapshot],
        sampleCount: Int
    ) -> QuillCodeDesktopAccessibilityRequiredElementSample {
        let candidatesByIdentifier = Dictionary(grouping: elements, by: \.identifier)
        var resolved: [String: QuillCodeDesktopAccessibilityElementSnapshot] = [:]
        resolved.reserveCapacity(identifiers.count)

        for identifier in identifiers {
            resolved[identifier] = candidatesByIdentifier[identifier]?
                .max { $0.frameArea < $1.frameArea }
        }
        return .init(
            elementsByIdentifier: resolved,
            missingIdentifiers: identifiers.subtracting(resolved.keys),
            sampleCount: sampleCount
        )
    }
}
