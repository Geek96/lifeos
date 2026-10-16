import Foundation

/// Claude Code 的 claude-cli:// 链接：在指定目录开新终端会话，指令预填但不自动发送。
/// 规范见 https://code.claude.com/docs/en/deep-links
public enum AgentDeepLink {
    /// 官方上限：q 最多 5000 个字符。
    public static let promptLimit = 5000

    /// 只放行 RFC 3986 的非保留 ASCII 字符；& = + 、中文、竖线、换行全部编码。
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func claudeCode(cwd: URL, prompt: String) -> URL? {
        var text = prompt
        if text.count > promptLimit { text = String(text.prefix(promptLimit - 1)) + "…" }
        var parts = ["cwd=" + encode(cwd.standardizedFileURL.path)]
        if !text.isEmpty { parts.append("q=" + encode(text)) }
        return URL(string: "claude-cli://open?" + parts.joined(separator: "&"))
    }

    /// Claude 桌面版 Code 标签页：新会话页，选中目录并预填指令（不自动发送）。
    /// 注意：folder 参数取自 Claude 桌面版的实现，官方文档只写了 SSH 参数，以后可能变化。
    public static func claudeDesktop(folder: URL, prompt: String) -> URL? {
        var text = prompt
        if text.count > promptLimit { text = String(text.prefix(promptLimit - 1)) + "…" }
        var parts = ["folder=" + encode(folder.standardizedFileURL.path)]
        if !text.isEmpty { parts.append("q=" + encode(text)) }
        return URL(string: "claude://code/new?" + parts.joined(separator: "&"))
    }

    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
