import XCTest
import Foundation
@testable import CouncilKit

/// Fast, deterministic unit tests for the CouncilKit facade — no network, and no writes to the
/// real Keychain or to the app's saved state. They lock in the public API shape, the error
/// contract, and the persistence isolation that the live run + adversarial review hardened.
///
/// Keys are supplied via `COUNCIL_KEY_*` env overrides (set in `setUp`) so the tests never prompt
/// for Keychain access; the values are dummies and no test makes a network call.
final class CouncilKitTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KeychainStore.allowEnvOverride = true
        setenv("COUNCIL_KEY_CLAUDE", "test-key", 1)
        setenv("COUNCIL_KEY_OPENAI", "test-key", 1)
    }

    override func tearDown() {
        unsetenv("COUNCIL_KEY_CLAUDE")
        unsetenv("COUNCIL_KEY_OPENAI")
        KeychainStore.allowEnvOverride = false
        super.tearDown()
    }

    // MARK: - Public API shape

    func testGptAliasMapsToOpenAI() {
        XCTAssertEqual(Backend.gpt, .openAI)
    }

    func testAdvisorDefaults() {
        let a = Advisor(backend: .claude)
        XCTAssertEqual(a.backend, .claude)
        guard case .analyst = a.persona else { return XCTFail("default persona should be .analyst") }
        XCTAssertNil(a.model)
    }

    @MainActor func testCustomPersonaPassesThrough() {
        XCTAssertEqual(Persona.custom("be terse").systemPrompt, "be terse")
    }

    @MainActor func testBuiltinPersonasAreDistinctAndNonEmpty() {
        let prompts = [Persona.analyst, .practitioner, .skeptic, .devilsAdvocate].map(\.systemPrompt)
        XCTAssertFalse(prompts.contains(where: \.isEmpty), "no built-in persona prompt should be empty")
        XCTAssertEqual(Set(prompts).count, prompts.count, "built-in personas should be distinct")
    }

    // MARK: - Error contract (guards fire before any store / network / Keychain access)

    @MainActor func testEmptyAdvisorsThrowsNoAdvisors() async {
        do {
            _ = try await Council(advisors: []).deliberate("anything")
            XCTFail("expected .noAdvisors")
        } catch CouncilError.noAdvisors {
            // expected
        } catch {
            XCTFail("expected .noAdvisors, got \(error)")
        }
    }

    @MainActor func testTooManyAdvisorsThrows() {
        let many = Array(repeating: Advisor(backend: .claude), count: 99)
        XCTAssertThrowsError(try Council.configuredStore(many)) { error in
            guard case CouncilError.tooManyAdvisors = error else {
                return XCTFail("expected .tooManyAdvisors, got \(error)")
            }
        }
    }

    // MARK: - Persistence isolation (regression guards for the P1 data-corruption fixes)

    @MainActor func testNonPersistingStoreDoesNotOverwriteSavedSeats() {
        let store = CouncilStore()
        store.persistenceEnabled = false
        let key = "council.seats.v7"                                   // CouncilStore.seatsKey (private)
        let before = UserDefaults.standard.data(forKey: key)
        if let sid = store.seats.first?.id { store.setProvider(.claude, seatID: sid) }  // → saveSeats()
        store.saveSeats()
        XCTAssertEqual(UserDefaults.standard.data(forKey: key), before,
                       "a non-persisting store must not overwrite the app's saved seat lineup")
    }

    @MainActor func testNonPersistingStoreDoesNotOverwriteRoleSeats() {
        let store = CouncilStore()
        store.persistenceEnabled = false
        let devilBefore = UserDefaults.standard.object(forKey: "council.devilsAdvocate") as? Int
        let synthBefore = UserDefaults.standard.object(forKey: "council.synthesizerSeat") as? Int
        store.devilsAdvocateSeatID = 99
        store.synthesizerSeatID = 99
        XCTAssertEqual(UserDefaults.standard.object(forKey: "council.devilsAdvocate") as? Int, devilBefore,
                       "a non-persisting store must not overwrite the saved devil's-advocate seat")
        XCTAssertEqual(UserDefaults.standard.object(forKey: "council.synthesizerSeat") as? Int, synthBefore,
                       "a non-persisting store must not overwrite the saved synthesizer seat")
    }

    // MARK: - Facade isolates itself from any leaked app state

    @MainActor func testConfiguredStoreNeutralizesLeakedRoleStateAndStaysNonPersisting() throws {
        let store = try Council.configuredStore([
            Advisor(backend: .claude, persona: .analyst),
            Advisor(backend: .claude, persona: .skeptic),
        ])
        XCTAssertEqual(store.devilsAdvocateSeatID, -1, "facade must neutralize any leaked devil's-advocate seat")
        XCTAssertEqual(store.synthesizerSeatID, -1, "facade must reset the synthesizer seat to auto")
        XCTAssertFalse(store.persistenceEnabled, "a facade store must never persist")
    }

    // MARK: - "Library leaves no trace" invariant (regression net for the P1 data-corruption bug)

    /// Exercises every persistence entry point a facade call can reach (seat lineup, role ids, session
    /// disk write) and asserts ZERO mutation of shared UserDefaults config and ZERO writes to the
    /// sessions directory. Fails if any future change reintroduces a write from a library path.
    @MainActor func testFacadeLeavesNoTrace() throws {
        let d = UserDefaults.standard
        let keys = ["council.seats.v7", "council.synthesizerSeat", "council.devilsAdvocate", "council.systemPrompt",
                    "council.custom1.host", "council.custom1.name"]
        let before = keys.map { d.object(forKey: $0) as? NSObject }

        func sessionSnapshot() -> [String: Date] {
            guard let dir = CouncilStore.sessionsFolderURL,
                  let files = try? FileManager.default.contentsOfDirectory(
                      at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [:] }
            var m: [String: Date] = [:]
            for f in files {
                m[f.lastPathComponent] = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
            }
            return m
        }
        let sessionsBefore = sessionSnapshot()

        // Include an in-code key AND a custom OpenAI-compatible endpoint — the paths that must stay
        // off disk / out of the Keychain.
        let store = try Council.configuredStore([
            Advisor(backend: .claude, persona: .analyst),
            Advisor(backend: .custom1, persona: .skeptic, model: "local-model",
                    apiKey: "transient-key", endpoint: URL(string: "http://localhost:9999")!),
        ])
        store.saveSeats()         // seat-lineup write — must be gated by persistenceEnabled
        store.saveConversation()  // session disk write — must be gated
        // (the role-id didSets already fired inside configuredStore — also gated)

        // The in-code key and custom endpoint must be held in memory, never persisted.
        XCTAssertFalse(store.transientKeys.isEmpty, "an in-code key must live in memory, not the Keychain")
        XCTAssertFalse(store.transientCustomEndpoints.isEmpty, "a custom endpoint must live in memory, not UserDefaults")

        for (i, k) in keys.enumerated() {
            XCTAssertEqual(d.object(forKey: k) as? NSObject, before[i], "facade mutated UserDefaults key \(k)")
        }
        XCTAssertEqual(sessionSnapshot(), sessionsBefore, "facade wrote to the sessions directory")
    }
}
