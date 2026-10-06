import Foundation

public struct ResumeRequest: Codable, Equatable, Sendable {
    public let provider: AgentProvider
    public let conversation: String
    public let directory: String
    public init?(provider: AgentProvider, conversation: String, directory: String) {
        guard UUID(uuidString: conversation) != nil, directory.hasPrefix("/"),
              !directory.contains("\0"), !directory.contains("\n"), !directory.contains("\r") else { return nil }
        self.provider = provider; self.conversation = conversation.lowercased(); self.directory = directory
    }
}
public struct ReportCommand: Identifiable, Equatable, Sendable {
    public let id: Int
    public let literal: String
    public let resume: ResumeRequest?
}
/// One `##` section of a work file. Sessions keep the file order, newest first.
public struct WorkEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: String?
    public let sessions: [ResumeRequest]
}
public struct ReportDocument: Sendable {
    public let markdown: String
    public let commands: [ReportCommand]
    public let entries: [WorkEntry]
    public init(markdown: String) {
        self.markdown = markdown
        let lines = markdown.components(separatedBy: .newlines)
        commands = lines.enumerated().compactMap { index, line in
            var literal = line.trimmingCharacters(in: .whitespaces)
            if literal.hasPrefix("`"), literal.hasSuffix("`") { literal = String(literal.dropFirst().dropLast()) }
            guard literal.hasPrefix("cd ") else { return nil }
            return ReportCommand(id: index, literal: literal, resume: Self.parse(literal))
        }
        entries = Self.entries(lines, commands: commands)
    }
    public var readableMarkdown: AttributedString {
        guard let parsed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) else { return AttributedString(markdown) }
        var output = AttributedString()
        var previousBlock: Int?
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            if block != previousBlock {
                if !output.characters.isEmpty { output.append(AttributedString("\n")) }
                let items = components.compactMap { component -> Int? in
                    if case .listItem(let ordinal) = component.kind { return ordinal }
                    return nil
                }
                if let ordinal = items.first {
                    let ordered = components.dropFirst().first { component in
                        switch component.kind { case .orderedList, .unorderedList: return true; default: return false }
                    }.map { component in if case .orderedList = component.kind { return true }; return false } ?? false
                    output.append(AttributedString(String(repeating: "  ", count: max(0, items.count - 1)) + (ordered ? "\(ordinal). " : "• ")))
                }
                previousBlock = block
            }
            output.append(AttributedString(parsed[run.range]))
        }
        return output
    }
    /// IDs come from the title, not the heading date, which changes on every update.
    private static func entries(_ lines: [String], commands: [ReportCommand]) -> [WorkEntry] {
        let headings = lines.indices.filter { lines[$0].hasPrefix("## ") }
        var seen: [String: Int] = [:]
        return headings.enumerated().map { position, start in
            let body = start + 1 ..< (position + 1 < headings.count ? headings[position + 1] : lines.count)
            let heading = lines[start].dropFirst(3).trimmingCharacters(in: .whitespaces)
            let dated = heading.replacingOccurrences(of: #"^\d{4}-\d{2}-\d{2}(\s+\d{1,2}:\d{2})?\s+[—–-]\s+"#, with: "", options: .regularExpression)
            let title = dated.isEmpty ? heading : dated
            let status = lines[body].lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.hasPrefix("- Status:") }
                .map { $0.dropFirst("- Status:".count).trimmingCharacters(in: .whitespaces) }
            let count = (seen[title] ?? 0) + 1
            seen[title] = count
            return WorkEntry(id: "work:" + title + (count > 1 ? "#\(count)" : ""), title: title,
                             status: status?.isEmpty == false ? status : nil,
                             sessions: commands.filter { body.contains($0.id) }.compactMap(\.resume))
        }
    }
    private static func parse(_ literal: String) -> ResumeRequest? {
        guard let words = tokenize(literal), words.count == 6, words[0] == "cd", words[2] == "&&" else { return nil }
        let provider: AgentProvider
        if words[3] == "codex", words[4] == "resume" { provider = .codex }
        else if words[3] == "claude", words[4] == "-r" || words[4] == "--resume" { provider = .claude }
        else if words[3] == "agent" || words[3] == "cursor-agent", words[4] == "--resume" { provider = .cursor }
        else { return nil }
        return ResumeRequest(provider: provider, conversation: words[5], directory: words[1])
    }
    private static func tokenize(_ text: String) -> [String]? {
        var words: [String] = [], current = "", quote: Character?, escaped = false, started = false
        let characters = Array(text)
        var i = 0
        while i < characters.count {
            let c = characters[i]
            if escaped { current.append(c); escaped = false; started = true }
            else if let q = quote {
                if c == q { quote = nil }
                else if q == "\"", c == "$" || c == "`" || c == "\\" { return nil }
                else { current.append(c) }
            } else if c == "'" || c == "\"" { quote = c; started = true }
            else if c == "\\" { escaped = true; started = true }
            else if c == "&", i + 1 < characters.count, characters[i + 1] == "&" {
                if started { words.append(current); current = ""; started = false }
                words.append("&&"); i += 1
            } else if c.isWhitespace {
                if started { words.append(current); current = ""; started = false }
            } else if ";|&$`<>()\0".contains(c) { return nil }
            else { current.append(c); started = true }
            i += 1
        }
        guard quote == nil, !escaped else { return nil }
        if started { words.append(current) }
        return words
    }
}

public enum ResumeDecision: Equatable, Sendable { case select(String), choose([String]), create(ResumeRequest) }
public enum ResumeConfirmation: Equatable, Sendable { case waiting, confirmed(String), choose([String]) }
public extension AgentRegistry {
    func resumeDecision(_ request: ResumeRequest) -> ResumeDecision {
        let matches = matchingResume(request)
        if matches.count == 1 { return .select(matches[0].id) }
        if matches.count > 1 { return .choose(matches.map(\.id)) }
        return .create(request)
    }
    func resumeConfirmation(_ request: ResumeRequest, createdTerminalID: String?) -> ResumeConfirmation {
        let matches = matchingResume(request).filter { createdTerminalID == nil || $0.terminal.id == createdTerminalID }
        if matches.count == 1 { return .confirmed(matches[0].id) }
        if matches.count > 1 { return .choose(matches.map(\.id)) }
        return .waiting
    }
    private func matchingResume(_ request: ResumeRequest) -> [AgentSession] {
        sessions.filter { $0.observedAt != nil && $0.provider == request.provider && $0.conversation?.lowercased() == request.conversation }
    }
}
