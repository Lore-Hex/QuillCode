import Foundation
import QuillCodeCore

enum WorkspacePullRequestReviewThreadsParser {
    static func parse(_ output: String, selector: String? = nil) -> [WorkspacePullRequestReviewThreadSurface] {
        guard let response = try? JSONHelpers.decode(PullRequestReviewThreadsResponse.self, from: output),
              let nodes = response.data?.repository?.pullRequest?.reviewThreads.nodes
        else {
            return []
        }
        return nodes.map { node in
            WorkspacePullRequestReviewThreadSurface(
                id: node.id,
                isResolved: node.isResolved,
                isOutdated: node.isOutdated,
                path: node.path,
                line: node.line,
                startLine: node.startLine,
                comments: node.comments.nodes.map { comment in
                    WorkspacePullRequestReviewThreadCommentSurface(
                        id: comment.id,
                        databaseID: comment.databaseId,
                        author: comment.author?.login,
                        body: comment.body
                    )
                },
                selector: selector
            )
        }
    }
}

private struct PullRequestReviewThreadsResponse: Decodable {
    struct Payload: Decodable {
        let repository: Repository?
    }

    struct Repository: Decodable {
        let pullRequest: PullRequest?
    }

    struct PullRequest: Decodable {
        let reviewThreads: ReviewThreads
    }

    struct ReviewThreads: Decodable {
        let nodes: [PullRequestReviewThreadNode]
    }

    let data: Payload?
}

private struct PullRequestReviewThreadNode: Decodable {
    struct Comments: Decodable {
        let nodes: [Comment]
    }

    struct Comment: Decodable {
        struct Author: Decodable {
            let login: String
        }

        let id: String
        let databaseId: Int?
        let body: String
        let author: Author?
    }

    let id: String
    let isResolved: Bool
    let isOutdated: Bool
    let path: String?
    let line: Int?
    let startLine: Int?
    let comments: Comments
}
