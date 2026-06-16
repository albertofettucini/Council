import Foundation
import CouncilKit

// ─────────────────────────────────────────────────────────────────────────────
// council — the Council engine as a text-only power tool. Zero pixels.
// Exit codes: 0 ok · 1 --fail-above tripped · 2 runtime error · 64 usage error.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Output helpers (respect NO_COLOR + non-TTY)

enum Style {
    static let on = ProcessInfo.processInfo.environment["NO_COLOR"] == nil && isatty(1) != 0
    static func bold(_ s: String) -> String { on ? "\u{1B}[1m\(s)\u{1B}[0m" : s }
    static func dim(_ s: String) -> String { on ? "\u{1B}[2m\(s)\u{1B}[0m" : s }
}

func errPrint(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
func die(_ msg: String, code: Int32 = 2) -> Never { errPrint("error: \(msg)"); exit(code) }

// MARK: - Options

struct Options {
    var question = ""
    var configPath: String?
    var seatNames: [String] = []
    var json = false
    var md = false
    var mdOut: String?
    var quiet = false
    var verbose = false
    var failAbove: Int?
    var noSave = false
    var allowEnvKeys = false
    var filePath: String?
}

let usage = """
council — multi-LLM roundtable in your terminal (the Council app's engine)

USAGE
  council "question" [flags]            run the full pipeline
  council keys set <provider>           store an API key in the Keychain (hidden prompt)
  council "review this" --file doc.md   attach a document for every seat
  cat doc.md | council "review this"    same, from stdin

FLAGS
  --config <path.council>   use a saved lineup (schema council.v1)
  --file <path>             attach a text/markdown document (analyzed by every seat)
  --seats a,b,c             ad-hoc lineup with default personas
                            (claude gpt gemini deepseek grok mistral perplexity
                             openrouter ollama apple custom1 custom2)
  --json                    full structured result on stdout (schema council.cli.v1)
  --md [-o file.md]         decision memo (markdown) on stdout or to a file
  --quiet                   synthesis only
  -v                        include full peer reviews / rebuttals
  --fail-above <N>          exit 1 if displayed divergence > N (CI gating)
  --no-save                 don't write the session into the app's history
  --allow-env-keys          CI only: COUNCIL_KEY_<PROVIDER> env vars may supply keys

EXIT CODES   0 ok · 1 divergence gate tripped · 2 runtime error · 64 usage error

Keys are read from the macOS Keychain (shared with the Council app — macOS will ask
once to allow access). Sessions land in the app's history unless --no-save.

\(CouncilKit.attribution)
"""

func parseArgs(_ argv: [String]) -> Options {
    var o = Options()
    var args = argv
    var positionals: [String] = []
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--help", "-h": print(usage); exit(0)
        case "--version", "-V": print("council \(CouncilKit.version)\n\(CouncilKit.signature)"); exit(0)
        case "--config":     o.configPath = args.isEmpty ? nil : args.removeFirst()
        case "--file":       guard !args.isEmpty else { die("--file needs a path (see --help)", code: 64) }
                             o.filePath = args.removeFirst()
        case "--seats":      o.seatNames = (args.isEmpty ? "" : args.removeFirst())
                                 .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        case "--json":       o.json = true
        case "--md":         o.md = true
        case "-o":           o.mdOut = args.isEmpty ? nil : args.removeFirst()
        case "--quiet":      o.quiet = true
        case "-v", "--verbose": o.verbose = true
        case "--fail-above":
            guard !args.isEmpty, let n = Int(args.removeFirst()), (0...100).contains(n)
            else { die("--fail-above needs a number 0–100", code: 64) }
            o.failAbove = n
        case "--no-save":    o.noSave = true
        case "--allow-env-keys": o.allowEnvKeys = true
        default:
            if a.hasPrefix("-") { die("unknown flag \(a) (see --help)", code: 64) }
            positionals.append(a)
        }
    }
    o.question = positionals.joined(separator: " ")
    return o
}

