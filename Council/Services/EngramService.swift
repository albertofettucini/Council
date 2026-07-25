import Foundation
import AppKit
import Observation
import Engram

/// Bridge to the user's local Engram store (the same maker's shared-AI-memory app): journal
/// decisions can be written into Engram so the user's OTHER AI tools recall them via MCP.
///
/// Ground rules, in order of load-bearing-ness:
/// - SANDBOX-CORRECT: Council is sandboxed, so it cannot just write into Engram's Application
///   Support folder (a naive path write would land in Council's own container and silently create
///   a divergent store). The user picks the Engram folder ONCE; an app-scoped security bookmark
///   keeps the grant. Never write outside that grant.
/// - DETECTION-GATED: nothing Engram-related appears in the UI unless Engram is actually installed
///   (or a grant already exists). This is an integration, not an in-app ad.
/// - WRITES ONLY JOURNAL TEXT: the memory is composed by the engine from journal fields + the
///   round's public verdict — never transcripts, attachments, or keys. Zero network.
@MainActor
@Observable
final class EngramService {
    static let bookmarkKey = "council.engram.bookmark"

    /// The user has a live grant (bookmark saved). Distinct from `detected`.
    private(set) var connected: Bool

    init() {
        connected = UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    }

    /// Engram present on this Mac? App-bundle lookup only — the sandbox can't probe brew paths,
    /// and an existing grant counts regardless.
    var detected: Bool {
        connected || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.engram.Engram") != nil
    }

    /// One-time grant: the user picks their Engram folder. Returns an error message, or nil on
    /// success AND on plain cancel (cancel is not an error).
    func connect() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Connect"
        panel.message = "Select your Engram folder — ~/Library/Application Support/Engram"
        // The REAL home, not the sandbox container: `.applicationSupportDirectory` resolves inside
        // Council's own container, which is precisely where Engram is not.
        panel.directoryURL = Self.realHome?
            .appendingPathComponent("Library/Application Support/Engram", isDirectory: true)
        guard panel.runModal() == .OK, let picked = panel.url else { return nil }
        guard Self.memoriesRoot(from: picked) != nil else {
            return "That doesn't look like an Engram folder — pick “Engram” itself (or its “memories” folder)."
        }
        do {
            let bookmark = try picked.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            connected = true
            return nil
        } catch {
            return "Couldn't keep access to that folder: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        connected = false
    }

    /// Append one memory to the user's Engram store. Returns the new memory's id (kept on the
    /// session so a later outcome can supersede it). Throws with a user-readable message.
    func remember(text: String, supersedes: UUID?) throws -> UUID {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            throw EngramError.notConnected
        }
        var stale = false
        guard let picked = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                    relativeTo: nil, bookmarkDataIsStale: &stale),
              picked.startAccessingSecurityScopedResource() else {
            throw EngramError.staleGrant
        }
        defer { picked.stopAccessingSecurityScopedResource() }
        guard let root = Self.memoriesRoot(from: picked) else { throw EngramError.staleGrant }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = try MarkdownStore(root: root)
            // One dedicated conversation file: keeps Engram's dashboard tidy and keeps engram-mcp /
            // capture rewrites away from the file Council appends to.
            let memory = Memory(content: text,
                                tags: ["council", "decision"],
                                source: "council",
                                conversationID: "council-decisions",
                                supersedes: supersedes)
            try store.append(memory)
            // `supersedes` is metadata Engram doesn't act on yet, so an update would otherwise leave
            // the OLD version live and recallable — tombstone it ourselves. Soft delete keeps it on
            // disk (auditable), just out of recall.
            if let old = supersedes { try? store.softDelete(old) }
            return memory.id
        } catch {
            throw EngramError.writeFailed(error.localizedDescription)
        }
    }

    enum EngramError: LocalizedError {
        case notConnected
        case staleGrant
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .notConnected: return "Engram isn't connected — connect it in Settings → App."
            case .staleGrant:   return "Council lost access to your Engram folder — in Settings → App, hit Disconnect, then Connect Engram again."
            case .writeFailed(let m): return "Couldn't write to Engram: \(m)"
            }
        }
    }

    /// The user's actual home directory. Inside the sandbox `NSHomeDirectory()` is the container,
    /// so ask the password database instead — used only to point the open panel somewhere useful.
    private static var realHome: URL? {
        guard let pw = getpwuid(getuid()) else { return nil }
        return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir), isDirectory: true)
    }

    /// Accept the Engram root or its memories dir; refuse anything else so a mis-pick (e.g. the
    /// whole home folder) can't scatter .md files into a random directory.
    private static func memoriesRoot(from picked: URL) -> URL? {
        if picked.lastPathComponent == "memories" { return picked }
        let sub = picked.appendingPathComponent("memories", isDirectory: true)
        if FileManager.default.fileExists(atPath: sub.path) { return sub }
        // A fresh Engram install may not have written memories yet — accept the root by name.
        if picked.lastPathComponent == "Engram" { return sub }
        return nil
    }
}
