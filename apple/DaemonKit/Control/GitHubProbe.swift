import Foundation

public struct PullRequestInfo: Codable, Sendable, Hashable, Identifiable {
    public let number: Int
    public let title: String
    public let state: String
    public let headRefName: String
    public let isDraft: Bool?
    public let updatedAt: Date?
    public let url: String
    public var id: Int { number }
}

public struct WorkflowRunInfo: Codable, Sendable, Hashable, Identifiable {
    public let databaseId: Int
    public let name: String?
    public let status: String
    public let conclusion: String?
    public let headBranch: String?
    public let createdAt: Date?
    public var id: Int { databaseId }
}

public struct IssueInfo: Codable, Sendable, Hashable, Identifiable {
    public let number: Int
    public let title: String
    public let state: String
    public var id: Int { number }
}

public struct GitHubSnapshot: Codable, Sendable {
    public let slug: String
    public let pullRequests: [PullRequestInfo]
    public let issues: [IssueInfo]
    public let runs: [WorkflowRunInfo]
    public let evidence: Evidence
    public let error: String?
    public let provenance: Provenance

    public var openPullRequests: [PullRequestInfo] { pullRequests.filter { $0.state == "OPEN" } }
}

public enum GitHubParser {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    public static func pullRequests(_ data: Data) -> [PullRequestInfo]? { try? decoder.decode([PullRequestInfo].self, from: data) }
    public static func runs(_ data: Data) -> [WorkflowRunInfo]? { try? decoder.decode([WorkflowRunInfo].self, from: data) }
    public static func issues(_ data: Data) -> [IssueInfo]? { try? decoder.decode([IssueInfo].self, from: data) }
}

#if os(macOS)
public enum GitHubProbe {
    public static func observe(slug: String) async -> GitHubSnapshot {
        let started = Date()
        async let prs = try? CommandRunner.run("gh", ["pr", "list", "-R", slug, "--state", "all", "--limit", "15",
                                                      "--json", "number,title,state,headRefName,isDraft,updatedAt,url"], timeout: 12)
        async let issues = try? CommandRunner.run("gh", ["issue", "list", "-R", slug, "--state", "open", "--limit", "15", "--json", "number,title,state"], timeout: 12)
        async let runs = try? CommandRunner.run("gh", ["run", "list", "-R", slug, "--limit", "8",
                                                       "--json", "databaseId,name,status,conclusion,headBranch,createdAt"], timeout: 12)
        let prResult = await prs, issueResult = await issues, runResult = await runs
        let pullRequests = prResult.flatMap { $0.succeeded ? GitHubParser.pullRequests(Data($0.standardOutput.utf8)) : nil }
        let error: String?
        if Toolbox.locate("gh") == nil { error = "gh no está instalado" }
        else if pullRequests == nil { error = prResult.map { CoreBridge.redact(String($0.standardError.prefix(240))) } ?? "gh no respondió" }
        else { error = nil }
        let snapshot = GitHubSnapshot(
            slug: slug,
            pullRequests: pullRequests ?? [],
            issues: issueResult.flatMap { $0.succeeded ? GitHubParser.issues(Data($0.standardOutput.utf8)) : nil } ?? [],
            runs: runResult.flatMap { $0.succeeded ? GitHubParser.runs(Data($0.standardOutput.utf8)) : nil } ?? [],
            evidence: pullRequests == nil ? .unverified : .verified,
            error: error,
            provenance: Provenance(source: "GitHub API vía gh", method: "gh pr/issue/run list -R \(slug)", observedAt: started))
        DaemonStore.write(snapshot, to: "snapshots/github-\(slug.replacingOccurrences(of: "/", with: "_")).json")
        return snapshot
    }
}
#endif
