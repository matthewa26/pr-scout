import Foundation
import ArgumentParser

enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case json, table, list, pretty
}

enum Renderer {
    static func render(_ classified: [ClassifiedPR], format: OutputFormat, viewer: String, profileName: String?) -> String {
        let resolved: OutputFormat
        if format == .pretty, !ANSI.stdoutIsTTY {
            // Pretty implies ANSI; fall back to list when piped.
            resolved = .list
        } else {
            resolved = format
        }
        switch resolved {
        case .json: return renderJSON(classified)
        case .list: return renderList(classified, viewer: viewer, profileName: profileName, color: false)
        case .pretty: return renderList(classified, viewer: viewer, profileName: profileName, color: true)
        case .table: return renderTable(classified)
        }
    }

    // MARK: - JSON

    private static func renderJSON(_ classified: [ClassifiedPR]) -> String {
        struct Output: Encodable {
            let category: String
            let categoryDisplay: String
            let repo: String
            let number: Int
            let title: String
            let author: String
            let url: String
            let createdAt: Date
            let updatedAt: Date
            let reason: String
        }
        let payload = classified.map {
            Output(
                category: $0.category.rawValue,
                categoryDisplay: $0.category.displayName,
                repo: $0.repo.slug,
                number: $0.detail.number,
                title: $0.detail.title,
                author: $0.detail.author.login,
                url: $0.detail.url,
                createdAt: $0.detail.createdAt,
                updatedAt: $0.detail.updatedAt,
                reason: $0.reason
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - Table

    private static func renderTable(_ classified: [ClassifiedPR]) -> String {
        if classified.isEmpty { return "No matching PRs.\n" }
        let now = Date()

        struct Row {
            let category: String
            let repo: String
            let number: String
            let author: String
            let age: String
            let title: String
            let url: String
        }
        let rows: [Row] = classified.map {
            Row(
                category: $0.category.rawValue,
                repo: $0.repo.slug,
                number: "#\($0.detail.number)",
                author: $0.detail.author.login,
                age: ageString(from: $0.detail.updatedAt, now: now),
                title: truncate($0.detail.title, max: 60),
                url: $0.detail.url
            )
        }
        let headers = ["CATEGORY", "REPO", "PR", "AUTHOR", "UPDATED", "TITLE", "URL"]
        let cols: [[String]] = [
            [headers[0]] + rows.map(\.category),
            [headers[1]] + rows.map(\.repo),
            [headers[2]] + rows.map(\.number),
            [headers[3]] + rows.map(\.author),
            [headers[4]] + rows.map(\.age),
            [headers[5]] + rows.map(\.title),
            [headers[6]] + rows.map(\.url),
        ]
        let widths = cols.map { col in col.map(\.count).max() ?? 0 }
        var out = ""
        for r in 0...rows.count {
            var pieces: [String] = []
            for (i, col) in cols.enumerated() {
                pieces.append(col[r].padding(toLength: widths[i], withPad: " ", startingAt: 0))
            }
            out += pieces.joined(separator: "  ") + "\n"
            if r == 0 {
                out += widths.map { String(repeating: "-", count: $0) }.joined(separator: "  ") + "\n"
            }
        }
        return out
    }

    // MARK: - List / Pretty

    private static func renderList(_ classified: [ClassifiedPR], viewer: String, profileName: String?, color: Bool) -> String {
        if classified.isEmpty {
            let header = headerLine(viewer: viewer, profileName: profileName, count: 0, color: color)
            return header + "\nNo matching PRs.\n"
        }

        let groups = Dictionary(grouping: classified, by: \.category)
        let now = Date()

        var out = headerLine(viewer: viewer, profileName: profileName, count: classified.count, color: color) + "\n\n"

        for kind in CategoryKind.allCases {
            guard let items = groups[kind], !items.isEmpty else { continue }
            let title = "\(kind.displayName) (\(items.count))"
            out += ANSI.color(title, ANSI.bold + ANSI.cyan, enabled: color) + "\n"
            for item in items {
                let pr = item.detail
                let bullet = ANSI.color("  •", ANSI.gray, enabled: color)
                let slug = ANSI.color("\(item.repo.slug)#\(pr.number)", ANSI.bold, enabled: color)
                let title = pr.title
                let updated = ageString(from: pr.updatedAt, now: now)
                let author = ANSI.color("@\(pr.author.login)", ANSI.magenta, enabled: color)
                let reason = ANSI.color(item.reason, ANSI.yellow, enabled: color)
                let url = ANSI.color(pr.url, ANSI.dim, enabled: color)
                out += "\(bullet) \(slug) — \(title)\n"
                out += "      \(author) · updated \(updated) · \(reason)\n"
                out += "      \(url)\n"
            }
            out += "\n"
        }
        return out
    }

    private static func headerLine(viewer: String, profileName: String?, count: Int, color: Bool) -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        let prof = profileName.map { " · profile: \($0)" } ?? ""
        let line = "pr-scout · viewer: @\(viewer)\(prof) · matches: \(count) · \(now)"
        return ANSI.color(line, ANSI.dim, enabled: color)
    }

    // MARK: - Helpers

    private static func ageString(from date: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        let days = s / 86_400
        if days < 30 { return "\(days)d ago" }
        return "\(days / 30)mo ago"
    }

    private static func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max - 1)) + "…"
    }
}
