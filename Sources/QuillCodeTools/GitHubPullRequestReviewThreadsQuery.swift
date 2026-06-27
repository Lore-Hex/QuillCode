public enum GitHubPullRequestReviewThreadsQuery {
    public static var graphql: String {
        let nonNull = "\u{21}"
        return "query($owner: String\(nonNull), $name: String\(nonNull), $number: Int\(nonNull)) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { reviewThreads(first: 50) { nodes { id isResolved isOutdated path line startLine comments(first: 10) { nodes { id databaseId body author { login } createdAt } } } } } } }"
    }
}