// MARK: - Provider names

func provider(named raw: String) -> LLMProvider? {
    switch raw.lowercased() {
    case "claude":                 return .claude
    case "gpt", "openai":          return .openAI
    case "gemini":                 return .gemini
    case "deepseek":               return .deepSeek
    case "grok":                   return .grok
    case "mistral":                return .mistral
    case "perplexity", "sonar":    return .perplexity
    case "openrouter":             return .openRouter
    case "ollama":                 return .ollama
    case "apple", "foundationmodels", "on-device": return .foundationModels
    case "custom1":                return .custom1
    case "custom2":                return .custom2
    default:                       return nil
    }
}

// MARK: - keys set

@MainActor
func keysSet(_ name: String) {
    guard let p = provider(named: name) else { die("unknown provider '\(name)'", code: 64) }
    guard p.requiresAPIKey else { die("\(p.displayName) needs no API key") }
    guard let raw = getpass("API key for \(p.displayName): ") else { die("no input") }
    let key = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { die("empty key") }
    do { try KeychainStore.save(key, account: p.keychainAccount) }
    catch { die("Keychain save failed: \(error)") }
    print("saved to Keychain (account \(p.keychainAccount)) — shared with the Council app")
    exit(0)
}

// MARK: - Pipeline

@MainActor
func run(_ opts: Options) async {
    if opts.allowEnvKeys {
        KeychainStore.allowEnvOverride = true
        errPrint("warning: --allow-env-keys is on — COUNCIL_KEY_* env vars may supply API keys (CI mode)")
    }

    let store = CouncilStore()
    store.persistenceEnabled = !opts.noSave

    // "Verify against an existing session file before writing": if the sessions dir has files but
    // NONE decoded, our writer may not match the app's schema — don't risk corrupting history.
    if store.persistenceEnabled,
       let dir = CouncilStore.sessionsFolderURL,
       let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
       files.contains(where: { $0.pathExtension == "json" }), store.sessions.isEmpty {
        errPrint("warning: existing session files could not be decoded — running with --no-save to protect them")
        store.persistenceEnabled = false
    }
    store.newSession()

    // Lineup: --config > --seats > the CLI's own last lineup.
    if let path = opts.configPath {
        guard let data = FileManager.default.contents(atPath: (path as NSString).expandingTildeInPath),
              let config = try? JSONDecoder().decode(CouncilConfig.self, from: data)
        else { die("couldn't read council config at \(path)") }
        store.applyConfig(config)
    } else if !opts.seatNames.isEmpty {
        guard opts.seatNames.count <= store.seats.count else { die("at most \(store.seats.count) seats", code: 64) }
        for (i, seat) in store.seats.enumerated() {
            if i < opts.seatNames.count {
                guard let p = provider(named: opts.seatNames[i]) else { die("unknown provider '\(opts.seatNames[i])'", code: 64) }
                store.setProvider(p, seatID: seat.id)
            } else {
                store.clearProvider(seatID: seat.id)
            }
        }
    }

    let connected = store.seats.filter { store.hasKey($0) }
    guard !connected.isEmpty else {
        die("no seats configured — use --seats claude,gpt,gemini or --config lineup.council\n       (cloud providers also need: council keys set <provider>)", code: 64)
    }
    for seat in store.seats where seat.provider != nil && !store.hasKey(seat) {
        errPrint("warning: \(seat.provider!.displayName) has no API key (council keys set …) — seat skipped")
    }

    // Attached document: --file wins, else stdin when piped. Folded into every seat's prompt by
    // the engine — NOT appended to the question here, so the saved history stays clean. All --file
    // failure modes share the runtime exit code so a CI script sees one code for "bad input file".
    var document: String?
    if let path = opts.filePath {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            die("can't read --file \(path)")
        }
        let doc = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !doc.isEmpty else { die("--file \(path) is empty") }
        if let err = CouncilLimits.documentError(doc) { die(err) }
        document = doc
        errPrint(Style.dim("attached \(doc.count)-char document from \(path)"))
    } else if isatty(0) == 0 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        if let doc = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !doc.isEmpty {
            if let err = CouncilLimits.documentError(doc) { die(err) }
            document = doc
            errPrint(Style.dim("attached \(doc.count)-char document from stdin"))
        }
    }
    // A document alone is a valid run — the engine synthesizes "Analyze the attached document."
    let question = opts.question
    guard !question.isEmpty || document != nil else { die("no question given (see --help)", code: 64) }

    let payloadMode = opts.json || opts.md          // keep stdout clean for machine output
    func stage(_ s: String) { errPrint(Style.dim("· \(s)…")) }
    func emit(_ s: String)  { if !payloadMode && !opts.quiet { print(s) } }

    let started = ISO8601DateFormatter().string(from: Date())

    // 1 — answers
    stage("answers (\(connected.count) seats)")
    await store.ask(question, document: document)
    let round = { () -> Round? in store.rounds.indices.contains(store.viewingRound) ? store.rounds[store.viewingRound] : nil }
    guard let r0 = round(), !r0.answeredSeatIDs.isEmpty else {
        let errs = store.seats.compactMap { seat -> String? in
            if case .failed(let m) = store.status[seat.id] ?? .idle { return "\(seat.provider?.panelName ?? "seat"): \(m)" }
            return nil
        }
        die("no advisor answered" + (errs.isEmpty ? "" : "\n       " + errs.joined(separator: "\n       ")))
    }
    func name(_ seatID: Int) -> String {
        round()?.answerProviders[seatID] ?? store.seats.first { $0.id == seatID }?.provider?.panelName ?? "Advisor"
    }
    if !payloadMode && !opts.quiet {
        print(Style.bold("ANSWERS"))
        for seat in store.seats {
            guard let a = round()?.answers[seat.id], !a.isEmpty else {
                if case .failed(let m) = store.status[seat.id] ?? .idle { print("  \(name(seat.id)): ✗ \(m)") }
                continue
            }
            let flat = a.replacingOccurrences(of: "\n", with: " ")
            print("  \(Style.bold(name(seat.id))): \(flat.count > 220 ? String(flat.prefix(220)) + "…" : flat)")
        }
        print("")
    }

    let canDeliberate = (round()?.answeredSeatIDs.count ?? 0) >= 2

    // 2 — peer review
    if canDeliberate {
        stage("peer review")
        await store.peerReview()
        if !payloadMode && !opts.quiet {
            if opts.verbose {
                print(Style.bold("PEER REVIEW"))
                for seat in store.seats {
                    if let rv = store.viewedPeerReview(seat.id), !rv.isEmpty {
                        print("  \(Style.bold(name(seat.id))):\n\(rv)\n")
                    }
                }
            } else {
                print(Style.dim("PEER REVIEW done — rerun with -v for the full critiques.") + "\n")
            }
        }

        // 3 — divergence (+ judge verdict)
        stage("divergence")
        await store.runDivergence()
        if let agreement = store.agreementScore {
            let displayed = 100 - agreement
            var line = "DIVERGENCE: \(displayed)/100"
            if let c = store.divergenceCamps { line += " · \(c) camp\(c == 1 ? "" : "s")" }
            if let o = store.outlierName { line += " · outlier: \(o)" }
            emit(Style.bold(line))
            emit(Style.dim("  (measures agreement, not correctness)") + "\n")
        } else {
            emit(Style.dim("DIVERGENCE: verdict unavailable for this run") + "\n")
        }

        // 4 — synthesis
        stage("synthesis")
        await store.runSynthesis()
        if let s = store.synthesisText, !payloadMode {
            print(Style.bold("SYNTHESIS"))
            print(s + "\n")
        }

        // 5 — dissent
        if let outlier = store.outlierName, let answer = store.outlierAnswer, !payloadMode, !opts.quiet {
            print(Style.bold("DISSENT — \(outlier) stood apart"))
            let flat = answer.replacingOccurrences(of: "\n", with: " ")
            print("  " + (flat.count > 400 ? String(flat.prefix(400)) + "…" : flat) + "\n")
        }
        if opts.verbose, store.hasRebuttalForViewedRound, !payloadMode {
            print(Style.bold("REBUTTALS"))
            for seat in store.seats {
                if let rb = store.viewedRebuttal(seat.id) { print("  \(Style.bold(name(seat.id))):\n\(rb)\n") }
            }
        }
    } else {
        errPrint("note: only one advisor answered — peer review / divergence / synthesis need ≥2")
    }

    let finished = ISO8601DateFormatter().string(from: Date())

    // Machine outputs
    if opts.md {
        let memo = store.exportDecisionMemo()
        if let out = opts.mdOut {
            do { try memo.write(toFile: (out as NSString).expandingTildeInPath, atomically: true, encoding: .utf8) }
            catch { die("couldn't write \(out): \(error.localizedDescription)") }
            errPrint("wrote \(out)")
        } else {
            print(memo)
        }
    }
    if opts.json, let r = round() {
        var seatsArr: [[String: Any]] = []
        var answers: [String: String] = [:], reviews: [String: String] = [:], rebuttals: [String: String] = [:]
        for seat in store.seats {
            if let a = r.answers[seat.id], !a.isEmpty {
                seatsArr.append(["name": name(seat.id), "provider": seat.provider?.rawValue ?? "", "model": seat.model])
                answers[name(seat.id)] = a
            }
            if let rv = r.peerReviews[seat.id], !rv.isEmpty { reviews[name(seat.id)] = rv }
            if let rb = r.rebuttals[seat.id], !rb.isEmpty { rebuttals[name(seat.id)] = rb }
        }
        var obj: [String: Any] = [
            "schemaVersion": "council.cli.v1",
            // The round's question, not the raw arg: on the document-only path opts.question is empty
            // while the round ran with the engine-synthesized "Analyze the attached document."
            "question": r.question,
            "startedAt": started, "finishedAt": finished,
            "seats": seatsArr, "answers": answers,
            "peerReviews": reviews, "rebuttals": rebuttals,
        ]
        if let agreement = r.divergenceScore {
            var d: [String: Any] = ["agreement": agreement, "displayedDivergence": 100 - agreement]
            if let c = r.divergenceCamps { d["camps"] = c }
            if let o = r.outlier { d["outlier"] = o }
            if let n = r.divergence { d["narrative"] = n }
            obj["divergence"] = d
        }
        if let s = r.synthesis { obj["synthesis"] = s }
        if let o = r.outlier, let a = store.outlierAnswer { obj["dissent"] = ["name": o, "answer": a] }
        let data = try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
    if opts.quiet && !payloadMode, let s = store.synthesisText {
        print(s)
    }

    // CI gate — distinct from runtime errors: missing verdict is a runtime error (can't gate on it).
    if let gate = opts.failAbove {
        guard let agreement = store.agreementScore else { die("--fail-above set but no divergence verdict was produced") }
        let displayed = 100 - agreement
        if displayed > gate {
            errPrint("divergence \(displayed) exceeds gate \(gate) — failing")
            exit(1)
        }
        errPrint(Style.dim("divergence \(displayed) within gate \(gate)"))
    }
    exit(0)
}

// MARK: - Entry

@main
struct CouncilCLI {
    static func main() async {
        var argv = Array(CommandLine.arguments.dropFirst())
        if argv.first == "keys" {
            guard argv.count >= 3, argv[1] == "set" else { die("usage: council keys set <provider>", code: 64) }
            await MainActor.run { keysSet(argv[2]) }
            return
        }
        let opts = parseArgs(argv)
        await run(opts)
    }
}
