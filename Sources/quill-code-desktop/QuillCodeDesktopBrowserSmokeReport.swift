import Foundation

struct QuillCodeDesktopBrowserSmokeReport {
    var previewPath: String
    var url: String
    var title: String
    var status: String
    var sourceLabel: String
    var inspectionDepth: String
    var outline: [String]
    var textSnippet: String
    var commentCount: Int
    var toolName: String
    var finalAnswer: String

    var dictionary: [String: Any] {
        [
            "previewPath": previewPath,
            "url": url,
            "title": title,
            "status": status,
            "sourceLabel": sourceLabel,
            "inspectionDepth": inspectionDepth,
            "outline": outline,
            "textSnippet": textSnippet,
            "commentCount": commentCount,
            "toolName": toolName,
            "finalAnswer": finalAnswer
        ]
    }
}
