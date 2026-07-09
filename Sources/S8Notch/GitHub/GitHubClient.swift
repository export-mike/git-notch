import Foundation

enum GitHubError: LocalizedError {
    case ghNotFound
    case tokenUnavailable(String)
    case http(Int, String)
    case graphql(String)

    var errorDescription: String? {
        switch self {
        case .ghNotFound:
            return "GitHub CLI (gh) not found. Install it and run `gh auth login`."
        case .tokenUnavailable(let detail):
            return "Couldn't read gh token. Run `gh auth login`. (\(detail))"
        case .http(let code, _):
            return "GitHub API error (HTTP \(code))."
        case .graphql(let msg):
            return "GitHub error: \(msg)"
        }
    }
}

/// Talks to GitHub using the token from the already-authenticated `gh` CLI.
enum GitHubClient {

    struct FetchResult {
        let viewerLogin: String
        let reviewRequested: [PullRequest]   // PRs awaiting *my* review
        let mine: [PullRequest]              // *my* open PRs (unfiltered)
        let rateCost: Int                    // points this query cost
        let rateRemaining: Int               // points left this hour
        let rateResetAt: Date?               // when the hourly window resets
    }

    // MARK: - Token

    /// Token source, in priority order:
    ///  1. `GIT_NOTCH_GH_TOKEN` env var (great for terminal/launchd launches).
    ///  2. A token file — `GIT_NOTCH_GH_TOKEN_FILE` or `~/.config/s8-notch/token`
    ///     (survives Finder/login-item launches, which don't inherit shell env).
    ///  3. The already-authenticated `gh` CLI (`gh auth token`).
    static func token() async throws -> String {
        if let override = ProcessInfo.processInfo.environment["GIT_NOTCH_GH_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            NSLog("[s8notch] using token from GIT_NOTCH_GH_TOKEN")
            return override
        }
        if let fileToken = tokenFromFile() {
            return fileToken
        }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do { cont.resume(returning: try readTokenSync()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    /// Reads a token from `GIT_NOTCH_GH_TOKEN_FILE` or `~/.config/s8-notch/token`.
    private static func tokenFromFile() -> String? {
        let env = ProcessInfo.processInfo.environment
        let path: String
        if let custom = env["GIT_NOTCH_GH_TOKEN_FILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            path = (custom as NSString).expandingTildeInPath
        } else {
            path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/s8-notch/token").path
        }
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let token = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        NSLog("[s8notch] using token from file %@", path)
        return token
    }

    private static func readTokenSync() throws -> String {
        guard let gh = locateGh() else { throw GitHubError.ghNotFound }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: gh)
        proc.arguments = ["auth", "token"]
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        // Ensure Homebrew's gh can find its config regardless of launch env.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        proc.environment = env
        try proc.run()
        proc.waitUntilExit()
        let token = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if proc.terminationStatus != 0 || token.isEmpty {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw GitHubError.tokenUnavailable(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return token
    }

    private static func locateGh() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    // MARK: - Fetch

    static func fetch(token: String, org: String, commenter: String) async throws -> FetchResult {
        let orgQ = org.trimmingCharacters(in: .whitespaces)
        let scope = orgQ.isEmpty ? "" : " org:\(orgQ)"
        let commenterQ = commenter.trimmingCharacters(in: .whitespaces)
        let commenterClause = commenterQ.isEmpty ? "" : " commenter:\(commenterQ)"

        // Ignore Dependabot's PRs — they don't need a human "review" nudge.
        let rrQuery = "is:open is:pr review-requested:@me\(scope) archived:false draft:false -author:app/dependabot"
        // Note: no draft filter here — drafts are fetched too so the UI can
        // offer an Open/Draft toggle. isDraft is used to split them client-side.
        let mineQuery = "is:open is:pr author:@me\(scope)\(commenterClause) archived:false"

        let payload: [String: Any] = [
            "query": Self.query,
            "variables": [
                "rr": rrQuery,
                "mine": mineQuery
            ]
        ]

        var req = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        req.httpMethod = "POST"
        req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("s8-notch", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GitHubError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(GQLResponse.self, from: data)
        if let errors = decoded.errors, !errors.isEmpty {
            throw GitHubError.graphql(errors.map(\.message).joined(separator: "; "))
        }
        guard let d = decoded.data else { throw GitHubError.graphql("empty response") }

        return FetchResult(
            viewerLogin: d.viewer.login,
            reviewRequested: d.reviewRequested.nodes.compactMap { $0.toPullRequest() },
            mine: d.myPRs.nodes.compactMap { $0.toPullRequest() },
            rateCost: d.rateLimit?.cost ?? 0,
            rateRemaining: d.rateLimit?.remaining ?? 0,
            rateResetAt: (d.rateLimit?.resetAt).flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }

    // RATE-LIMIT RULE: GitHub GraphQL allows 5,000 points/hour. Query cost ≈ the
    // total nodes that *could* be returned (roughly sum of nested first:/last:
    // products ÷ 100). Keep every `first:` as small as realistically needed and
    // only request fields a side actually uses, so a full hour of polling stays
    // well under budget. Two lean fragments below: the left (review) list only
    // needs labels + approvals; the right (mine) list needs review/CI/merge state.
    // See also: the `rateLimit` block, which the app logs and backs off on.
    private static let query = """
    query($rr: String!, $mine: String!) {
      rateLimit { cost remaining limit resetAt }
      viewer { login }
      reviewRequested: search(query: $rr, type: ISSUE, first: 40) {
        issueCount
        nodes { ...reviewFields }
      }
      myPRs: search(query: $mine, type: ISSUE, first: 40) {
        issueCount
        nodes { ...mineFields }
      }
    }
    fragment reviewFields on PullRequest {
      title
      url
      number
      updatedAt
      repository { nameWithOwner }
      author { login }
      labels(first: 10) { nodes { name } }
      latestReviews(first: 10) { nodes { state } }
    }
    fragment mineFields on PullRequest {
      title
      url
      number
      updatedAt
      isDraft
      reviewDecision
      mergeable
      repository { nameWithOwner }
      author { login }
      reviews { totalCount }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      reviewThreads(first: 20) { nodes { isResolved isOutdated } }
    }
    """
}

// MARK: - GraphQL decoding

private struct GQLResponse: Decodable {
    let data: GQLData?
    let errors: [GQLError]?
}
private struct GQLError: Decodable { let message: String }

private struct GQLData: Decodable {
    let viewer: Viewer
    let reviewRequested: SearchResult
    let myPRs: SearchResult
    let rateLimit: RateLimit?
}
private struct RateLimit: Decodable {
    let cost: Int
    let remaining: Int
    let limit: Int
    let resetAt: String
}
private struct Viewer: Decodable { let login: String }
private struct SearchResult: Decodable { let issueCount: Int; let nodes: [PRNode] }

private struct PRNode: Decodable {
    let title: String?
    let url: String?
    let number: Int?
    let updatedAt: String?
    let isDraft: Bool?
    let reviewDecision: String?
    let mergeable: String?
    let repository: Repo?
    let author: Author?
    let labels: Labels?
    let reviews: Count?

    struct Labels: Decodable {
        let nodes: [Label]
        struct Label: Decodable { let name: String }
    }
    let latestReviews: Reviews?
    let commits: Commits?
    let reviewThreads: Threads?

    struct Repo: Decodable { let nameWithOwner: String }
    struct Author: Decodable { let login: String? }
    struct Count: Decodable { let totalCount: Int }
    struct Reviews: Decodable {
        let nodes: [Review]
        struct Review: Decodable { let state: String? }
    }
    struct Commits: Decodable {
        let nodes: [CommitNode]
        struct CommitNode: Decodable { let commit: Commit }
        struct Commit: Decodable { let statusCheckRollup: Rollup? }
        struct Rollup: Decodable { let state: String? }
    }
    struct Threads: Decodable {
        let nodes: [Thread]
        struct Thread: Decodable { let isResolved: Bool; let isOutdated: Bool }
    }

    func toPullRequest() -> PullRequest? {
        guard let title, let urlStr = url, let url = URL(string: urlStr),
              let number, let updatedAt, let iso = PRNode.iso.date(from: updatedAt),
              let repository else { return nil }

        let checkState = commits?.nodes.first?.commit.statusCheckRollup?.state
        let unresolved = reviewThreads?.nodes.filter { !$0.isResolved && !$0.isOutdated }.count ?? 0
        let approvals = latestReviews?.nodes.filter { $0.state == "APPROVED" }.count ?? 0

        return PullRequest(
            id: urlStr,
            title: title,
            url: url,
            number: number,
            repo: repository.nameWithOwner,
            author: author?.login ?? "",
            updatedAt: iso,
            isDraft: isDraft ?? false,
            labels: labels?.nodes.map(\.name) ?? [],
            reviewDecision: reviewDecision,
            reviewCount: reviews?.totalCount ?? 0,
            checkState: checkState,
            unresolvedCount: unresolved,
            approvalCount: approvals,
            mergeable: mergeable
        )
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
