import Foundation

enum CLIDoctorStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case ok
    case warning
    case fail

    var rank: Int {
        switch self {
        case .ok: 0
        case .warning: 1
        case .fail: 2
        }
    }
}

enum CLIDoctorDetail: Codable, Sendable, Equatable {
    case text(String)
    case list([String])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .text(value)
        } else {
            self = .list(try container.decode([String].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .list(let values):
            try container.encode(values)
        }
    }
}

struct CLIDoctorIssue: Codable, Sendable, Equatable {
    var severity: CLIDoctorStatus
    var cause: String
    var measured: String?
    var expected: String?
    var remedy: String?
    var fields: [String]

    init(
        severity: CLIDoctorStatus,
        cause: String,
        measured: String? = nil,
        expected: String? = nil,
        remedy: String? = nil,
        fields: [String] = []
    ) {
        self.severity = severity
        self.cause = cause
        self.measured = measured
        self.expected = expected
        self.remedy = remedy
        self.fields = fields
    }
}

struct CLIDoctorCheck: Codable, Sendable, Equatable {
    var id: String
    var category: String
    var status: CLIDoctorStatus
    var summary: String
    var details: [String: CLIDoctorDetail]
    var remediation: String?
    var issues: [CLIDoctorIssue]
    var durationMs: Int

    init(
        id: String,
        category: String,
        status: CLIDoctorStatus,
        summary: String,
        details: [String: CLIDoctorDetail] = [:],
        remediation: String? = nil,
        issues: [CLIDoctorIssue] = [],
        durationMs: Int = 0
    ) {
        self.id = id
        self.category = category
        self.status = status
        self.summary = summary
        self.details = details
        self.remediation = remediation
        self.issues = issues
        self.durationMs = durationMs
    }
}

struct CLIDoctorReport: Codable, Sendable, Equatable {
    static let schemaVersion = 1

    var schemaVersion: Int
    var generatedAt: String
    var overallStatus: CLIDoctorStatus
    var quillCodeVersion: String
    var checks: [String: CLIDoctorCheck]

    init(
        generatedAt: String,
        quillCodeVersion: String,
        checks: [CLIDoctorCheck]
    ) {
        self.schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        self.overallStatus = checks.map(\.status).max { $0.rank < $1.rank } ?? .ok
        self.quillCodeVersion = quillCodeVersion
        self.checks = Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0) })
    }

    var exitStatus: Int32 {
        overallStatus == .fail ? 1 : 0
    }

    var orderedChecks: [CLIDoctorCheck] {
        checks.values.sorted {
            let lhsCategory = Self.categoryOrder[$0.category] ?? Int.max
            let rhsCategory = Self.categoryOrder[$1.category] ?? Int.max
            if lhsCategory != rhsCategory { return lhsCategory < rhsCategory }
            if $0.category != $1.category { return $0.category < $1.category }
            return $0.id < $1.id
        }
    }

    private static let categoryOrder: [String: Int] = [
        "system": 0,
        "runtime": 1,
        "install": 2,
        "search": 3,
        "git": 4,
        "terminal": 5,
        "config": 6,
        "auth": 7,
        "mcp": 8,
        "sandbox": 9,
        "state": 10,
        "threads": 11,
        "network": 12,
        "reachability": 13,
        "app-server": 14
    ]
}

extension Dictionary where Key == String, Value == CLIDoctorDetail {
    static func doctorDetails(_ values: [String: String]) -> Self {
        values.mapValues { .text(CLIDoctorSanitizer.singleLine($0)) }
    }
}

enum CLIDoctorSanitizer {
    static let maximumDetailCharacters = 1_024

    static func singleLine(_ value: String, limit: Int = maximumDetailCharacters) -> String {
        let normalized = value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(max(0, limit - 1))) + "…"
    }

    static func safeURL(_ value: String) -> String {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme,
              let host = components.host else {
            return "invalid URL"
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.scheme = scheme
        components.host = host
        return components.url?.absoluteString ?? "invalid URL"
    }

    static func redacted(_ value: String, secrets: [String?]) -> String {
        secrets.compactMap { secret in
            let normalized = secret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return normalized.isEmpty ? nil : normalized
        }.reduce(singleLine(value)) { result, secret in
            result.replacingOccurrences(of: secret, with: "<redacted>")
        }
    }
}
