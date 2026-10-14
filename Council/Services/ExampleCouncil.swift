import CouncilKit
import Foundation

/// The example council: one real, recorded session that ships inside the app (Resources/
/// ExampleCouncil.json, produced by scripts/make-example-council.py), so a new user can see a whole
/// council (answers, blind review, divergence, dissent) before adding a single key.
///
/// It is opened read-only (`CouncilStore.openReadOnly`): nothing runs against it, nothing about it is
/// saved, and it never joins the history. The session file doesn't record which models answered or
/// who synthesized, so the wrapper carries that, and the UI shows it instead of today's settings.
struct ExampleCouncil: Decodable {
    /// One seat as it was set up when the example was recorded.
    struct RecordedSeat: Decodable {
        let seatID: Int
        /// Panel name, e.g. "Claude".
        let provider: String
        /// Model id, e.g. "claude-sonnet-4-6". Empty when unknown.
        let model: String
        /// Whether the seat used Council's default persona. nil = not checked when it was produced.
        let defaultPersona: Bool?

        enum CodingKeys: String, CodingKey { case seatID, provider, model, defaultPersona }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            seatID = try c.decode(Int.self, forKey: .seatID)
            provider = try c.decode(String.self, forKey: .provider)
            model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
            defaultPersona = try c.decodeIfPresent(Bool.self, forKey: .defaultPersona)
        }
    }

    static let schemaID = "council.example.v1"
    static let resourceName = "ExampleCouncil"

    let schema: String
    let recordedAt: Date
    /// The Council version the session was recorded with.
    let appVersion: String?
    let seats: [RecordedSeat]
    /// Who wrote the divergence and synthesis (the "via" name).
    let synthesizer: String?
    /// The neutral chair, if one was seated.
    let chair: String?
    let session: Session

    enum CodingKeys: String, CodingKey { case schema, recordedAt, appVersion, seats, synthesizer, chair, session }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(String.self, forKey: .schema)
        guard schema == Self.schemaID else {
            throw DecodingError.dataCorruptedError(forKey: .schema, in: c,
                                                   debugDescription: "Unknown example schema \(schema)")
        }
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        seats = try c.decodeIfPresent([RecordedSeat].self, forKey: .seats) ?? []
        synthesizer = try c.decodeIfPresent(String.self, forKey: .synthesizer)
        chair = try c.decodeIfPresent(String.self, forKey: .chair)
        session = try c.decode(Session.self, forKey: .session)
    }

    /// The bundled example, read once. nil hides every entry point.
    static let bundled: ExampleCouncil? = load()

    /// Reads ExampleCouncil.json from the bundle. nil when the file is missing, doesn't decode, or
    /// holds no round to show.
    static func load(from bundle: Bundle = .main) -> ExampleCouncil? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// Same decoding as session files: ISO 8601 dates, Int-keyed dictionaries as JSON objects.
    static func decode(_ data: Data) -> ExampleCouncil? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let example = try? decoder.decode(ExampleCouncil.self, from: data),
              !example.session.rounds.isEmpty else { return nil }
        return example
    }

    func seat(_ seatID: Int) -> RecordedSeat? { seats.first { $0.seatID == seatID } }

    /// "Recorded 14 Oct 2026 with Claude (claude-sonnet-4-6), GPT (gpt-5.4-mini), Ollama (llama3.2)"
    var label: String {
        let parts = seats.sorted { $0.seatID < $1.seatID }.map { s -> String in
            var detail = s.model
            if s.defaultPersona == false { detail += detail.isEmpty ? "custom persona" : ", custom persona" }
            return detail.isEmpty ? s.provider : "\(s.provider) (\(detail))"
        }
        let day = "Recorded \(Self.dayFormatter.string(from: recordedAt))"
        return parts.isEmpty ? day : "\(day) with \(parts.joined(separator: ", "))"
    }

    /// Fixed English day format, in UTC so the date reads the same everywhere.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}
