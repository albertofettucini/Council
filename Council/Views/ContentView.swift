//
//  ContentView.swift
//  Council
//

import CouncilKit
import Sparkle
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications

extension Color {
    /// A color that resolves to `light` or `dark` based on the active appearance,
    /// which is driven app-wide by `.preferredColorScheme` (see ContentView).
    static func adaptive(_ light: Color, _ dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

extension NSView {
    /// Depth-first search for a descendant view carrying this identifier.
    func descendant(withIdentifier id: String) -> NSView? {
        if identifier?.rawValue == id { return self }
        for sub in subviews {
            if let found = sub.descendant(withIdentifier: id) { return found }
        }
        return nil
    }
}

/// Behind-window blur: shows the desktop / other windows behind this app, frosted. `behindWindow`
/// blending is what makes the whole app read as one sheet of glass. It also makes its host window
/// transparent so the blur actually reaches the desktop instead of an opaque backing.
struct VisualEffectBackground: NSViewRepresentable {
    /// true = behind-window (the desktop shows through, gorgeous but the transparent window forces
    /// the window server to recomposite against the desktop on every scroll frame → jank).
    /// false = within-window on an opaque window (still frosted glass, just doesn't reveal the
    /// actual desktop) → the window server never touches the desktop → buttery scrolling.
    var desktopGlass: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = desktopGlass ? .behindWindow : .withinWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.blendingMode = desktopGlass ? .behindWindow : .withinWindow
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isOpaque = !desktopGlass
            w.backgroundColor = desktopGlass ? .clear : .windowBackgroundColor
        }
    }
}

/// "Liquid glass" palette — a deep slate, frosted surfaces, and a blue accent, with a soft
/// light variant. Token names are kept from the old brutalist theme so call sites don't churn;
/// only the values changed. `ink` = primary text/icons, `sub`/`dim` = secondary, `paper` = the
/// (now mostly translucent) surface tint, `bg` = the gradient base.
enum Blue {
    // Neutral grayscale glass — no hue. Dark base ≈ #121212 / #0e0e0e, light ≈ soft warm-white.
    static let bg    = Color.adaptive(Color(red: 0.95,  green: 0.95,  blue: 0.96),  Color(red: 0.075, green: 0.075, blue: 0.078)) // base
    static let paper = Color.adaptive(.white,                                       Color(red: 0.12,  green: 0.12,  blue: 0.125)) // solid fallback
    static let ink   = Color.adaptive(Color(red: 0.10, green: 0.10, blue: 0.11),    Color(red: 0.95,  green: 0.95,  blue: 0.96))  // primary text
    static let sub   = Color.adaptive(Color(red: 0.42,  green: 0.42,  blue: 0.44),  Color(red: 0.74,  green: 0.75,  blue: 0.77))  // secondary text (on-surface-variant)
    static let dim   = Color.adaptive(Color(red: 0.64,  green: 0.64,  blue: 0.66),  Color(red: 0.46,  green: 0.46,  blue: 0.48))  // placeholder / disabled
    static let red   = Color.adaptive(Color(red: 0.82,  green: 0.24,  blue: 0.28),  Color(red: 1.0,   green: 0.55,  blue: 0.52))  // error (kept — functional)

    // `accent` is the ONE hue in the app, reserved for meaning — the divergence/dissent signal, the
    // working/active state, and system switches. Everything else gets neutral emphasis (brighter glass
    // fill + border + glow). Keep colour rare so it actually lands when it appears.
    static let accent      = Color.adaptive(Color(red: 0.20, green: 0.50, blue: 0.95), Color(red: 0.40, green: 0.66, blue: 1.0))  // the single accent
    static let glassFill   = Color.adaptive(Color.white.opacity(0.28),                Color.white.opacity(0.045)) // thin tint — let the material + backdrop show through
    static let glassStroke = Color.adaptive(Color.black.opacity(0.08),                Color.white.opacity(0.16))  // hairline edge
    static let glassBright = Color.adaptive(Color.black.opacity(0.10),                Color.white.opacity(0.12))  // active/selected/hover fill — DARK in light mode so it actually shows on light backgrounds
    static let ok          = Color.adaptive(Color(red: 0.30, green: 0.32, blue: 0.34), Color(red: 0.88, green: 0.90, blue: 0.93)) // "done" → bright neutral
    static let warn        = Color.adaptive(Color(red: 0.55, green: 0.56, blue: 0.58), Color(red: 0.60, green: 0.62, blue: 0.66)) // "standby" → mid neutral

    /// Background tints for the palette (index 0 = none → pure glass). One color = a solid wash;
    /// two colors = a gradient mix. Kept subtle over the behind-window vibrancy.
    struct Tint { let name: String; let colors: [Color] }
    static let bgTints: [Tint] = [
        Tint(name: "None",     colors: []),
        // Solid hues:
        Tint(name: "Blue",     colors: [Color(red: 0.20, green: 0.45, blue: 0.97)]),
        Tint(name: "Cyan",     colors: [Color(red: 0.10, green: 0.68, blue: 0.90)]),
        Tint(name: "Teal",     colors: [Color(red: 0.08, green: 0.60, blue: 0.58)]),
        Tint(name: "Green",    colors: [Color(red: 0.20, green: 0.66, blue: 0.32)]),
        Tint(name: "Lime",     colors: [Color(red: 0.58, green: 0.76, blue: 0.18)]),
        Tint(name: "Amber",    colors: [Color(red: 0.97, green: 0.64, blue: 0.12)]),
        Tint(name: "Orange",   colors: [Color(red: 0.96, green: 0.46, blue: 0.14)]),
        Tint(name: "Rose",     colors: [Color(red: 0.93, green: 0.24, blue: 0.40)]),
        Tint(name: "Pink",     colors: [Color(red: 0.95, green: 0.42, blue: 0.74)]),
        Tint(name: "Violet",   colors: [Color(red: 0.54, green: 0.30, blue: 0.94)]),
        Tint(name: "Indigo",   colors: [Color(red: 0.34, green: 0.32, blue: 0.88)]),
        Tint(name: "Sky",      colors: [Color(red: 0.35, green: 0.65, blue: 0.98)]),
        Tint(name: "Emerald",  colors: [Color(red: 0.10, green: 0.72, blue: 0.50)]),
        Tint(name: "Gold",     colors: [Color(red: 0.92, green: 0.74, blue: 0.18)]),
        Tint(name: "Coral",    colors: [Color(red: 0.98, green: 0.45, blue: 0.40)]),
        Tint(name: "Crimson",  colors: [Color(red: 0.82, green: 0.10, blue: 0.24)]),
        Tint(name: "Magenta",  colors: [Color(red: 0.85, green: 0.18, blue: 0.62)]),
        Tint(name: "Lavender", colors: [Color(red: 0.66, green: 0.56, blue: 0.92)]),
        Tint(name: "Slate",    colors: [Color(red: 0.34, green: 0.40, blue: 0.50)]),
        Tint(name: "Graphite", colors: [Color(red: 0.40, green: 0.42, blue: 0.46)]),
        // Two-color mixes (gradients) — drawn split in the swatch, blended on the backdrop:
        Tint(name: "Sunset",   colors: [Color(red: 0.98, green: 0.55, blue: 0.15), Color(red: 0.90, green: 0.20, blue: 0.45)]),
        Tint(name: "Ocean",    colors: [Color(red: 0.14, green: 0.45, blue: 0.98), Color(red: 0.06, green: 0.64, blue: 0.62)]),
        Tint(name: "Aurora",   colors: [Color(red: 0.10, green: 0.64, blue: 0.55), Color(red: 0.52, green: 0.30, blue: 0.94)]),
        Tint(name: "Berry",    colors: [Color(red: 0.54, green: 0.24, blue: 0.88), Color(red: 0.95, green: 0.34, blue: 0.70)]),
        Tint(name: "Ember",    colors: [Color(red: 0.88, green: 0.18, blue: 0.24), Color(red: 0.97, green: 0.62, blue: 0.16)]),
        Tint(name: "Mint",     colors: [Color(red: 0.26, green: 0.82, blue: 0.50), Color(red: 0.10, green: 0.66, blue: 0.78)]),
        Tint(name: "Peach",    colors: [Color(red: 0.98, green: 0.70, blue: 0.30), Color(red: 0.95, green: 0.42, blue: 0.66)]),
        Tint(name: "Lagoon",   colors: [Color(red: 0.12, green: 0.70, blue: 0.86), Color(red: 0.18, green: 0.68, blue: 0.42)]),
        Tint(name: "Galaxy",   colors: [Color(red: 0.28, green: 0.24, blue: 0.78), Color(red: 0.80, green: 0.26, blue: 0.70)]),
        Tint(name: "Magma",    colors: [Color(red: 0.86, green: 0.16, blue: 0.20), Color(red: 0.97, green: 0.52, blue: 0.14)]),
        Tint(name: "Dusk",     colors: [Color(red: 0.30, green: 0.28, blue: 0.72), Color(red: 0.85, green: 0.30, blue: 0.45)]),
        Tint(name: "Tropical", colors: [Color(red: 0.55, green: 0.78, blue: 0.20), Color(red: 0.10, green: 0.70, blue: 0.80)]),
        Tint(name: "Candy",    colors: [Color(red: 0.96, green: 0.45, blue: 0.78), Color(red: 0.55, green: 0.32, blue: 0.92)]),
        Tint(name: "Steel",    colors: [Color(red: 0.36, green: 0.42, blue: 0.52), Color(red: 0.14, green: 0.62, blue: 0.78)]),
        Tint(name: "Sunrise",  colors: [Color(red: 0.98, green: 0.78, blue: 0.25), Color(red: 0.96, green: 0.42, blue: 0.16)]),
        Tint(name: "Nebula",   colors: [Color(red: 0.52, green: 0.28, blue: 0.92), Color(red: 0.14, green: 0.66, blue: 0.86)]),
        Tint(name: "Forest",   colors: [Color(red: 0.18, green: 0.55, blue: 0.30), Color(red: 0.10, green: 0.62, blue: 0.60)]),
    ]
    /// Fill style for a tint index (nil = none). Shared by the swatch and the backdrop wash.
    static func tintStyle(_ i: Int) -> AnyShapeStyle? {
        guard i > 0, i < bgTints.count, !bgTints[i].colors.isEmpty else { return nil }
        let c = bgTints[i].colors
        return c.count == 1
            ? AnyShapeStyle(c[0])
            : AnyShapeStyle(LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    static func serif(_ s: CGFloat, _ w: Font.Weight = .bold) -> Font { .system(size: s, weight: w, design: .serif) }
    static func mono(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w, design: .monospaced) }
    static func body(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w) }
}

/// One motion language for the whole app — every interaction animates with the same hand.
/// Prefer these over ad-hoc durations; the consistency is what reads as "designed" to the Mac
/// audience that notices. Tune once here and the whole app shifts together.
enum Motion {
    static let quick     = Animation.easeOut(duration: 0.17)     // hovers, collapses, tiny state flips
    static let reveal    = Animation.smooth(duration: 0.34)      // expands / graceful reveals (no bounce)
    static let view      = Animation.easeInOut(duration: 0.26)   // view, content, toggle & tint swaps
    static let cinematic = Animation.easeOut(duration: 1.1)      // first-run / hero reveals (deliberate)
    static let pulse     = Animation.easeInOut(duration: 0.85)   // looping ambient (glows, fills)
}

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT KNOBS — live-tunable in the app. Press ⌘D to open the sliders, drag to
// taste, then screenshot the values and tell me — I'll bake them in as defaults.
// ─────────────────────────────────────────────────────────────────────────────
@MainActor @Observable
final class Layout {
    static let shared = Layout()

    var windowTopInset: CGFloat   = 4    // gap above the cards (clears the traffic lights)
    var windowSideInset: CGFloat  = 12   // left/right margin around everything
    var windowBottomInset: CGFloat = 11  // bottom margin
    var sidebarGap: CGFloat       = 9    // space between sidebar and the canvas
    var sidebarWidth: CGFloat     = 222  // sidebar card width
    var sidebarTopInset: CGFloat  = 5    // space above NEW DIRECTIVE inside the sidebar
    var sidebarTrafficClear: CGFloat = 15 // push the sidebar card down to clear the macOS traffic lights
    var sidebarBottomClear: CGFloat = 16 // lift JUST the sidebar card off the bottom (dashboard unaffected)
    var panelGap: CGFloat         = 32   // space between the 3 advisor panels
    var canvasRowGap: CGFloat     = 9    // space between round-bar / panels / input
    var panelCorner: CGFloat      = 30   // advisor panel corner radius
    var roundBarTop: CGFloat      = -6   // shift the ROUND row up (−) / down (+); panels unaffected
    var exportY: CGFloat          = -4   // shift JUST the EXPORT button up (−) / down (+)
}

/// Frosted-glass surface. On macOS 26+ this uses Apple's real Liquid Glass (`.glassEffect`),
/// which genuinely refracts + reflects whatever is behind it. On older systems it falls back to
/// a hand-built material + hairline approximation so the app still builds and looks reasonable.
struct GlassPanel: ViewModifier {
    var corner: CGFloat = 18
    var strokeOpacity: Double = 1
    /// Performance mode forces the cheap material instead of real Liquid Glass (off by default —
    /// the beautiful path). A user-facing escape hatch for weaker machines.
    @AppStorage("council.liteMode") private var liteMode = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !liteMode {
            // Real Liquid Glass. `.rect(cornerRadius:)` is the shape API glassEffect expects.
            content.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            content
                .background(.regularMaterial, in: shape)
                .background(Blue.glassFill, in: shape)
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .overlay(shape.strokeBorder(Blue.glassStroke.opacity(strokeOpacity), lineWidth: 1))
                .clipShape(shape)
                .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 14)
        }
    }
}
/// A small control surface (button / chip / field) in real Liquid Glass, capsule or rounded-rect.
/// Falls back to a material on pre-26 systems. `tinted`/`interactive` map to the Glass options.
struct GlassControl: ViewModifier {
    var corner: CGFloat? = nil          // nil → capsule
    var tinted: Bool = false
    var interactive: Bool = false
    @AppStorage("council.liteMode") private var liteMode = false
    @available(macOS 26.0, *)
    private var glass: Glass {
        var g: Glass = .regular
        if tinted { g = g.tint(Blue.accent) }
        if interactive { g = g.interactive() }
        return g
    }
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !liteMode {
            if let corner { content.glassEffect(glass, in: .rect(cornerRadius: corner)) }
            else { content.glassEffect(glass, in: .capsule) }
        } else {
            let bg = AnyShapeStyle(.ultraThinMaterial)
            if let corner {
                content.background(bg, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
            } else {
                content.background(bg, in: Capsule()).overlay(Capsule().strokeBorder(Blue.glassStroke, lineWidth: 1))
            }
        }
    }
}

extension View {
    func glassPanel(corner: CGFloat = 18, strokeOpacity: Double = 1) -> some View {
        modifier(GlassPanel(corner: corner, strokeOpacity: strokeOpacity))
    }
    /// Capsule glass control (default) or rounded-rect when `corner` is given.
    func glassControl(corner: CGFloat? = nil, tinted: Bool = false, interactive: Bool = false) -> some View {
        modifier(GlassControl(corner: corner, tinted: tinted, interactive: interactive))
    }
}

/// Hover affordance: on pointer-over, a clean frosted-glass pill fades in behind the content with
/// a faint light edge — the calm "liquid glass" touch response (no flowing light).
struct GlassHover: ViewModifier {
    var corner: CGFloat = 10
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    // Adaptive tint: a slight DARK wash in light mode (so the hover box actually
                    // shows over light backgrounds), a slight light wash in dark mode.
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color.adaptive(.black.opacity(0.10), .white.opacity(0.14))))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .opacity(hovered ? 1 : 0)
            }
            .onHover { h in withAnimation(Motion.quick) { hovered = h } }
    }
}
extension View {
    func glassHover(corner: CGFloat = 10) -> some View { modifier(GlassHover(corner: corner)) }
}

/// A soft glow (ink → white in dark mode) that follows the cursor inside a view's bounds
/// on hover, clipped to the box. When `selected` and not hovering, it rests near the top as
/// a steady indicator. Used on buttons and the Light/Dark options.
private struct CursorGlow: ViewModifier {
    var selected: Bool = false
    @State private var loc: CGPoint?
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geo in
                if selected || loc != nil {
                    // Selected → fixed, centered glow (ignores the cursor). Otherwise it follows the cursor.
                    Circle()
                        .fill(Blue.ink.opacity(0.22))
                        .frame(width: 120, height: 120)
                        .blur(radius: 30)
                        .position(selected
                                  ? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                                  : (loc ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)))
                }
            }
            // Feathered mask instead of a hard clip — the glow fades out toward the edges,
            // so no rectangular boundary line appears.
            .mask(Rectangle().fill(.black).blur(radius: 12))
            .allowsHitTesting(false)
        }
        .onContinuousHover { phase in
            if case .active(let p) = phase { loc = p } else { loc = nil }
        }
        .animation(.easeOut(duration: 0.14), value: loc)
    }
}
private extension View {
    func cursorGlow(selected: Bool = false) -> some View { modifier(CursorGlow(selected: selected)) }
}

/// A plain-text/markdown document staged for the next deliberation. Holds only what the composer
/// needs to show a chip and what the engine needs to fold into each seat's prompt.
struct PickedDocument: Equatable {
    let name: String
    let text: String
    var chars: Int { text.count }
}

struct ContentView: View {
    let store: CouncilStore
    @State private var query: String = ""
    @State private var isAsking = false
    /// The in-flight round Task, so it can be cancelled (Stop).
    @State private var runningTask: Task<Void, Never>?

    /// Optional image attached to the next directive (sent to every connected seat).
    @State private var pickedImage: NSImage?
    @State private var isDropTargeted = false
    @State private var showImagePreview = false

    /// Optional text/markdown document attached to the next directive. Like the image, it rides on
    /// the request to every seat and is NOT saved into history — only the typed question is.
    @State private var pickedDocument: PickedDocument?
    /// Surfaced when an attached document is rejected (too large / unreadable).
    @State private var docError: String?

    /// Providers whose keys were orphaned by an update (ad-hoc signing — see migrateKeychainIfNeeded).
    /// Non-empty → the one-time "re-enter your keys" sheet.
    @State private var staleKeyProviders: [LLMProvider] = []
    @State private var migrationDrafts: [LLMProvider: String] = [:]
    @State private var migrationErrors: [LLMProvider: String] = [:]
    @State private var migrationBusy: LLMProvider?

    /// Optional bridge to the user's local Engram store (shown only when Engram is installed).
    @State private var engram = EngramService()

    /// Optional GUEST answer staged for the next directive: an external AI's answer, pasted in. It
    /// joins the round as one more anonymous advisor in blind review — it never calls a model.
    @State private var pickedGuest: GuestAnswer?
    @State private var showGuestSheet = false
    @State private var guestDraft = ""
    @State private var guestNameDraft = ""
    /// The viewed round's guest card in the flow — collapsed by default, like peer review.
    @State private var guestExpanded = false

    /// Appearance: "light" (default) or "dark". Toggled from Settings, not the main screen.
    @AppStorage("council.appearance") private var appearance = "light"
    /// Whether exported share images carry the "made with Council" watermark (default on).
    @AppStorage("council.shareWatermark") private var shareWatermark = true
    @State private var showSettings = false

    /// Left panel can be collapsed to give the canvas the full width.
    @State private var sidebarOpen = true

    /// Local key monitor: pressing Return while nothing is focused jumps into the composer.
    @State private var keyMonitor: Any?

    /// A provider pick awaiting confirmation because it duplicates another seat (token warning).
    struct PendingPick: Identifiable { let id = UUID(); let provider: LLMProvider; let seatID: Int }
    @State private var pendingPick: PendingPick?

    /// Which advisor panel the cursor is over — flattens its perspective tilt for easy reading.
    @State private var hoveredSeat: Int?
    @State private var handleHover = false

    /// Live layout tuner (⌘D) — drag sliders to dial in spacing, then tell me the numbers.
    private let layout = Layout.shared   // fixed layout constants (tuner removed)

    /// Single-page flow: scroll proxy for gentle stage reveals, and the peer-review disclosure.
    @State private var flowProxy: ScrollViewProxy?
    @State private var peerReviewExpanded = false

    /// Two session layouts, user's choice (Settings → App): "flow" = one page, stages beneath the
    /// answers; "classic" = each stage is its own screen in the sidebar (the pre-1.1 paradigm).
    @AppStorage("council.layout") private var layoutMode = "flow"
    private var isClassic: Bool { layoutMode == "classic" }
    /// Orb welcome (empty flow canvas) → CONFIGURE reveals the seat panels without asking anything.
    @State private var showSetupPanels = false
    /// Brief frosted interlude while the layout swaps — selecting a mode shouldn't snap.
    @State private var modeSwitching = false
    /// Which canvas Classic mode is showing (panels or one full-screen deliberation artifact).
    enum CanvasMode { case panels, peerReview, divergence, synthesis, dissent, debate }
    @State private var canvasMode: CanvasMode = .panels

    /// Top-level screen: the Home dashboard (landing) or the live roundtable.
    enum Screen { case home, council, journal }
    @State private var screen: Screen = .home

    /// History list state.
    @State private var historyQuery = ""
    /// Journal filters — the journal is meant to be read back months later, so it needs finding.
    @State private var journalQuery = ""
    @State private var journalOpenOnly = false
    /// HISTORY stays collapsed to keep the sidebar minimal; the conversation list reveals on hover.
    @State private var historyExpanded = false
    @State private var renamingSession: UUID?
    @State private var renameText = ""

    /// First-run onboarding — shown once, then never again. `didOnboard` persists; `showOnboarding`
    /// is the LOCAL @State that actually drives the overlay (so withAnimation reliably animates the
    /// dismiss — an @AppStorage change propagates async and skips the transition).
    @AppStorage("council.didOnboard") private var didOnboard = false
    @State private var showOnboarding = false

    /// Background tint index into Blue.bgTints (0 = none/pure glass). User-chosen via the palette.
    @AppStorage("council.bgTint") private var bgTintIndex = 0

    private var scheme: ColorScheme { appearance == "dark" ? .dark : .light }

    init(store: CouncilStore) { self.store = store }

    var body: some View {
        mainUI
        // Fill the whole window so content can't size to its *ideal* width and get re-centered
        // (which is what shifted the view when NEW DIRECTIVE emptied the panels).
        // Min height = where the flexible PROVIDERS / RECENT row hits its content floor. The window
        // stops here so that row never clips and its bottom stays level with the sidebar's SETTINGS;
        // above it, dragging taller grows just that row.
        .frame(minWidth: 1300, maxWidth: .infinity, minHeight: 820, maxHeight: .infinity)
        .preferredColorScheme(scheme)
        .background { shortcutButtons }
        .onAppear { if !didOnboard { showOnboarding = true } }   // instant insert; the card animates itself in
        .overlay {
            if showOnboarding {
                OnboardingCard {
                    didOnboard = true                                                  // persist (no animation needed)
                    withAnimation(Motion.cinematic) { showOnboarding = false }   // animate the blur-out
                }
                    .preferredColorScheme(scheme)
                    .transition(.revealBlur)   // slow blur-out, matching the reveal feel
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(store: store, appearance: $appearance, engram: engram) { showSettings = false }
                .preferredColorScheme(scheme)
        }
        // After an update, this build may not be able to read the previous build's Keychain items
        // (ad-hoc signing — macOS treats every release as a new app). Detect it silently and ask
        // ONCE, calmly — re-entering a key migrates the keychain generation under the hood.
        .onAppear {
            let stale = store.staleKeychainProviders()
            if !stale.isEmpty { staleKeyProviders = stale }
        }
        .sheet(isPresented: Binding(get: { !staleKeyProviders.isEmpty },
                                    set: { if !$0 { staleKeyProviders = [] } })) {
            keyMigrationSheet.preferredColorScheme(scheme)
        }
        // Layout switch (Settings → App): close the sheet, a brief frosted interlude, then the
        // chosen canvas. Lives on the BODY so it fires from any screen, not just the roundtable.
        .onChange(of: layoutMode) {
            showSettings = false
            canvasMode = .panels
            screen = .council
            withAnimation(Motion.quick) { modeSwitching = true }
            Task {
                try? await Task.sleep(for: .milliseconds(850))
                withAnimation(Motion.view) { modeSwitching = false }
            }
        }
        .overlay {
            if modeSwitching {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Text(isClassic ? "CLASSIC LAYOUT" : "FLOW LAYOUT")
                            .font(Blue.mono(11, .bold)).tracking(3).foregroundStyle(Blue.sub)
                        FillBar(once: true).frame(maxWidth: 220)
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    /// Drop keyboard focus from any text field (clicking empty space deselects inputs).
    private func resignFocus() { NSApp.keyWindow?.makeFirstResponder(nil) }

    /// While no field is focused, a plain Return jumps the cursor into the composer so the
    /// user can start typing. While a field IS focused, Return does its normal job (send / newline).
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 36,   // Return
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  let window = NSApp.keyWindow else { return event }
            if window.firstResponder is NSText { return event }   // already typing somewhere
            if let composer = window.contentView?.descendant(withIdentifier: "council.composer") {
                window.makeFirstResponder(composer)
                return nil   // consume — this Return only moved focus
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Invisible buttons that carry keyboard shortcuts (keyboard-first ethos).
    private var shortcutButtons: some View {
        Group {
            Button("") { if !isBusy { store.newSession(); screen = .council } }
                .keyboardShortcut("n", modifiers: .command)
            Button("") { showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
            Button("") { if store.canGoPrevRound { store.prevRound() } }
                .keyboardShortcut("[", modifiers: .command)
            Button("") { if store.canGoNextRound { store.nextRound() } }
                .keyboardShortcut("]", modifiers: .command)
            Button("") { if store.hasSession { Exporter.copy(store.exportMarkdown()) } }
                .keyboardShortcut("e", modifiers: .command)
            Button("") { if store.hasSession { Exporter.saveMarkdown(store.exportDecisionMemo(), name: "council-memo") } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("") { screen = .home }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { screen = .council }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { screen = .journal }
                .keyboardShortcut("3", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    private var mainUI: some View {
        HStack(spacing: layout.sidebarGap) {
            if sidebarOpen {
                sidebar
                    .overlay(alignment: .trailing) { sidebarHandle }   // stuck to the sidebar's edge
                    .padding(.top, layout.sidebarTrafficClear)         // drop the card below the traffic lights
                    .padding(.bottom, layout.sidebarBottomClear)       // lift JUST this column off the bottom
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Group {
                switch screen {
                case .home: homeDashboard
                case .council: mainCanvas
                case .journal: journalScreen
                }
            }
            .overlay(alignment: .leading) { if !sidebarOpen { sidebarHandle } }
        }
        // The glass cards stay BELOW the title-bar strip (top inset clears the traffic lights);
        // only the background extends up under them, so no card overlaps the window controls.
        .padding(.horizontal, layout.windowSideInset)
        .padding(.top, layout.windowTopInset).padding(.bottom, layout.windowBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(gridBackground.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { resignFocus() }   // click empty space → deselect any input
    }

    /// Collapse/expand control, integrated onto the leftmost vertical line (replaces the old top bar).
    /// `chevron.left` rotates 180° rather than swapping symbols, so nothing flickers under the cursor.
    private var sidebarHandle: some View {
        Button {
            withAnimation(Motion.view) { sidebarOpen.toggle() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Blue.ink)
                .rotationEffect(.degrees(sidebarOpen ? 0 : 180))
                .frame(width: 24, height: 48)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .background(Blue.glassBright, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                // Hover highlight — same feel as every other button.
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.adaptive(.black.opacity(0.10), .white.opacity(0.14)))
                    .opacity(handleHover ? 1 : 0))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(handleHover ? 1.08 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Toggle sidebar")
        .accessibilityLabel(sidebarOpen ? "Collapse sidebar" : "Expand sidebar")
        .offset(x: sidebarOpen ? 12 : 0)   // pokes out past the sidebar's right edge
        .onHover { h in withAnimation(Motion.quick) { handleHover = h } }
    }


    // MARK: Background grid

    /// Real behind-window vibrancy: the macOS desktop / windows BEHIND this app are blurred and
    /// shown through, so the whole window reads as one piece of frosted glass. The frosted panels
    /// then sit on top of that live, refracted backdrop — the actual "glass" you wanted.
    private var gridBackground: some View {
        let style = Blue.tintStyle(bgTintIndex)
        // Opaque window (no desktop showing through) — the frosted backdrop + Liquid Glass cards stay.
        return VisualEffectBackground(desktopGlass: false)
            // Plain normal-blend film (NO .color blendMode — that forced a full-window offscreen
            // composite every frame and caused the scroll jank). Saturated tint.
            .overlay { if let style { Rectangle().fill(style).opacity(0.5) } }
            .ignoresSafeArea()
            .animation(Motion.view, value: bgTintIndex)
    }



    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: layout.sidebarTopInset)

            Button(action: { store.newSession(); screen = .council }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("NEW DIRECTIVE").font(Blue.mono(11, .bold)).tracking(1)
                }
                .foregroundStyle(Blue.ink)
                .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
                .glassHover(corner: 10)            // plain text; the glass panel only appears on hover
                .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isBusy ? 0.4 : 1)
            .help(isBusy ? "Finish or stop the current generation first" : "Start a new directive")

            modeItem("square.grid.2x2", "HOME",
                     state: screen == .home ? .active : .button,
                     action: { screen = .home })

            modeItem("book.closed", "JOURNAL",
                     state: screen == .journal ? .active : .button,
                     hint: store.dueReminders.isEmpty
                        ? "Record what you decided — and how it turned out"
                        : "\(store.dueReminders.count) decision\(store.dueReminders.count == 1 ? "" : "s") waiting for an outcome",
                     badge: store.dueReminders.isEmpty ? nil : "\(store.dueReminders.count)",
                     action: { screen = .journal })

            // Flow: the session is ONE page, so no stage nav. Classic: the stages live here,
            // exactly like pre-1.1.
            modeItem("point.3.connected.trianglepath.dotted", "ROUNDTABLE",
                     state: (screen == .council && (!isClassic || canvasMode == .panels)) ? .active : .button,
                     hint: isClassic ? "The three advisors, side by side"
                                     : "The session — answers up top, analysis flows in below",
                     action: { screen = .council; canvasMode = .panels })

            if isClassic {
            modeItem("arrow.2.squarepath", "PEER REVIEW",
                     state: (screen == .council && canvasMode == .peerReview) ? .active
                          : ((store.canPeerReview || store.hasPeerReviewForViewedRound) ? .button : .locked),
                     hint: store.hasPeerReviewForViewedRound
                        ? "Show this round's peer review (already generated)"
                        : (store.canPeerReview ? "Models review each other's answers, anonymized"
                                               : "Ask a question first — unlocks once ≥2 models have answered"),
                     action: (store.canPeerReview || store.hasPeerReviewForViewedRound) ? {
                        screen = .council; canvasMode = .peerReview
                        if !store.hasPeerReviewForViewedRound { runRound { await store.peerReview() } }
                     } : nil)

            modeItem("bubble.left.and.bubble.right", "DEBATE",
                     state: (screen == .council && canvasMode == .debate) ? .active
                          : ((store.canRebut || store.hasRebuttalForViewedRound) ? .button : .locked),
                     hint: store.hasRebuttalForViewedRound
                        ? "Show this round's rebuttal — who moved, who held"
                        : (store.canRebut ? "One rebuttal round — each advisor revises or holds"
                                          : "Run peer review first — then advisors can rebut"),
                     action: (store.canRebut || store.hasRebuttalForViewedRound)
                        ? { screen = .council; canvasMode = .debate } : nil)

            modeItem("arrow.triangle.branch", "DIVERGENCE",
                     state: (screen == .council && canvasMode == .divergence) ? .active : (divergenceAvailable ? .button : .locked),
                     hint: divergenceAvailable ? "Map where advisors agree and diverge"
                                               : "Answer ≥2 advisors first",
                     action: divergenceAvailable ? { screen = .council; canvasMode = .divergence } : nil)

            modeItem("exclamationmark.bubble", "DISSENT",
                     state: (screen == .council && canvasMode == .dissent) ? .active : (store.hasDissent ? .button : .locked),
                     hint: store.hasDissent ? "The outlier's take — judge the dissent yourself"
                                            : "Appears once a divergence finds an advisor standing apart",
                     action: store.hasDissent ? { screen = .council; canvasMode = .dissent } : nil)

            modeItem("rectangle.3.group", "SYNTHESIS",
                     state: (screen == .council && canvasMode == .synthesis) ? .active : (synthesisAvailable ? .button : .locked),
                     hint: synthesisAvailable ? "Final answer that preserves the dissent"
                                              : "Answer ≥2 advisors first",
                     action: synthesisAvailable ? { screen = .council; canvasMode = .synthesis } : nil)

            }


            historySection

            Spacer(minLength: 0)

            modeItem("gearshape", "SETTINGS", state: .button) { showSettings = true }
                .padding(.bottom, 6)
        }
        .frame(width: layout.sidebarWidth)
        .frame(maxHeight: .infinity)
        .glassPanel(corner: 24)   // floating frosted card, gaps on all sides
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(Blue.mono(9, .bold)).tracking(2).foregroundStyle(Blue.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 6)
    }

    /// Sidebar deliberation row. `.button` is a normal tappable row (e.g. SETTINGS).
    private func modeItem(_ icon: String, _ label: String, state: ModeRow.ModeState,
                          hint: String? = nil, badge: String? = nil,
                          action: (() -> Void)? = nil) -> some View {
        ModeRow(icon: icon, label: label, state: state, hint: hint, badge: badge, action: action)
    }

    // MARK: Main canvas

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Minimal by default: just the label. Hovering reveals the conversation list below;
            // moving the cursor away collapses it again.
            HStack(spacing: 5) {
                Text("HISTORY").font(Blue.mono(9, .bold)).tracking(2).foregroundStyle(Blue.sub)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold)).foregroundStyle(Blue.sub)
                    .rotationEffect(.degrees(historyExpanded ? 0 : -90))
                Spacer(minLength: 0)
                if !store.sessions.isEmpty {
                    Text("\(store.sessions.count)").font(Blue.mono(9, .bold)).foregroundStyle(Blue.sub)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, historyExpanded ? 6 : 4)
            .contentShape(Rectangle())
            // Click/tap (and assistive tech) can toggle the list too — hover alone shuts out
            // keyboard and VoiceOver users entirely.
            .onTapGesture { withAnimation(Motion.reveal) { historyExpanded.toggle() } }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(historyExpanded ? "Hide history" : "Show history")

            if historyExpanded {
                if store.sessions.count > 3 || !historyQuery.isEmpty {
                    PlainTextField(text: $historyQuery, placeholder: "search…", fontSize: 11)
                        .frame(height: 16)
                        .padding(.horizontal, 18).padding(.bottom, 8)
                }
                let results = store.searchedSessions(historyQuery)   // compute once per render
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { session in
                            historyRow(session)
                        }
                        if results.isEmpty {
                            Text(historyQuery.isEmpty ? "No saved directives yet." : "No matches.")
                                .font(Blue.mono(10)).foregroundStyle(Blue.dim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18).padding(.vertical, 10)
                        }
                    }
                }
                .frame(maxHeight: 340)
                .transition(.opacity)
            }
        }
        // Reveal is graceful (a gentle no-bounce spring); collapse stays snappy so it feels responsive.
        .onHover { hovering in
            withAnimation(hovering ? Motion.reveal : Motion.quick) {
                historyExpanded = hovering
            }
        }
    }

    @ViewBuilder private func historyRow(_ s: Session) -> some View {
        if renamingSession == s.id {
            PlainTextField(text: $renameText, placeholder: "title", fontSize: 11, onSubmit: {
                store.renameSession(s.id, to: renameText); renamingSession = nil
            })
            .frame(height: 16).padding(.horizontal, 18).padding(.vertical, 10)
        } else {
            Button {
                store.openSession(s); screen = .council
            } label: {
                Text(s.title.isEmpty ? "Untitled" : s.title)
                    .font(Blue.mono(11)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(s.id == store.currentSession ? Blue.ink : Blue.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(s.id == store.currentSession ? Blue.ink.opacity(0.06) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .glassHover(corner: 10)                 // exact same geometry as the sidebar mode rows
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isBusy && s.id != store.currentSession ? 0.4 : 1)
            .contextMenu {
                Button("Rename") { renameText = s.title; renamingSession = s.id }
                Button("Delete", role: .destructive) { store.deleteSession(s.id) }
                    .disabled(isBusy)
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            Button("Copy markdown") { Exporter.copy(store.exportMarkdown()) }
            Button("Save markdown…") { Exporter.saveMarkdown(store.exportMarkdown(), name: "council") }
            Button("Save PDF…") { Exporter.savePDF(store.exportMarkdown(), name: "council") }
            Divider()
            Button("Save decision memo…") { Exporter.saveMarkdown(store.exportDecisionMemo(), name: "council-memo") }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .bold))
                Text("EXPORT").font(Blue.mono(9, .bold)).tracking(1)
            }
            .foregroundStyle(store.hasSession ? Blue.ink : Blue.dim)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Blue.glassStroke.opacity(store.hasSession ? 1 : 0.4), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!store.hasSession)
        .accessibilityLabel("Export conversation")
    }

    // MARK: Home dashboard

    /// Landing screen: usage at a glance, your council, quick-start presets, recent sessions.
    /// Entering the roundtable happens via New Directive, a preset, or a recent session.
    private var homeDashboard: some View {
        HStack(spacing: 10) {
            // Cards fill the available height and shrink with the window. A minimum window height
            // (set on the root) stops the resize before the cards hit their content floor — so they
            // adapt down to a clean point, then the window won't shrink further (no clip).
            VStack(spacing: 10) {
                HomeHero { q in
                    query = q; screen = .council
                    // If at least one advisor is connected, run it straight away (the "→" implies it
                    // will start); otherwise land on the panels so the user can connect a key first.
                    if store.seats.contains(where: store.hasKey) { ask() }
                }
                // Slim merged stats (was the USAGE + SPEND cards) — one quiet glance row, fixed height.
                dashCard("USAGE") { statStrip }
                // The two actionable cards keep their natural height.
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        dashCard("YOUR COUNCIL", fill: true) { councilOverview }
                        dashCard("QUICK START", fill: true) { quickStartList }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                // RECENT alone now (the providers reference moved to Settings → Models). It absorbs all
                // the extra height, so its bottom edge stays level with the sidebar's SETTINGS.
                dashCard("RECENT", fill: true) { recentList }
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(16)

            colorRail.frame(width: 32).padding(.trailing, 6)
        }
    }

    /// Vertical strip of background-tint swatches on the right edge. ~6 show at once and the NEXT
    /// one peeks at the bottom under a soft dark fade (+ a bobbing chevron over it), so it's obvious
    /// there are more colors to scroll to. Page stays clean.
    /// The agreed look: a thin vertical rail, ~7 swatches visible, the rest scroll (the next one
    /// peeks at the bottom edge). Smooth now that key-status no longer hits the Keychain per render.
    private var colorRail: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Blue.bgTints.indices, id: \.self) { i in
                        ColorSwatch(index: i, dot: 18, cell: 28, selected: bgTintIndex == i) {
                            withAnimation(Motion.view) { bgTintIndex = i }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 224)   // ~7 swatches; rest scroll, next peeks at the cut edge
            Spacer(minLength: 0)
        }
    }

    private func dashCard<Content: View>(_ title: String, fill: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Blue.mono(9, .bold)).tracking(2).foregroundStyle(Blue.dim)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        // When fill, the card's GLASS BACKGROUND itself stretches to the row height (so paired cards
        // are equal with no empty gap under the shorter one) — the stretch is applied BEFORE the
        // glass, not after, which was the bug that left a blank band below the card.
        .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
        .glassPanel(corner: 20)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(Blue.mono(20, .bold)).foregroundStyle(Blue.ink)
                .lineLimit(1).minimumScaleFactor(0.6)               // long values (e.g. a model name) shrink to fit
            Text(label).font(Blue.mono(9)).tracking(1).foregroundStyle(Blue.dim)
        }
        .frame(maxWidth: .infinity)
    }

    /// Merged glance stats (replaced the separate USAGE + SPEND cards) — four numbers, one quiet row.
    private var statStrip: some View {
        HStack(spacing: 0) {
            statTile(String(format: "$%.2f", store.allTimeCostUSD), "total spent")
            statDivider
            statTile(String(format: "$%.2f", store.thisMonthCostUSD), "this month")
            statDivider
            statTile("\(store.sessions.count)", "sessions")
            statDivider
            statTile(store.topModelName ?? "—", "top model")
        }
        .padding(.vertical, 2)
    }

    private var statDivider: some View {
        Rectangle().fill(Blue.glassStroke).frame(width: 1, height: 30)
    }

    private func personaLabel(_ seat: Seat) -> String {
        switch seat.id {
        case 0: return "Analyst"
        case 1: return "Practitioner"
        case 2: return "Skeptic"
        default: return "Seat \(seat.id + 1)"
        }
    }

    private func personaDescriptor(_ seat: Seat) -> String {
        switch seat.id {
        case 0: return "reasons from first principles"
        case 1: return "grounded in what works in practice"
        case 2: return "challenges the easy answer"
        default: return "your custom advisor"
        }
    }

    private var councilOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.seats) { seat in
                HStack(alignment: .center, spacing: 10) {
                    Circle().fill(store.hasKey(seat) ? Blue.ink : Color.clear)
                        .overlay(Circle().strokeBorder(Blue.glassStroke))
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(personaLabel(seat).uppercased()).font(Blue.mono(10, .bold)).foregroundStyle(Blue.ink)
                            Text(personaDescriptor(seat)).font(Blue.body(10)).foregroundStyle(Blue.dim).lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Text(seat.provider?.panelName ?? "Not set")
                                .font(Blue.mono(9)).foregroundStyle(seat.provider == nil ? Blue.dim : Blue.sub)
                            if seat.provider != nil, !seat.model.isEmpty {
                                Text("·").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                                Text(seat.model).font(Blue.mono(9)).foregroundStyle(Blue.dim).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            Button(action: { screen = .council }) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 9, weight: .bold))
                    Text("CONFIGURE").font(Blue.mono(9, .bold)).tracking(1)
                }
                .foregroundStyle(Blue.sub)
                .padding(.vertical, 6).padding(.horizontal, 9)
                .glassHover(corner: 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
    }

    private var quickStartList: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(CouncilConfig.presets.enumerated()), id: \.offset) { _, preset in
                Button(action: {
                    store.applyConfig(preset); store.newSession(); screen = .council
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name).font(Blue.mono(10, .bold)).foregroundStyle(Blue.ink)
                        Text(preset.detail ?? "").font(Blue.body(10)).foregroundStyle(Blue.dim).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .glassHover(corner: 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recentList: some View {
        Group {
            if store.sessions.isEmpty {
                Text("No sessions yet — pick a question from the hero above to begin.")
                    .font(Blue.mono(10)).foregroundStyle(Blue.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 4) {
                    ForEach(store.sessions.prefix(4)) { s in
                        Button(action: { store.openSession(s); screen = .council }) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 10) {
                                    Text(s.title.isEmpty ? "Untitled" : s.title)
                                        .font(Blue.mono(11, .bold)).foregroundStyle(Blue.ink).lineLimit(1)
                                    Spacer()
                                    Text(relativeDate(s.updatedAt)).font(Blue.mono(9)).foregroundStyle(Blue.dim)
                                    Text(String(format: "$%.2f", s.totalCostUSD))
                                        .font(Blue.mono(9)).foregroundStyle(Blue.sub)
                                        .frame(width: 46, alignment: .trailing)
                                }
                                Text(sessionPreview(s))
                                    .font(Blue.body(10)).foregroundStyle(Blue.dim)
                                    .lineLimit(1).truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 7).padding(.horizontal, 10)
                            .glassHover(corner: 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// A one-line preview of a session — its first advisor answer (or the question if none yet).
    private func sessionPreview(_ s: Session) -> String {
        for r in s.rounds {
            for a in r.answers.values where !a.isEmpty {
                return String(a.prefix(100)).replacingOccurrences(of: "\n", with: " ")
            }
            if !r.question.isEmpty { return r.question }
        }
        return "—"
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    private var mainCanvas: some View {
        VStack(spacing: layout.canvasRowGap) {
            if store.roundCount > 0 { roundNavigator }
            Group {
                if isClassic { classicCanvas } else { sessionFlow }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            directiveInput
        }
        .padding(.horizontal, 4).padding(.top, 2).padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Gentle reveal: when the pipeline moves to a new stage, ease its card into view. Fires
        // only on pipeline transitions the user initiated — never while they're idly reading.
        .onChange(of: store.pipelineStage) { _, stage in
            guard !isClassic, let stage, let target = stageAnchor(stage) else { return }
            withAnimation(Motion.view) { flowProxy?.scrollTo(target, anchor: .bottom) }
        }
        .onChange(of: store.viewingRound) {
            peerReviewExpanded = false
            if !isClassic { flowProxy?.scrollTo("flow.panels", anchor: .top) }
        }

    }

    private func stageAnchor(_ stage: String) -> String? {
        switch stage {
        case "Peer review": return "stage.pr"
        case "Divergence":  return "stage.div"
        case "Debate":      return "stage.debate"
        case "Synthesis":   return "stage.syn"
        default:            return nil
        }
    }

    /// The single session page: the signature 3 panels fill the first viewport; the deliberation
    /// stages flow in below as they complete. No mode switching — just scroll.
    private var sessionFlow: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: layout.canvasRowGap) {
                        // Empty-state welcome: council connected, nothing asked yet → one calm orb
                        // instead of three empty panels. First-run setup (no connected seat) and
                        // CONFIGURE both fall through to the panel grid.
                        if store.rounds.isEmpty, !showSetupPanels,
                           store.seats.contains(where: { store.hasKey($0) }) {
                            OrbWelcome { withAnimation(.easeInOut(duration: 0.35)) { showSetupPanels = true } }
                                .frame(height: geo.size.height)
                                .id("flow.panels")
                        } else {
                            panelGrid
                                .frame(height: geo.size.height)
                                .id("flow.panels")
                        }
                        stageFlow
                    }
                }
                .onAppear { flowProxy = proxy }
            }
        }
    }

    /// Stage cards in pipeline order. Each appears once its content exists; the stage currently
    /// generating shows a quiet progress hint in its future slot.
    @ViewBuilder private var stageFlow: some View {
        let running = store.pipelineStage
        if let g = store.viewedGuestAnswer {
            guestFlowCard(g).id("stage.guest").transition(.opacity)
        }
        if store.hasPeerReviewForViewedRound {
            peerReviewFlowCard.id("stage.pr").transition(.opacity)
        } else if running == "Peer review" {
            stageProgressCard("PEER REVIEW").id("stage.pr")
        }
        if store.divergenceText?.isEmpty == false {
            divergenceFlowCard.id("stage.div").transition(.opacity)
        } else if running == "Divergence" {
            stageProgressCard("DIVERGENCE").id("stage.div")
        }
        if store.hasRebuttalForViewedRound {
            debateFlowCard.id("stage.debate").transition(.opacity)
        } else if running == "Debate" {
            stageProgressCard("DEBATE").id("stage.debate")
        } else if store.canRebut, running == nil, !store.isWorking {
            debateOfferCard.id("stage.debate")
        }
        if store.synthesisText?.isEmpty == false {
            synthesisFlowCard.id("stage.syn").transition(.opacity)
        } else if running == "Synthesis" {
            stageProgressCard("SYNTHESIS").id("stage.syn")
        }
        if store.chairSummaryText?.isEmpty == false {
            chairSummaryFlowCard.id("stage.chair").transition(.opacity)
        } else if running == "Chair summary" {
            stageProgressCard("CHAIR SUMMARY").id("stage.chair")
        } else if store.chairError != nil {
            chairErrorCard.id("stage.chair").transition(.opacity)
        }
        if store.hasDissent {
            dissentFlowCard.id("stage.dissent").transition(.opacity)
        }
        if showRunAnalysis {
            runAnalysisCard
        }
        Color.clear.frame(height: 2)
    }

    /// The viewed round's pasted guest answer — collapsed to one quiet line until opened.
    private func guestFlowCard(_ text: String) -> some View {
        // Say what actually happened to this guest, not what usually happens to one.
        let deliberated = store.hasPeerReviewForViewedRound
        // Read the SELECTION, not just whether review has run — an excluded guest must say so
        // before the run too, not promise a blind review it was already taken out of.
        let satOut = !store.isSeatDeliberating(Round.guestSeatID)
        let subtitle = satOut ? (deliberated ? "pasted answer — sat out of this round's deliberation"
                                             : "pasted answer — sitting this round out")
                              : (deliberated ? "pasted answer — reviewed blind, like any advisor"
                                             : "pasted answer — joins the deliberation blind")
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(Motion.reveal) { guestExpanded.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Blue.sub)
                        .rotationEffect(.degrees(guestExpanded ? 90 : 0))
                    Text("GUEST").font(Blue.mono(13, .bold)).tracking(2).foregroundStyle(Blue.ink)
                    if satOut {
                        Text("SAT OUT").font(Blue.mono(7, .bold)).tracking(2).foregroundStyle(Blue.dim)
                    }
                    Text("· \(store.viewedGuestName) · \(subtitle)")
                        .font(Blue.mono(9)).foregroundStyle(Blue.sub)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .accessibilityLabel(guestExpanded ? "Collapse guest answer" : "Expand guest answer")
            if guestExpanded {
                Rectangle().fill(Blue.glassStroke).frame(height: 1)
                // Capped + independently scrollable: in the classic layout this card shares a fixed
                // canvas with the panels, so an unbounded paste would squeeze them to nothing.
                ScrollView {
                    MarkdownView(text: text, baseSize: 14).equatable().textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .frame(maxHeight: 320)
            }
        }
        .glassPanel(corner: 22)
    }

    /// The neutral chair's post-debate wrap-up.
    private var chairSummaryFlowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            stageHeader("CHAIR SUMMARY", info: chairInfo,
                        subtitle: store.viewedChairName.map { "via \($0.uppercased()) — the chair" })
            MarkdownView(text: store.chairSummaryText ?? "", baseSize: 14).equatable().textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .glassPanel(corner: 22)
    }

    /// The chair promised a wrap-up and couldn't deliver one — say so rather than leave a gap.
    private var chairErrorCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Blue.red)
            Text("CHAIR SUMMARY").font(Blue.mono(10, .bold)).tracking(2).foregroundStyle(Blue.sub)
            Text(store.chairError ?? "").font(Blue.mono(9)).foregroundStyle(Blue.red)
                .lineLimit(2).truncationMode(.tail)
            Spacer()
            Button { runRound { await store.runChairSummary() } } label: {
                Text("RETRY").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .glassHover(corner: 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(store.isWorking)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .glassPanel(corner: 22)
    }

    private let chairInfo = "The neutral chair's read of the debate — who moved, who held, and which disagreement matters most. The chair never answers the question itself, so it has no position to defend."

    /// Classic layout: the pre-1.1 canvas — panels, or ONE full-screen deliberation stage,
    /// chosen from the sidebar. Restored verbatim; gated behind Settings → App → Layout.
    @ViewBuilder private var classicCanvas: some View {
        switch canvasMode {
        case .panels:
            // A guest answer rides under the panels as the same collapsed card the flow uses —
            // panels give up a sliver of height only when a guest actually exists.
            if store.viewedGuestAnswer != nil {
                VStack(spacing: 12) {
                    panelGrid
                    if let g = store.viewedGuestAnswer { guestFlowCard(g) }
                }
            } else {
                panelGrid
            }
        case .peerReview:
            peerReviewView
        case .divergence:
            deliberationView(title: "DIVERGENCE",
                             info: divergenceInfo,
                             text: store.divergenceText,
                             loading: store.deliberationBusy && store.divergenceText == nil,
                             canGenerate: store.canSynthesize,
                             error: store.divergenceError,
                             disabledReason: deliberationDisabledReason,
                             verdict: store.agreementScore.map { DivergenceVerdict(divergence: 100 - $0, camps: store.divergenceCamps, outlier: store.outlierName) },
                             onExportImage: { copy in exportImage(title: "DIVERGENCE", text: store.divergenceText, copy: copy) },
                             onGenerate: { runRound { await store.runDivergence() } })
        case .synthesis:
            deliberationView(title: "SYNTHESIS",
                             info: synthesisInfo,
                             text: store.synthesisText,
                             loading: store.deliberationBusy && store.synthesisText == nil,
                             canGenerate: store.canSynthesize,
                             error: store.synthesisError,
                             disabledReason: deliberationDisabledReason,
                             onExportImage: { copy in exportImage(title: "SYNTHESIS", text: store.synthesisText, copy: copy) },
                             onGenerate: { runRound { await store.runSynthesis() } })
        case .dissent:
            dissentView
        case .debate:
            debateView
        }
    }

    /// "Minority report": isolates the outlier advisor's full answer with a judge-it-yourself frame.
    private var dissentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("DISSENT").font(Blue.mono(15, .bold)).tracking(2).foregroundStyle(Blue.ink)
                InfoDot(text: dissentInfo)
                Spacer()
                Button { canvasMode = .panels } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left").font(.system(size: 10, weight: .bold))
                        Text("PANELS").font(Blue.mono(10, .bold)).tracking(1)
                    }
                    .foregroundStyle(Blue.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .overlay(alignment: .bottom) { Rectangle().fill(Blue.glassStroke).frame(height: 1) }

            if let name = store.outlierName, let answer = store.outlierAnswer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 13)).foregroundStyle(Blue.accent)
                                Text("\(name.uppercased()) STOOD APART").font(Blue.mono(13, .bold)).tracking(1).foregroundStyle(Blue.ink)
                            }
                            Text("The majority isn't automatically right — advisors can share the same blind spot. Here's the dissenting take; judge it for yourself.")
                                .font(Blue.body(13)).foregroundStyle(Blue.sub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))

                        MarkdownView(text: answer, baseSize: 15).equatable().textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
                }
            } else {
                VStack(spacing: 10) {
                    Text("No clear outlier this round.").font(Blue.body(15)).italic().foregroundStyle(Blue.sub)
                    Text("The advisors landed close together — no strong dissent to spotlight.").font(Blue.mono(11)).foregroundStyle(Blue.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Bounded debate: a single rebuttal round. A cost-gated run button, then each advisor's
    /// revised-or-held take with its original answer tucked underneath, so you can see what moved.
    private var debateView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("DEBATE").font(Blue.mono(15, .bold)).tracking(2).foregroundStyle(Blue.ink)
                InfoDot(text: debateInfo)
                Text("· one rebuttal round").font(Blue.mono(9)).foregroundStyle(Blue.sub)
                Spacer()
                Button { canvasMode = .panels } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left").font(.system(size: 10, weight: .bold))
                        Text("PANELS").font(Blue.mono(10, .bold)).tracking(1)
                    }
                    .foregroundStyle(Blue.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .overlay(alignment: .bottom) { Rectangle().fill(Blue.glassStroke).frame(height: 1) }

            if store.deliberationBusy && !store.hasRebuttalForViewedRound {
                VStack(spacing: 12) {
                    Text("REBUTTING…").font(Blue.mono(11, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    FillBar(once: true).frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.hasRebuttalForViewedRound {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(store.seats) { seat in
                            if let rebuttal = store.viewedRebuttal(seat.id) {
                                debateCard(seat: seat, rebuttal: rebuttal, original: store.viewedAnswer(seat.id))
                            }
                        }
                        if let summary = store.chairSummaryText, !summary.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Text("CHAIR SUMMARY").font(Blue.mono(11, .bold)).tracking(1).foregroundStyle(Blue.ink)
                                    InfoDot(text: chairInfo)
                                    if let n = store.viewedChairName {
                                        Text("· via \(n.uppercased())").font(Blue.mono(9)).foregroundStyle(Blue.sub)
                                    }
                                    Spacer()
                                }
                                MarkdownView(text: summary, baseSize: 14).equatable().textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                        }
                    }
                    .frame(maxWidth: 820).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
            } else if store.canRebut {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 30, weight: .light)).foregroundStyle(Blue.sub)
                    Text("Let the council rebut").font(Blue.mono(14, .bold)).tracking(1).foregroundStyle(Blue.ink)
                    Text("Each advisor sees where the others landed and gets one chance to revise — or hold its ground and say why. One round only.")
                        .font(Blue.body(13)).foregroundStyle(Blue.sub).multilineTextAlignment(.center)
                        .frame(maxWidth: 420).fixedSize(horizontal: false, vertical: true)
                    Text(rebuttalCostNote).font(Blue.mono(10)).foregroundStyle(Blue.dim)
                    Button { runRound { await store.runRebuttal() } } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                            Text("RUN REBUTTAL ROUND").font(Blue.mono(11, .bold)).tracking(1)
                        }
                        .foregroundStyle(Blue.ink)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(store.isWorking)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Text("Run peer review first.").font(Blue.body(15)).italic().foregroundStyle(Blue.sub)
                    Text("The rebuttal round needs the council's critiques to push against.").font(Blue.mono(11)).foregroundStyle(Blue.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func deliberationView(title: String, info: String, text: String?, loading: Bool,
                                  canGenerate: Bool, error: String?, disabledReason: String,
                                  verdict: DivergenceVerdict? = nil,
                                  onExportImage: @escaping (Bool) -> Void,
                                  onGenerate: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(title).font(Blue.mono(15, .bold)).tracking(2).foregroundStyle(Blue.ink)
                InfoDot(text: info)
                if let n = store.synthesizerName, text != nil {
                    Text("· via \(n.uppercased())").font(Blue.mono(9)).foregroundStyle(Blue.sub)
                }
                if let error, !loading {
                    Text("⚠︎ \(error)").font(Blue.mono(9)).foregroundStyle(Blue.red)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer()
                if text != nil && !loading {
                    Button(action: onGenerate) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                            Text("REGENERATE").font(Blue.mono(9, .bold)).tracking(1)
                        }
                        .foregroundStyle(Blue.sub).padding(.horizontal, 8).padding(.vertical, 5)
                        .glassHover(corner: 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!canGenerate).help("Regenerate for this round")
                }
                if text != nil && !loading {
                    Menu {
                        Button("Save image…") { onExportImage(false) }
                        Button("Copy image") { onExportImage(true) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "photo").font(.system(size: 9, weight: .bold))
                            Text("IMAGE").font(Blue.mono(9, .bold)).tracking(1)
                        }
                        .foregroundStyle(Blue.sub).padding(.horizontal, 8).padding(.vertical, 5)
                        .glassHover(corner: 8).contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Export this as a shareable image")
                    .accessibilityLabel("Export as image")
                }
                Button { canvasMode = .panels } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left").font(.system(size: 10, weight: .bold))
                        Text("PANELS").font(Blue.mono(10, .bold)).tracking(1)
                    }
                    .foregroundStyle(Blue.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .overlay(alignment: .bottom) { Rectangle().fill(Blue.glassStroke).frame(height: 1) }

            if let v = verdict, !loading { verdictBand(v) }

            if loading {
                VStack(spacing: 12) {
                    Text("DELIBERATING…").font(Blue.mono(11, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    FillBar(once: true).frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let text, !text.isEmpty {
                ScrollView {
                    MarkdownView(text: text, baseSize: 15).equatable()
                        .textSelection(.enabled)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
            } else {
                VStack(spacing: 14) {
                    Text(info)
                        .font(Blue.body(13)).foregroundStyle(Blue.sub)
                        .multilineTextAlignment(.center).lineSpacing(2).frame(maxWidth: 400)
                    Text("Not generated for this round yet.")
                        .font(Blue.mono(9)).tracking(1).foregroundStyle(Blue.dim)
                    Button(action: onGenerate) {
                        Text("GENERATE \(title)").font(Blue.mono(11, .bold)).tracking(1)
                            .foregroundStyle(canGenerate ? Blue.ink : Blue.dim)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .background(canGenerate ? Blue.glassBright : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Blue.glassStroke, lineWidth: 1))
                            .shadow(color: Color.adaptive(.clear, .white.opacity(canGenerate ? 0.06 : 0)), radius: 12)
                    }
                    .buttonStyle(.plain).disabled(!canGenerate)
                    if !canGenerate {
                        Text(disabledReason)
                            .font(Blue.mono(9)).foregroundStyle(Blue.dim)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel(corner: 22)
    }

    private var peerReviewGenerating: Bool {
        store.deliberationBusy && store.generatingRound == store.viewingRound
    }

    /// Full-page peer review — each advisor's critique of the others, as an attributed card.
    private var peerReviewView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("PEER REVIEW").font(Blue.mono(15, .bold)).tracking(2).foregroundStyle(Blue.ink)
                InfoDot(text: peerReviewInfo)
                Text("· advisors critique each other").font(Blue.mono(9)).foregroundStyle(Blue.sub)
                Spacer()
                if store.hasPeerReviewForViewedRound && !peerReviewGenerating {
                    Button { runRound { await store.peerReview() } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                            Text("REGENERATE").font(Blue.mono(9, .bold)).tracking(1)
                        }
                        .foregroundStyle(Blue.sub).padding(.horizontal, 8).padding(.vertical, 5)
                        .glassHover(corner: 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!store.canPeerReview).help("Re-run peer review for this round")
                }
                Button { canvasMode = .panels } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left").font(.system(size: 10, weight: .bold))
                        Text("PANELS").font(Blue.mono(10, .bold)).tracking(1)
                    }
                    .foregroundStyle(Blue.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .overlay(alignment: .bottom) { Rectangle().fill(Blue.glassStroke).frame(height: 1) }

            if peerReviewGenerating && !store.hasPeerReviewForViewedRound {
                VStack(spacing: 12) {
                    Text("REVIEWING…").font(Blue.mono(11, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    FillBar(once: true).frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.hasPeerReviewForViewedRound {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(store.seats) { seat in
                            if let review = store.viewedPeerReview(seat.id), !review.isEmpty {
                                peerReviewCard(seat: seat, review: review)
                            }
                        }
                    }
                    .frame(maxWidth: 820).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
            } else {
                VStack(spacing: 14) {
                    Text(peerReviewInfo)
                        .font(Blue.body(13)).foregroundStyle(Blue.sub)
                        .multilineTextAlignment(.center).lineSpacing(2).frame(maxWidth: 400)
                    Text("Not generated for this round yet.")
                        .font(Blue.mono(9)).tracking(1).foregroundStyle(Blue.dim)
                    if deliberationChoices.count > 2 {
                        seatSelectionChips.fixedSize()
                    }
                    Button { runRound { await store.peerReview() } } label: {
                        Text("GENERATE PEER REVIEW").font(Blue.mono(11, .bold)).tracking(1)
                            .foregroundStyle(store.canPeerReview ? Blue.ink : Blue.dim)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .background(store.canPeerReview ? Blue.glassBright : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain).disabled(!store.canPeerReview)
                    if !store.canPeerReview {
                        Text(deliberationDisabledReason)
                            .font(Blue.mono(9)).foregroundStyle(Blue.dim).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel(corner: 22)
    }

    /// Divergence/Synthesis can be viewed if already generated, or run once ≥2 advisors answered.
    private var divergenceAvailable: Bool { store.canSynthesize || store.divergenceText != nil }
    private var synthesisAvailable: Bool { store.canSynthesize || store.synthesisText != nil }

    /// Why GENERATE is disabled — distinguishes "busy elsewhere" from "needs ≥2 answers".
    private var deliberationDisabledReason: String {
        store.isWorking ? "A generation is in progress — wait for it to finish."
                        : "Answer ≥2 advisors in this round first."
    }


    /// A loaded round with answers but no analysis yet (older sessions, or a stopped pipeline) —
    /// one quiet way to run it, since the stage nav is gone.
    private var showRunAnalysis: Bool {
        store.canSynthesize && !store.hasPeerReviewForViewedRound
            && store.divergenceText == nil && store.synthesisText == nil
            && store.pipelineStage == nil
    }

    private var panelGrid: some View {
        // Each panel is locked to exactly one-third of the available width. Without this, a seat
        // whose content has a wide intrinsic size (the model picker) would stretch its column and
        // push the whole window wider — so columns must never size to their content.
        GeometryReader { geo in
            let gap: CGFloat = layout.panelGap
            let colWidth = max(0, (geo.size.width - gap * 2) / 3)   // 2 gaps
            HStack(alignment: .top, spacing: gap) {
                ForEach(store.seats) { seat in
                    let hovered = hoveredSeat == seat.id

                    AdvisorPanel(seat: seat,
                                 answeredProvider: store.viewedAnswerProvider(seat.id),
                                 answer: store.viewedAnswer(seat.id),
                                 loading: store.generatingRound == store.viewingRound && store.status[seat.id] == .loading && store.pipelineStage == nil,
                                 failedMessage: panelFailure(seat.id),
                                 connected: connected(seat),
                                 canRegenerate: store.isViewingLatest && !store.viewedRoundHadAttachment,
                                 isAdversary: store.devilsAdvocateSeatID == seat.id,
                                 // Tag only when the round actually deliberated without this seat.
                                 satOut: !store.isSeatDeliberating(seat.id)
                                     && store.viewedAnswer(seat.id)?.isEmpty == false
                                     && store.hasPeerReviewForViewedRound,
                                 onValidateKey: { k in
                                     let err = await store.validateAndSaveKey(k, for: seat)
                                     if err == nil, let p = seat.provider { await store.refreshModels(for: p) }
                                     return err
                                 },
                                 onSetModel: { store.setModel($0, seatID: seat.id) },
                                 onPickProvider: { pickProvider($0, for: seat) },
                                 onResetSeat: { store.clearProvider(seatID: seat.id) },
                                 onRegenerate: { runRound { await store.regenerate(seatID: seat.id) } },
                                 availableModels: seat.provider.flatMap { store.providerModels[$0] } ?? [],
                                 readyProviders: readyProviders)
                        .frame(width: colWidth, height: geo.size.height)   // all three equal height
                        .glassPanel(corner: layout.panelCorner, strokeOpacity: hovered ? 2.2 : 1)
                        .contentShape(Rectangle())   // hover only registers over the panel's own rect
                        .onHover { hoveredSeat = $0 ? seat.id : nil }
                        .id(seat.id)   // bind the panel's @State (begun/justPicked) to its seat
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Fetch only lists we don't have yet — this view re-appears on every canvas switch, and
        // key-save / provider-pick / test-connection already refresh on change.
        .task { for p in Set(store.seats.compactMap(\.provider)) where store.providerModels[p] == nil { await store.refreshModels(for: p) } }
        .alert("Same model on two seats?",
               isPresented: Binding(get: { pendingPick != nil }, set: { if !$0 { pendingPick = nil } }),
               presenting: pendingPick) { pick in
            Button("Continue") { store.setProvider(pick.provider, seatID: pick.seatID); pendingPick = nil }
            Button("Cancel", role: .cancel) { pendingPick = nil }
        } message: { pick in
            Text("\(pick.provider.panelName) is already on another seat. Running it twice spends extra tokens and usually reduces divergence.")
        }
    }

    /// Assign a provider to a seat, warning first if the provider is already used elsewhere.
    private func pickProvider(_ provider: LLMProvider, for seat: Seat) {
        Task { await store.refreshModels(for: provider) }   // pull this provider's real model list
        if store.providerInUse(provider, excluding: seat.id) {
            pendingPick = PendingPick(provider: provider, seatID: seat.id)
        } else {
            store.setProvider(provider, seatID: seat.id)
        }
    }

    /// Providers the user can pick and use immediately — already keyed, or key-free (Ollama, the
    /// on-device model, a configured custom endpoint).
    private var readyProviders: Set<LLMProvider> {
        _ = store.keyRevision
        return Set(LLMProvider.selectable.filter { store.keyExists($0) })
    }

    private func panelFailure(_ id: Int) -> String? {
        guard store.isViewingLatest, case .failed(let m) = store.status[id] ?? .idle else { return nil }
        return m
    }

    /// Navigate between rounds; shows which round (and its question) you're viewing.
    private var roundNavigator: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Button { store.prevRound() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(store.canGoPrevRound ? Blue.ink : Blue.dim)
                        .frame(width: 28, height: 26)
                        .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Blue.glassStroke.opacity(store.canGoPrevRound ? 1 : 0.4), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!store.canGoPrevRound)
                .accessibilityLabel("Previous round")

                Button { store.nextRound() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(store.canGoNextRound ? Blue.ink : Blue.dim)
                        .frame(width: 28, height: 26)
                        .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Blue.glassStroke.opacity(store.canGoNextRound ? 1 : 0.4), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!store.canGoNextRound)
                .accessibilityLabel("Next round")
            }

            Text("ROUND \(store.viewingRound + 1) / \(store.roundCount)")
                .font(Blue.mono(10, .bold)).tracking(1).foregroundStyle(Blue.ink)
            // One chip per existing stage — the old left-nav's speed without a second nav paradigm.
            if store.hasPeerReviewForViewedRound { roundTag("PR", target: isClassic ? nil : "stage.pr").help("Peer review exists") }
            if store.divergenceText?.isEmpty == false { roundTag("DIV", target: isClassic ? nil : "stage.div").help("Divergence exists") }
            if store.hasRebuttalForViewedRound { roundTag("DEB", target: isClassic ? nil : "stage.debate").help("Debate exists") }
            if store.synthesisText?.isEmpty == false { roundTag("SYN", target: isClassic ? nil : "stage.syn").help("Synthesis exists") }
            if store.hasDissent { roundTag("DIS", target: isClassic ? nil : "stage.dissent").help("Dissent exists") }
            Text(store.viewedQuestion)
                .font(Blue.mono(10)).foregroundStyle(Blue.sub).lineLimit(1).truncationMode(.tail)
            Spacer()
            exportMenu.offset(y: layout.exportY)   // EXPORT can be nudged independently
        }
        // offset (not padding) so moving this row never pushes the panels — they stay put.
        .offset(y: layout.roundBarTop)
    }

    /// A quiet outlined chip marking that the viewed round already has this artifact (DIV / SYN).
    /// With a target it doubles as a jump-to-stage button in the flow.
    @ViewBuilder private func roundTag(_ s: String, target: String? = nil) -> some View {
        let chip = Text(s).font(Blue.mono(8, .bold)).tracking(1).foregroundStyle(Blue.ink)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Blue.glassStroke, lineWidth: 1))
        if let target {
            Button {
                if target == "stage.pr" { peerReviewExpanded = true }   // jumping to a collapsed card opens it
                withAnimation(Motion.view) { flowProxy?.scrollTo(target, anchor: .top) }
            } label: {
                chip.contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Jump to \(s) stage")
        } else {
            chip
        }
    }

    private let dissentInfo = "The advisor whose answer diverged most from the rest, surfaced on its own. The majority can be confidently wrong together — this is the take worth a second look. You decide."

    private let debateInfo = "One optional rebuttal round. Each advisor sees where the council diverged and either revises its answer or holds — and says why. Capped at one round, so cost stays bounded. The point isn't to force consensus; it's to see which positions survive scrutiny."

    /// Rough cost note: the rebuttal re-asks every answered seat once, so ≈ one more answer round.
    /// With an active chair, its closing summary is one more (disclosed) call.
    private var rebuttalCostNote: String {
        // Only the seats that actually deliberate rebut — a seat sitting out isn't billed.
        let n = store.seats.filter { store.viewedAnswer($0.id) != nil && store.isSeatDeliberating($0.id) }.count
        let base = "Runs \(n) advisor\(n == 1 ? "" : "s") once more · ≈ the cost of one answer round"
        return store.isChairActive ? base + " · +1 chair summary" : base
    }

    /// One advisor's rebuttal — its final take up top, the original answer collapsed underneath.
    private func debateCard(seat: Seat, rebuttal: String, original: String?) -> some View {
        let name = (store.viewedAnswerProvider(seat.id) ?? seat.provider?.panelName ?? "—").uppercased()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(name).font(Blue.mono(11, .bold)).tracking(1).foregroundStyle(Blue.ink)
                Text("FINAL TAKE").font(Blue.mono(8, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Blue.glassStroke, lineWidth: 1))
                Spacer()
            }
            MarkdownView(text: rebuttal, baseSize: 14).equatable().textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let original, !original.isEmpty {
                DisclosureGroup {
                    MarkdownView(text: original, baseSize: 12).equatable().textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                } label: {
                    Text("EARLIER ANSWER").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.dim)
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
    }

    private let journalInfo = "A private log of the decisions your councils informed. Record what you actually chose, then revisit to note how it played out — so over time you can see whether the council's read held up. Stored only on this Mac, never uploaded."

    /// Decision journal: the current council's decision up top (to log), then past decisions with
    /// their outcomes. Closes the loop — a council proves its worth in the decisions it shaped.
    private var journalScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("DECISION JOURNAL").font(Blue.mono(17, .bold)).tracking(2).foregroundStyle(Blue.ink)
                        InfoDot(text: journalInfo)
                        Spacer()
                        if !store.journal.isEmpty {
                            Menu {
                                Button("Save as Markdown…") {
                                    Exporter.saveMarkdown(store.exportJournal(), name: "council-journal")
                                }
                                Button("Copy") { Exporter.copy(store.exportJournal()) }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.and.arrow.up").font(.system(size: 9, weight: .bold))
                                    Text("EXPORT").font(Blue.mono(9, .bold)).tracking(1)
                                }
                                .foregroundStyle(Blue.sub).padding(.horizontal, 8).padding(.vertical, 5)
                                .glassHover(corner: 8).contentShape(Rectangle())
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .help("Export every decision and outcome — the journal only, not the transcripts")
                        }
                    }
                    Text("What you decided after the council — and how it turned out. The council earns its keep in your decisions, not its answers.")
                        .font(Blue.body(13)).foregroundStyle(Blue.sub).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 2)

                // Search + the open-loops filter appear once there's enough journal to get lost in.
                if store.journal.count > 2 {
                    HStack(spacing: 10) {
                        PlainTextField(text: $journalQuery, placeholder: "search decisions…", fontSize: 12)
                            .frame(height: 16)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Blue.glassStroke, lineWidth: 1))
                        let open = store.awaitingOutcome.count
                        Button { journalOpenOnly.toggle() } label: {
                            Text("AWAITING OUTCOME\(open > 0 ? " · \(open)" : "")")
                                .font(Blue.mono(9, .bold)).tracking(1)
                                .foregroundStyle(journalOpenOnly ? Blue.ink : Blue.sub)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(journalOpenOnly ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear),
                                            in: Capsule())
                                .overlay(Capsule().strokeBorder(Blue.glassStroke.opacity(journalOpenOnly ? 1 : 0.5), lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Show only decisions whose outcome you haven't recorded yet")
                    }
                }

                // Reminders that came due: decision logged, outcome still open — pinned up top so
                // the loop actually gets closed. Calm by design: a section, not a notification.
                let due = store.dueReminders.filter { $0.id != store.currentSession }
                if !due.isEmpty {
                    Text("OUTCOME DUE").font(Blue.mono(10, .bold)).tracking(1.5).foregroundStyle(Blue.dim)
                    ForEach(due) { s in journalCard(s, isCurrent: false) }
                }

                if store.hasSession, let cur = store.sessions.first(where: { $0.id == store.currentSession }) {
                    journalCard(cur, isCurrent: true)
                        // Re-key the card to the session: without this, switching sessions reuses the
                        // card's @State (draft text + edit mode) from the PREVIOUS session.
                        .id(cur.id)
                }

                let dueIDs = Set(due.map(\.id))
                let past = store.searchedJournal(journalQuery)
                    .filter { $0.id != store.currentSession && !dueIDs.contains($0.id) }
                    .filter { !journalOpenOnly || ($0.outcome ?? "").isEmpty }
                if !past.isEmpty {
                    Text(journalQuery.isEmpty && !journalOpenOnly ? "PAST DECISIONS"
                                                                 : "MATCHES · \(past.count)")
                        .font(Blue.mono(10, .bold)).tracking(1.5).foregroundStyle(Blue.dim)
                        .padding(.top, 6)
                    ForEach(past) { s in journalCard(s, isCurrent: false) }
                } else if !journalQuery.isEmpty || journalOpenOnly {
                    Text(journalOpenOnly && journalQuery.isEmpty
                         ? "Every decision has an outcome recorded. Nice."
                         : "No decisions match that.")
                        .font(Blue.body(13)).italic().foregroundStyle(Blue.sub)
                        .padding(.vertical, 12)
                }

                if !store.hasSession && past.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed").font(.system(size: 28, weight: .light)).foregroundStyle(Blue.dim)
                        Text("No decisions logged yet.").font(Blue.body(14)).italic().foregroundStyle(Blue.sub)
                        Text("After a council answers, come back and record what you chose.").font(Blue.body(12)).foregroundStyle(Blue.dim)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 48)
                }
            }
            .frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }

    /// One journal card with every closure wired — decision/outcome/reminder, and the optional
    /// Engram hand-off when a connection exists.
    private func journalCard(_ s: Session, isCurrent: Bool) -> some View {
        JournalEntryCard(session: s, isCurrent: isCurrent,
                         onSaveDecision: { store.recordDecision($0, for: s.id) },
                         onSaveOutcome: { store.recordOutcome($0, for: s.id) },
                         onSetReminder: { store.setReminder($0, for: s.id) },
                         onRememberEngram: engram.connected ? {
                             do {
                                 let mid = try engram.remember(text: store.engramMemoryText(for: s),
                                                               supersedes: s.engramMemoryID)
                                 store.markRememberedInEngram(s.id, memoryID: mid)
                                 return nil
                             } catch {
                                 return error.localizedDescription
                             }
                         } : nil)
    }

    /// The analyst's structured read of a round, shown as a band atop the Divergence view.
    struct DivergenceVerdict { let divergence: Int; let camps: Int?; let outlier: String? }

    /// Score band: how far apart the council landed (high = more disagreement = the signal), how
    /// many camps, and the outlier — plus the honest caveat that this is agreement, not truth.
    @ViewBuilder private func verdictBand(_ v: DivergenceVerdict) -> some View {
        let hot = v.divergence >= 50
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(v.divergence)").font(Blue.mono(32, .bold)).foregroundStyle(hot ? Blue.accent : Blue.ink)
                    Text("/100").font(Blue.mono(11)).foregroundStyle(Blue.dim)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("DIVERGENCE").font(Blue.mono(9, .bold)).tracking(2).foregroundStyle(Blue.sub)
                    Text("how far apart the council landed").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                }
                Spacer()
                if let c = v.camps { verdictStat("\(c)", "CAMPS") }
                if let o = v.outlier, !o.isEmpty { verdictStat(o.uppercased(), "OUTLIER") }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Blue.glassStroke).frame(height: 6)
                    Capsule().fill(hot ? Blue.accent : Blue.sub)
                        .frame(width: max(6, geo.size.width * Double(v.divergence) / 100), height: 6)
                }
            }
            .frame(height: 6)
            Text("measures agreement, not correctness — models can share the same blind spot.")
                .font(Blue.body(11)).foregroundStyle(Blue.dim)
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Blue.glassStroke).frame(height: 1) }
    }

    private func verdictStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value).font(Blue.mono(13, .bold)).foregroundStyle(Blue.ink).lineLimit(1)
            Text(label).font(Blue.mono(8, .bold)).tracking(1.5).foregroundStyle(Blue.sub)
        }
    }

    private let peerReviewInfo = "Each advisor critiques the others' answers, shown anonymized so there's no brand bias — it surfaces the weak spots the council finds in each other's reasoning."

    private func peerReviewCard(seat: Seat, review: String) -> some View {
        let name = (store.viewedAnswerProvider(seat.id) ?? seat.provider?.panelName ?? "—").uppercased()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(name).font(Blue.mono(11, .bold)).tracking(1).foregroundStyle(Blue.ink)
                if seat.id == store.devilsAdvocateSeatID {
                    Text("DEVIL'S ADVOCATE").font(Blue.mono(8, .bold)).tracking(1).foregroundStyle(Blue.red)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Blue.red.opacity(0.5), lineWidth: 1))
                }
                Spacer()
            }
            MarkdownView(text: review, baseSize: 14).equatable().textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
    }

    private func connected(_ seat: Seat) -> Bool {
        _ = store.keyRevision
        return store.hasKey(seat)
    }

    // MARK: Flow stage cards

    private let divergenceInfo = "Where the council disagrees. It skips what everyone already shares and pulls out the real fault lines — what they split on, and why."
    private let synthesisInfo = "The council's answers distilled into one — the common ground plus the strongest individual points, for a single, decision-ready read."

    /// Shared header for a stage card in the flow: title + info dot + optional subtitle/actions.
    @ViewBuilder private func stageHeader(_ title: String, info: String, subtitle: String? = nil,
                                          showVia: Bool = false,
                                          onRegenerate: (() -> Void)? = nil, canRegenerate: Bool = true,
                                          onExportImage: ((Bool) -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            Text(title).font(Blue.mono(13, .bold)).tracking(2).foregroundStyle(Blue.ink)
            InfoDot(text: info)
            if let subtitle {
                Text("· \(subtitle)").font(Blue.mono(9)).foregroundStyle(Blue.sub)
            }
            if showVia, let n = store.synthesizerName {
                Text("· via \(n.uppercased())").font(Blue.mono(9)).foregroundStyle(Blue.sub)
            }
            // A configured chair that couldn't run: name who actually wrote this, not who was meant to.
            if showVia, let note = store.chairFallbackNote {
                Text("· \(note)").font(Blue.mono(9)).foregroundStyle(Blue.red)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            if let onRegenerate {
                Button(action: onRegenerate) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                        Text("REGENERATE").font(Blue.mono(9, .bold)).tracking(1)
                    }
                    .foregroundStyle(Blue.sub).padding(.horizontal, 8).padding(.vertical, 5)
                    .glassHover(corner: 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!canRegenerate).help("Regenerate for this round")
            }
            if let onExportImage {
                Menu {
                    Button("Save image…") { onExportImage(false) }
                    Button("Copy image") { onExportImage(true) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "photo").font(.system(size: 9, weight: .bold))
                        Text("IMAGE").font(Blue.mono(9, .bold)).tracking(1)
                    }
                    .foregroundStyle(Blue.sub).padding(.horizontal, 8).padding(.vertical, 5)
                    .glassHover(corner: 8).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Export this as a shareable image")
                .accessibilityLabel("Export as image")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Blue.glassStroke).frame(height: 1) }
    }

    /// Quiet inline hint for the stage the pipeline is generating right now.
    private func stageProgressCard(_ title: String) -> some View {
        HStack(spacing: 14) {
            Text(title).font(Blue.mono(10, .bold)).tracking(2).foregroundStyle(Blue.sub)
            FillBar(once: false).frame(maxWidth: 160)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .glassPanel(corner: 22)
        .transition(.opacity)
    }

    private var runAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ANALYSIS").font(Blue.mono(10, .bold)).tracking(1.5).foregroundStyle(Blue.ink)
                    Text(analysisSubtitle)
                        .font(Blue.body(10)).foregroundStyle(Blue.dim)
                }
                Spacer()
                Button { runRound { await store.runAutoPipeline() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                        Text("RUN").font(Blue.mono(10, .bold)).tracking(1)
                    }
                    .foregroundStyle(Blue.paper)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Blue.ink, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(store.isWorking)
            }
            // With 3+ positions on the table, the answers can be cherry-picked into deliberation.
            if deliberationChoices.count > 2 {
                seatSelectionChips
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
        .glassPanel(corner: 22)
    }

    private var analysisSubtitle: String {
        let all = deliberationChoices.count
        let included = deliberationChoices.filter { store.isSeatDeliberating($0.id) }.count
        return included < all
            ? "Peer review → divergence → synthesis, over \(included) of \(all) answers."
            : "Peer review → divergence → synthesis for this round."
    }

    /// The positions of the viewed round that CAN deliberate (the engine drops answers whose seat
    /// lost its key), for the selection chips. Anything the engine won't use must not be offered —
    /// otherwise the "keep at least two" rule counts seats that aren't really there.
    private var deliberationChoices: [(id: Int, name: String)] {
        guard store.rounds.indices.contains(store.viewingRound) else { return [] }
        let round = store.rounds[store.viewingRound]
        let usable = store.participantIDs(in: store.viewingRound)
            .union(round.includedSeatIDs.map(Set.init) ?? [])   // keep excluded-but-usable seats listed
        var out: [(id: Int, name: String)] = []
        for seat in store.seats
        where round.answers[seat.id]?.isEmpty == false && (usable.contains(seat.id) || store.hasKey(seat)) {
            out.append((seat.id, round.answerProviders[seat.id] ?? seat.provider?.panelName ?? "Advisor"))
        }
        if round.guestAnswer != nil { out.append((Round.guestSeatID, round.guestName)) }
        return out
    }

    /// One tappable pill per answered position: tap to sit it out of deliberation (min 2 stay in).
    private var seatSelectionChips: some View {
        HStack(spacing: 6) {
            // At exactly two included, removing another would leave nothing to deliberate — the
            // chips say so instead of offering a click that quietly does nothing.
            let includedCount = deliberationChoices.filter { store.isSeatDeliberating($0.id) }.count
            ForEach(deliberationChoices, id: \.id) { c in
                let on = store.isSeatDeliberating(c.id)
                let locked = on && includedCount <= 2
                Button { toggleDeliberation(c.id) } label: {
                    Text(c.name.uppercased()).font(Blue.mono(8, .bold)).tracking(1)
                        .foregroundStyle(on ? (locked ? Blue.sub : Blue.ink) : Blue.dim)
                        .padding(.horizontal, 8).padding(.vertical, 3.5)
                        .background(on ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear), in: Capsule())
                        .overlay(Capsule().strokeBorder(Blue.glassStroke.opacity(on ? 1 : 0.5), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(locked ? "Deliberation needs at least two answers"
                             : (on ? "\(c.name) deliberates — click to sit it out"
                                   : "\(c.name) sits out — click to include"))
                .accessibilityLabel(on ? "\(c.name) included — exclude from deliberation" : "\(c.name) excluded — include in deliberation")
            }
            Spacer(minLength: 0)
        }
    }

    private func toggleDeliberation(_ id: Int) {
        guard store.rounds.indices.contains(store.viewingRound) else { return }
        let round = store.rounds[store.viewingRound]
        // Count only positions actually on offer — an answered seat whose key is gone can't be the
        // second participant that keeps deliberation alive.
        let offered = Set(deliberationChoices.map(\.id))
        var set = (round.includedSeatIDs.map(Set.init) ?? offered).intersection(offered)
        if set.contains(id) {
            guard set.count > 2 else { return }   // deliberation needs at least two positions
            set.remove(id)
        } else {
            set.insert(id)
        }
        store.setDeliberationSelection(set == offered ? nil : set, forRound: store.viewingRound)
    }

    /// Peer review stage card — collapsed by default; one tap reveals the full critiques.
    private var peerReviewFlowCard: some View {
        let count = store.seats.filter { store.viewedPeerReview($0.id)?.isEmpty == false }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button { withAnimation(Motion.reveal) { peerReviewExpanded.toggle() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Blue.sub)
                            .rotationEffect(.degrees(peerReviewExpanded ? 90 : 0))
                        Text("PEER REVIEW").font(Blue.mono(13, .bold)).tracking(2).foregroundStyle(Blue.ink)
                        Text("· \(count) critique\(count == 1 ? "" : "s")").font(Blue.mono(9)).foregroundStyle(Blue.sub)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(peerReviewExpanded ? "Collapse peer review" : "Expand peer review")
                InfoDot(text: peerReviewInfo)
                Spacer()
                if peerReviewExpanded {
                    Button { runRound { await store.peerReview() } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                            Text("REGENERATE").font(Blue.mono(9, .bold)).tracking(1)
                        }
                        .foregroundStyle(Blue.sub).padding(.horizontal, 8).padding(.vertical, 5)
                        .glassHover(corner: 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!store.canPeerReview).help("Re-run peer review for this round")
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            if peerReviewExpanded {
                Rectangle().fill(Blue.glassStroke).frame(height: 1)
                VStack(spacing: 14) {
                    ForEach(store.seats) { seat in
                        if let review = store.viewedPeerReview(seat.id), !review.isEmpty {
                            peerReviewCard(seat: seat, review: review)
                        }
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .transition(.opacity)
            }
        }
        .glassPanel(corner: 22)
    }

    private var divergenceFlowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            stageHeader("DIVERGENCE", info: divergenceInfo, showVia: true,
                        onRegenerate: { runRound { await store.runDivergence() } },
                        canRegenerate: store.canSynthesize,
                        onExportImage: { copy in exportImage(title: "DIVERGENCE", text: store.divergenceText, copy: copy) })
            if let v = store.agreementScore.map({ DivergenceVerdict(divergence: 100 - $0, camps: store.divergenceCamps, outlier: store.outlierName) }) {
                verdictBand(v)
            }
            if let error = store.divergenceError {
                Text("⚠︎ \(error)").font(Blue.mono(9)).foregroundStyle(Blue.red)
                    .padding(.horizontal, 24).padding(.top, 10)
            }
            if let t = store.divergenceText {
                MarkdownView(text: t, baseSize: 15).equatable().textSelection(.enabled)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
        }
        .glassPanel(corner: 22)
    }

    private var synthesisFlowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            stageHeader("SYNTHESIS", info: synthesisInfo, showVia: true,
                        onRegenerate: { runRound { await store.runSynthesis() } },
                        canRegenerate: store.canSynthesize,
                        onExportImage: { copy in exportImage(title: "SYNTHESIS", text: store.synthesisText, copy: copy) })
            if let error = store.synthesisError {
                Text("⚠︎ \(error)").font(Blue.mono(9)).foregroundStyle(Blue.red)
                    .padding(.horizontal, 24).padding(.top, 10)
            }
            if let t = store.synthesisText {
                MarkdownView(text: t, baseSize: 15).equatable().textSelection(.enabled)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
        }
        .glassPanel(corner: 22)
    }

    /// Debate stage card — each advisor's final take, original answer tucked underneath.
    private var debateFlowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            stageHeader("DEBATE", info: debateInfo, subtitle: "final takes — who moved, who held")
            VStack(spacing: 14) {
                ForEach(store.seats) { seat in
                    if let rebuttal = store.viewedRebuttal(seat.id) {
                        debateCard(seat: seat, rebuttal: rebuttal, original: store.viewedAnswer(seat.id))
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .glassPanel(corner: 22)
    }

    /// The optional debate, offered quietly in its pipeline slot — one bounded round, user opts in.
    private var debateOfferCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 14, weight: .light)).foregroundStyle(Blue.sub)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("DEBATE").font(Blue.mono(10, .bold)).tracking(1.5).foregroundStyle(Blue.ink)
                    Text("· optional").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                    InfoDot(text: debateInfo)
                }
                Text("One rebuttal round — each advisor revises or holds. \(rebuttalCostNote)")
                    .font(Blue.body(10)).foregroundStyle(Blue.dim)
            }
            Spacer()
            Button { runRound { await store.runRebuttal() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                    Text("RUN").font(Blue.mono(10, .bold)).tracking(1)
                }
                .foregroundStyle(Blue.paper)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Blue.ink, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(store.isWorking)
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
        .glassPanel(corner: 22)
    }

    /// "Minority report" stage card: the outlier advisor's full answer, judge-it-yourself framing.
    private var dissentFlowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            stageHeader("DISSENT", info: dissentInfo)
            if let name = store.outlierName, let answer = store.outlierAnswer {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 13)).foregroundStyle(Blue.accent)
                            Text("\(name.uppercased()) STOOD APART").font(Blue.mono(13, .bold)).tracking(1).foregroundStyle(Blue.ink)
                        }
                        Text("The majority isn't automatically right — advisors can share the same blind spot. Here's the dissenting take; judge it for yourself.")
                            .font(Blue.body(13)).foregroundStyle(Blue.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))

                    MarkdownView(text: answer, baseSize: 15).equatable().textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
        .glassPanel(corner: 22)
    }

    private var directiveInput: some View {
      VStack(alignment: .trailing, spacing: 6) {
        // Quiet session usage readout, right-aligned just above the input pill.
        if store.sessionInputTokens + store.sessionOutputTokens > 0 {
            HStack(spacing: 6) {
                Image(systemName: "bolt").font(.system(size: 8, weight: .bold))
                Text("\(tokenString)").font(Blue.mono(9))
                Text("·").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                Text("~\(costString)").font(Blue.mono(9))
            }
            .foregroundStyle(Blue.sub)
            .padding(.trailing, 6)
            .help("Session tokens · estimated cost (you pay providers directly)")
        }

        VStack(alignment: .leading, spacing: 12) {
            if let img = pickedImage {
                HStack(spacing: 10) {
                    Button { showImagePreview = true } label: {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 46, height: 46).clipped()
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Blue.paper)
                                    .padding(2).background(Blue.ink)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Enlarge")
                    .accessibilityLabel("Enlarge attached image")
                    Text("IMAGE ATTACHED").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    Button { pickedImage = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Blue.ink)
                            .frame(width: 22, height: 22).overlay(Rectangle().stroke(Blue.ink, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove attached image")
                    Spacer()
                }
            }

            if let doc = pickedDocument {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Blue.sub)
                        .frame(width: 46, height: 46)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.name).font(Blue.mono(10, .bold)).foregroundStyle(Blue.ink)
                            .lineLimit(1).truncationMode(.middle)
                        Text("\(doc.chars.formatted()) chars · sent to every seat")
                            .font(Blue.mono(9)).foregroundStyle(Blue.sub)
                    }
                    Button { pickedDocument = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Blue.ink)
                            .frame(width: 22, height: 22).overlay(Rectangle().stroke(Blue.ink, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove attached document")
                    Spacer()
                }
            }

            if let g = pickedGuest {
                HStack(spacing: 10) {
                    Image(systemName: "theatermasks")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Blue.sub)
                        .frame(width: 46, height: 46)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GUEST ANSWER\(g.name.map { " · \($0.uppercased())" } ?? "")")
                            .font(Blue.mono(10, .bold)).foregroundStyle(Blue.ink)
                            .lineLimit(1).truncationMode(.tail)
                        Text("\(g.text.count.formatted()) chars · joins the round anonymously")
                            .font(Blue.mono(9)).foregroundStyle(Blue.sub)
                    }
                    Button { pickedGuest = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Blue.ink)
                            .frame(width: 22, height: 22).overlay(Rectangle().stroke(Blue.ink, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove guest answer")
                    Spacer()
                }
            }

            if let docError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                    Text(docError).font(Blue.mono(9)).lineLimit(2)
                }
                .foregroundStyle(Blue.red)
            }

            HStack(spacing: 14) {
                Button(action: pickAttachment) {
                    Image(systemName: "paperclip").font(.system(size: 15)).foregroundStyle(Blue.sub)
                        .frame(width: 30, height: 30)
                        .glassHover(corner: 15)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach an image or a text/markdown document")
                .accessibilityLabel("Attach image or document")
                Button {
                    guestDraft = pickedGuest?.text ?? guestDraft
                    guestNameDraft = pickedGuest?.name ?? guestNameDraft
                    showGuestSheet = true
                } label: {
                    Image(systemName: "theatermasks")
                        .font(.system(size: 15))
                        .foregroundStyle(pickedGuest == nil ? Blue.sub : Blue.ink)
                        .frame(width: 30, height: 30)
                        .glassHover(corner: 15)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Guest seat — paste another AI's answer; the council reviews it blind, as one of its own")
                .accessibilityLabel("Add a guest answer")
                ComposerTextView(text: $query, placeholder: "Enter a command or prompt…",
                                 onSubmit: ask, onPasteImage: { pickedImage = $0 })
                    .frame(maxWidth: .infinity)
                    .frame(height: composerHeight)
                Button(action: isBusy ? stop : ask) {
                    Image(systemName: isBusy ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isBusy ? Blue.red : (canAsk ? Blue.paper : Blue.dim))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        // THE primary action of the canvas: ink-filled when ready, quiet glass otherwise.
                        .background(canAsk && !isBusy ? AnyShapeStyle(Blue.ink) : AnyShapeStyle(Blue.glassBright), in: Circle())
                        .overlay(Circle().strokeBorder(Blue.glassStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!isBusy && !canAsk)
                .accessibilityLabel(isBusy ? "Stop" : "Execute")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        // A fixed-radius rounded rect, NOT a Capsule: a Capsule's corner radius is half its height,
        // so once an attachment chip makes the pill tall the ends balloon into huge semicircles and
        // the send button looks adrift in the curve. 24 keeps the single-line pill looking rounded
        // while the multi-row state stays a tidy box. Keep all three layers on the same shape.
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(Blue.glassBright, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(isDropTargeted ? Blue.ink.opacity(0.4) : Blue.glassStroke,
                          lineWidth: isDropTargeted ? 2 : 1))
        .shadow(color: Color.adaptive(.black.opacity(0.10), .white.opacity(0.08)), radius: 20, y: 6)
        .shadow(color: .black.opacity(0.30), radius: 16, y: 10)
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
      }
      .sheet(isPresented: $showImagePreview) {
            imagePreviewSheet.preferredColorScheme(scheme)
      }
      .sheet(isPresented: $showGuestSheet) {
            guestSheet.preferredColorScheme(scheme)
      }
    }

    /// One calm sheet after an update whose keys didn't survive the signature change — instead of
    /// macOS storming the user with a login-password dialog per key.
    @ViewBuilder private var keyMigrationSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("UPDATE INSTALLED").font(Blue.mono(11, .bold)).tracking(2).foregroundStyle(Blue.ink)
                Spacer()
                Button { staleKeyProviders = [] } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Blue.ink)
                        .frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Dismiss")
            }
            .padding(20)
            Rectangle().fill(Blue.glassStroke).frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                Text("Council updated. Because it ships without a paid Apple certificate (free, open source), macOS treats each version as a new app and won't hand it the previous version's Keychain items.")
                    .font(Blue.body(13)).foregroundStyle(Blue.sub)
                    .fixedSize(horizontal: false, vertical: true)
                // Re-enter right here: sending the user off to hunt for a key field was the whole
                // problem. Saving one key also performs the Keychain generation hop under the hood.
                VStack(alignment: .leading, spacing: 10) {
                    Text("RE-ENTER THESE KEYS ONCE").font(Blue.mono(9, .bold)).tracking(1.5).foregroundStyle(Blue.sub)
                    ForEach(staleKeyProviders, id: \.self) { p in
                        migrationKeyRow(p)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                Text("Keys stay in your Mac's Keychain — Council never sends them anywhere but the model itself. You can re-enter one later from an advisor panel in a new session (⌘N).")
                    .font(Blue.mono(9)).foregroundStyle(Blue.dim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button { staleKeyProviders = [] } label: {
                        Text(staleKeyProviders.isEmpty ? "DONE" : "LATER").font(Blue.mono(10, .bold)).tracking(1)
                            .foregroundStyle(Blue.paper)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Blue.ink, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .frame(width: 470)
        .background(Blue.bg)
    }

    /// One provider's inline re-entry row inside the migration sheet.
    @ViewBuilder private func migrationKeyRow(_ p: LLMProvider) -> some View {
        let draft = Binding<String>(get: { migrationDrafts[p] ?? "" },
                                    set: { migrationDrafts[p] = $0 })
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle().fill(Blue.red).frame(width: 6, height: 6)
                Text(p.panelName).font(Blue.mono(12)).foregroundStyle(Blue.ink)
                Spacer()
                if migrationBusy == p {
                    Text("CHECKING…").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                }
            }
            HStack(spacing: 8) {
                MaskedKeyField(text: draft, onSubmit: { saveMigrationKey(p) })
                    .frame(height: 18)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Blue.glassStroke, lineWidth: 1))
                Button { saveMigrationKey(p) } label: {
                    Text("SAVE").font(Blue.mono(9, .bold)).tracking(1)
                        .foregroundStyle(draft.wrappedValue.isEmpty ? Blue.dim : Blue.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .glassHover(corner: 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(draft.wrappedValue.isEmpty || migrationBusy != nil)
            }
            if let err = migrationErrors[p] {
                Text(err).font(Blue.mono(9)).foregroundStyle(Blue.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func saveMigrationKey(_ p: LLMProvider) {
        let key = (migrationDrafts[p] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, migrationBusy == nil else { return }
        migrationBusy = p
        migrationErrors[p] = nil
        Task {
            // Validate against the provider before storing, exactly like the panel's key step.
            let seat = store.seats.first { $0.provider == p } ?? Seat(id: 0, archetype: .sage, provider: p)
            let err = await store.validateAndSaveKey(key, for: seat)
            migrationBusy = nil
            if let err {
                migrationErrors[p] = err
            } else {
                migrationDrafts[p] = nil
                staleKeyProviders.removeAll { $0 == p }
            }
        }
    }

    private let guestInfo = "A guest seat lets an outside answer face the council. Paste it here; in peer review it appears as just another anonymous advisor — the models can't tell it was pasted — and it counts in divergence, dissent, and synthesis. It never generates anything itself."

    @ViewBuilder private var guestSheet: some View {
        let trimmed = guestDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let capError = trimmed.isEmpty ? nil : CouncilLimits.guestError(trimmed)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("GUEST SEAT").font(Blue.mono(11, .bold)).tracking(2).foregroundStyle(Blue.ink)
                InfoDot(text: guestInfo)
                Spacer()
                Button { showGuestSheet = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Blue.ink)
                        .frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close guest sheet")
            }
            .padding(20)
            Rectangle().fill(Blue.glassStroke).frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                Text("Paste an answer from any AI — ChatGPT, Gemini, anywhere. With your next question it takes a seat as one more anonymous advisor: peer-reviewed blind, and counted in divergence and synthesis. It never runs a model, so it can't answer back in the debate round.")
                    .font(Blue.body(13)).foregroundStyle(Blue.sub)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $guestDraft)
                    .font(Blue.body(13)).foregroundStyle(Blue.ink).scrollContentBackground(.hidden)
                    .frame(maxHeight: .infinity).padding(8)
                    .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Blue.glassStroke, lineWidth: 1))

                HStack(spacing: 10) {
                    PlainTextField(text: $guestNameDraft, placeholder: "name (optional — revealed only after review)", fontSize: 11)
                        .frame(width: 300, height: 16)
                    Spacer()
                    Text("\(trimmed.count.formatted()) chars")
                        .font(Blue.mono(9)).foregroundStyle(capError == nil ? Blue.dim : Blue.red)
                }

                if let capError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                        Text(capError).font(Blue.mono(9)).lineLimit(2)
                    }
                    .foregroundStyle(Blue.red)
                }

                HStack {
                    Text("Tip: strip lines like “As ChatGPT…” — the review is blind, and a self-introduction unblinds it.")
                        .font(Blue.mono(9)).foregroundStyle(Blue.dim)
                    Spacer()
                    Button {
                        let name = guestNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        pickedGuest = GuestAnswer(name: name.isEmpty ? nil : name, text: trimmed)
                        showGuestSheet = false
                    } label: {
                        Text("SEAT THE GUEST").font(Blue.mono(10, .bold)).tracking(1)
                            .foregroundStyle(trimmed.isEmpty || capError != nil ? Blue.ink : Blue.paper)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(trimmed.isEmpty || capError != nil ? AnyShapeStyle(Blue.glassFill) : AnyShapeStyle(Blue.ink),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Blue.glassStroke, lineWidth: trimmed.isEmpty || capError != nil ? 1 : 0))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmed.isEmpty || capError != nil)
                    .opacity(trimmed.isEmpty || capError != nil ? 0.5 : 1)
                }
            }
            .padding(20)
        }
        .frame(width: 580, height: 470)
        .background(Blue.bg)
    }

    @ViewBuilder private var imagePreviewSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ATTACHED IMAGE").font(Blue.mono(11, .bold)).tracking(2).foregroundStyle(Blue.ink)
                Spacer()
                Button { showImagePreview = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Blue.ink)
                        .frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                        .contentShape(Rectangle())
                        .cursorGlow()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close image preview")
            }
            .padding(20)
            Rectangle().fill(Blue.glassStroke).frame(height: 1)

            if let img = pickedImage {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
            } else {
                Text("No image.").font(Blue.body(14)).foregroundStyle(Blue.sub)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 680, height: 560)
        .background(Blue.bg)
    }

    private var canAsk: Bool {
        (!query.trimmingCharacters(in: .whitespaces).isEmpty || pickedImage != nil || pickedDocument != nil) && !isAsking
    }

    private var tokenString: String {
        let t = store.sessionInputTokens + store.sessionOutputTokens
        return t >= 1000 ? String(format: "%.1fK tok", Double(t) / 1000) : "\(t) tok"
    }
    private var costString: String { String(format: "$%.4f", store.sessionCostUSD) }

    /// Composer grows to fit explicit newlines AND long wrapped lines (so a long paste without any
    /// `\n` no longer collapses to a 1-line box that hides its own text), 1→6 lines, then scrolls.
    private var composerHeight: CGFloat {
        // Approximate visual wrapping: a composer line fits ~58 characters at the default width.
        let visualLines = query.components(separatedBy: "\n")
            .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / 58.0))) }
        return CGFloat(min(6, max(1, visualLines))) * 18 + 5
    }

    /// Plain-text/markdown types accepted as a document attachment.
    private static let docTypes: [UTType] = [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]

    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image] + ContentView.docTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let img = NSImage(contentsOf: url) {
            pickedImage = img
            docError = nil
        } else if let doc = readDocument(at: url) {
            ingestDocument(name: doc.name, raw: doc.raw)
        } else {
            docError = "Couldn’t read “\(url.lastPathComponent)” as text."
        }
    }

    /// Read a file URL's text. Wraps the read in security-scoped access so it succeeds for sandboxed
    /// drag-drop (and is a harmless no-op for files chosen via the open panel). Pure read, no state —
    /// safe to call off the main actor, which the drop handler does while the URL is still valid.
    private func readDocument(at url: URL) -> (name: String, raw: String)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (url.lastPathComponent, raw)
    }

    /// Validate already-read document text against the shared engine cap and stage it (or surface an
    /// error). Mutates view state, so it must run on the main actor.
    private func ingestDocument(name: String, raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { docError = "“\(name)” is empty."; return }
        if let err = CouncilLimits.documentError(text) { docError = err; return }
        docError = nil
        pickedDocument = PickedDocument(name: name, text: text)
    }

    /// Drop handler: an image becomes the picked image; a text/markdown file becomes the document.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { obj, _ in
                if let img = obj as? NSImage { DispatchQueue.main.async { pickedImage = img; docError = nil } }
            }
            return true
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let isText = ContentView.docTypes.contains { type in
                    (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: type) ?? false
                } || ["md", "markdown", "txt", "text"].contains(url.pathExtension.lowercased())
                // Read while the URL is still valid (inside the completion), then hop to main to stage.
                // Surface the same kind of error the open panel does, so both entry points behave alike.
                guard isText else {
                    DispatchQueue.main.async { docError = "Can’t attach “\(url.lastPathComponent)” — only text or markdown files." }
                    return
                }
                guard let doc = readDocument(at: url) else {
                    DispatchQueue.main.async { docError = "Couldn’t read “\(url.lastPathComponent)” as text." }
                    return
                }
                DispatchQueue.main.async { ingestDocument(name: doc.name, raw: doc.raw) }
            }
            return true
        }
        return false
    }

    /// Re-encode the attached NSImage to PNG bytes for the API request.
    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func ask() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!q.isEmpty || pickedImage != nil || pickedDocument != nil), !isBusy else { return }
        // No connected advisor → the engine creates no round at all. Say so and KEEP the question,
        // the attachment and any pasted guest answer instead of quietly binning them (which is
        // exactly what the post-update, keys-not-yet-re-entered state looks like).
        guard store.seats.contains(where: { store.hasKey($0) }) else {
            docError = "No advisor is connected yet — start a new session (⌘N) and add a model + key on a panel."
            return
        }
        let image: ImageAttachment? = pickedImage
            .flatMap(pngData(from:))
            .map { ImageAttachment(data: $0, mediaType: "image/png") }
        let document = pickedDocument?.text
        let guest = pickedGuest
        isAsking = true
        query = ""
        pickedImage = nil
        pickedDocument = nil
        pickedGuest = nil
        guestDraft = ""; guestNameDraft = ""
        docError = nil
        if isClassic { canvasMode = .panels }
        else { withAnimation(Motion.view) { flowProxy?.scrollTo("flow.panels", anchor: .top) } }
        runningTask = Task {
            await store.ask(q, image: image, document: document, guest: guest)
            // Analysis is OPT-IN: once ≥2 answers land, the flow offers a single RUN — nothing
            // spends tokens without a click.
            isAsking = false
            runningTask = nil
        }
    }

    /// Anything running right now (any advisor loading, a deliberation round, or a tracked task).
    private var isBusy: Bool {
        runningTask != nil || store.deliberationBusy || store.status.values.contains { $0 == .loading }
    }

    /// Stop the in-flight round and return loading advisors to idle.
    private func stop() {
        runningTask?.cancel()
        runningTask = nil
        store.cancelAll()
        isAsking = false
    }

    /// Run a deliberation round as the cancellable in-flight task.
    private func runRound(_ op: @escaping () async -> Void) {
        runningTask = Task { await op(); runningTask = nil }
    }

    /// Render a deliberation artifact to a shareable PNG (current theme) and save it or copy it.
    private func exportImage(title: String, text: String?, copy: Bool) {
        guard let text, !text.isEmpty else { return }
        let card = ShareCard(title: title, via: store.synthesizerName,
                             question: store.viewedQuestion, markdown: text,
                             watermark: shareWatermark)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return }
        if copy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        } else {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "council-\(title.lowercased()).png"
            panel.allowedContentTypes = [.png]
            if panel.runModal() == .OK, let url = panel.url { try? png.write(to: url) }
        }
    }
}

// MARK: - Sidebar mode row

/// One sidebar deliberation row (ROUNDTABLE / PEER REVIEW / …). Active or hovered → a glass pill;
/// the pill geometry is identical in both states so borders never mismatch.
/// One decision-journal entry. Owns its own draft state so several can edit independently in a list.
private struct JournalEntryCard: View {
    let session: Session
    let isCurrent: Bool
    let onSaveDecision: (String) -> Void
    let onSaveOutcome: (String) -> Void
    var onSetReminder: ((Date?) -> Void)? = nil
    /// Present only when Engram is connected — returns an error message, or nil on success.
    var onRememberEngram: (() -> String?)? = nil

    @State private var decisionDraft: String
    @State private var outcomeDraft: String
    @State private var editingDecision: Bool
    @State private var showCustomDate = false
    @State private var customDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var engramError: String?

    init(session: Session, isCurrent: Bool,
         onSaveDecision: @escaping (String) -> Void, onSaveOutcome: @escaping (String) -> Void,
         onSetReminder: ((Date?) -> Void)? = nil,
         onRememberEngram: (() -> String?)? = nil) {
        self.session = session
        self.isCurrent = isCurrent
        self.onSaveDecision = onSaveDecision
        self.onSaveOutcome = onSaveOutcome
        self.onSetReminder = onSetReminder
        self.onRememberEngram = onRememberEngram
        _decisionDraft = State(initialValue: session.decision ?? "")
        _outcomeDraft = State(initialValue: session.outcome ?? "")
        _editingDecision = State(initialValue: (session.decision ?? "").isEmpty)
    }

    private var hasDecision: Bool { !(session.decision ?? "").isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if isCurrent {
                    Text("THIS COUNCIL").font(Blue.mono(8, .bold)).tracking(1).foregroundStyle(Blue.sub)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Blue.glassStroke, lineWidth: 1))
                }
                Text(session.title.isEmpty ? "Untitled" : session.title)
                    .font(Blue.mono(12, .bold)).foregroundStyle(Blue.ink).lineLimit(1)
                Spacer()
                if let d = session.decisionAt {
                    Text(Self.fmt.string(from: d)).font(Blue.mono(9)).foregroundStyle(Blue.dim)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("DECISION").font(Blue.mono(9, .bold)).tracking(1.5).foregroundStyle(Blue.sub)
                if editingDecision {
                    TextEditor(text: $decisionDraft)
                        .font(Blue.body(13)).foregroundStyle(Blue.ink).scrollContentBackground(.hidden)
                        .frame(minHeight: 58, maxHeight: 130).padding(8)
                        .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    HStack {
                        if hasDecision {
                            Button { decisionDraft = session.decision ?? ""; editingDecision = false } label: {
                                Text("CANCEL").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.dim)
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                        saveButton("SAVE DECISION", enabled: !decisionDraft.trimmed.isEmpty) {
                            onSaveDecision(decisionDraft.trimmed); editingDecision = false
                        }
                    }
                } else {
                    Text(session.decision ?? "").font(Blue.body(14)).foregroundStyle(Blue.ink).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    Button { editingDecision = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil").font(.system(size: 9))
                            Text("EDIT").font(Blue.mono(9, .bold)).tracking(1)
                        }.foregroundStyle(Blue.dim)
                    }.buttonStyle(.plain)
                }
            }

            // Outcome reminder — only while the loop is still open (decision logged, outcome not).
            if hasDecision && !editingDecision, (session.outcome ?? "").isEmpty, let onSetReminder {
                HStack(spacing: 6) {
                    Text("REMIND ME").font(Blue.mono(8, .bold)).tracking(1.5).foregroundStyle(Blue.dim)
                    reminderChip("1W") { onSetReminder(Calendar.current.date(byAdding: .day, value: 7, to: Date())) }
                    reminderChip("1M") { onSetReminder(Calendar.current.date(byAdding: .month, value: 1, to: Date())) }
                    reminderChip("CUSTOM") { showCustomDate = true }
                        .popover(isPresented: $showCustomDate, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("REMIND ON").font(Blue.mono(9, .bold)).tracking(1.5).foregroundStyle(Blue.sub)
                                DatePicker("", selection: $customDate, in: Date()..., displayedComponents: .date)
                                    .datePickerStyle(.field).labelsHidden()
                                Button {
                                    onSetReminder(customDate)
                                    showCustomDate = false
                                } label: {
                                    Text("SET").font(Blue.mono(10, .bold)).tracking(1).foregroundStyle(Blue.paper)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Blue.ink, in: RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                        }
                    if session.remindAt != nil {
                        reminderChip("OFF") { onSetReminder(nil) }
                    }
                    Spacer()
                    if let r = session.remindAt {
                        Text(r <= Date() ? "outcome due" : "reminder · \(Self.fmt.string(from: r))")
                            .font(Blue.mono(9)).foregroundStyle(Blue.dim)
                    }
                }
            }

            if hasDecision && !editingDecision {
                Rectangle().fill(Blue.glassStroke).frame(height: 1).padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("HOW IT TURNED OUT").font(Blue.mono(9, .bold)).tracking(1.5).foregroundStyle(Blue.sub)
                    if let o = session.outcome, !o.isEmpty {
                        Text(o).font(Blue.body(13)).foregroundStyle(Blue.ink).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        if let oa = session.outcomeAt {
                            Text("logged \(Self.fmt.string(from: oa))").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                        }
                    } else {
                        TextEditor(text: $outcomeDraft)
                            .font(Blue.body(13)).foregroundStyle(Blue.ink).scrollContentBackground(.hidden)
                            .frame(minHeight: 44, maxHeight: 110).padding(8)
                            .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Blue.glassStroke, lineWidth: 1))
                        HStack {
                            Spacer()
                            saveButton("LOG OUTCOME", enabled: !outcomeDraft.trimmed.isEmpty) {
                                onSaveOutcome(outcomeDraft.trimmed)
                            }
                        }
                    }
                }
            }

            // Optional Engram hand-off — shown only when Engram is connected (see EngramService).
            if hasDecision && !editingDecision, let onRememberEngram {
                HStack(spacing: 8) {
                    Button { engramError = onRememberEngram() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "brain").font(.system(size: 9, weight: .bold))
                            Text(session.engramRememberedAt == nil ? "REMEMBER IN ENGRAM" : "UPDATE IN ENGRAM")
                                .font(Blue.mono(9, .bold)).tracking(1)
                        }
                        .foregroundStyle(Blue.sub)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .glassHover(corner: 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Write this decision into your Engram memory — your other AI tools can recall it (they see it after they restart)")
                    if let at = session.engramRememberedAt {
                        Text("remembered · \(Self.fmt.string(from: at))").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                    }
                    Spacer()
                    if let engramError {
                        Text(engramError).font(Blue.mono(9)).foregroundStyle(Blue.red)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
    }

    private func reminderChip(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(Blue.mono(8, .bold)).tracking(1).foregroundStyle(Blue.sub)
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .overlay(Capsule().strokeBorder(Blue.glassStroke, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func saveButton(_ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(Blue.mono(10, .bold)).tracking(1)
                .foregroundStyle(enabled ? Blue.paper : Blue.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                // The card's one primary action — filled when it can actually save.
                .background(enabled ? AnyShapeStyle(Blue.ink) : AnyShapeStyle(Blue.glassFill),
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Blue.glassStroke, lineWidth: enabled ? 0 : 1))
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.5)
    }

    static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct ModeRow: View {
    enum ModeState { case active, locked, button }
    let icon: String
    let label: String
    let state: ModeState
    var hint: String?
    var badge: String?
    var action: (() -> Void)?
    @State private var hovered = false

    private var active: Bool { state == .active }
    private var locked: Bool { state == .locked }

    var body: some View {
        let showPill = active || (hovered && action != nil && !locked)
        let row = HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 15))
            Text(label).font(Blue.mono(11, .bold)).tracking(1)
            Spacer()
            if let badge {
                Text(badge).font(Blue.mono(9, .bold)).foregroundStyle(Blue.sub)
            }
            if locked { Image(systemName: "lock.fill").font(.system(size: 9)) }
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .foregroundStyle(locked ? Blue.dim : Blue.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Blue.glassBright))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                .opacity(showPill ? 1 : 0)
        }
        // Generous outer inset so adjacent highlighted pills keep a clear gap (no collision).
        .padding(.horizontal, 12).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isOver in
            guard action != nil else { return }
            withAnimation(Motion.quick) { hovered = isOver }
        }
        .help(hint ?? (locked ? "Not built yet — on the roadmap"
                              : (state == .button ? "Settings" : "Active mode: all models answer in parallel")))

        if let action {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

// MARK: - Advisor panel

/// A small ⓘ affordance that reveals a one/two-sentence explanation in a popover. Used in the
/// Peer Review / Divergence / Synthesis headers so a newcomer knows what each view does.
private struct InfoDot: View {
    let text: String
    @State private var open = false
    @State private var hovering = false
    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovering || open ? Blue.ink : Blue.sub)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("What is this?")
        .accessibilityLabel("About this view")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            Text(text)
                .font(Blue.body(12.5))
                .foregroundStyle(Blue.ink)
                .lineSpacing(2)
                .frame(width: 250, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        }
    }
}

private struct AdvisorPanel: View {
    let seat: Seat
    /// Provider name stored with this round's answer (used for the title when the seat is unassigned).
    var answeredProvider: String? = nil
    let answer: String?
    let loading: Bool
    let failedMessage: String?
    let connected: Bool
    let canRegenerate: Bool
    let isAdversary: Bool
    /// This seat answered but sits out of the round's deliberation (selective deliberation).
    var satOut: Bool = false
    let onValidateKey: (String) async -> String?   // returns nil on success, else an error message
    let onSetModel: (String) -> Void
    let onPickProvider: (LLMProvider) -> Void
    let onResetSeat: () -> Void
    let onRegenerate: () -> Void
    /// Models actually available for this seat's provider, live-fetched (Ollama installs / OpenRouter
    /// catalogue / a keyed provider's /models). Empty → fall back to the fixed suggestion list.
    let availableModels: [String]
    /// Providers usable right now — sorted to the top of the picker so setup isn't a scroll hunt.
    var readyProviders: Set<LLMProvider> = []

    @State private var keyDraft = ""
    @State private var modelSearch = ""
    @State private var validating = false
    @State private var keyError: String?
    /// True only after the user picks a provider / enters a key this session — gates the
    /// model-selection step so returning users (already set up) go straight to ready.
    @State private var justPicked = false
    /// Set once the user confirms the model with BEGIN.
    @State private var begun = false
    @State private var panelHover = false

    private var hasAnswer: Bool { answer?.isEmpty == false }
    private var failed: Bool { failedMessage != nil }
    /// Live model list when we have one (Ollama installs / OpenRouter catalogue / a keyed /models),
    /// otherwise the provider's fixed suggestions — so the picker is never blank.
    private var modelChoices: [String] {
        availableModels.isEmpty ? (seat.provider?.modelOptions ?? []) : availableModels
    }
    /// The model-selection step: after a provider is picked, before BEGIN. Comes BEFORE the key
    /// step so the user chooses a model first, then (if needed) enters a key.
    private var showingModelPicker: Bool {
        seat.provider != nil && justPicked && !begun && !hasAnswer && !loading && !failed
    }

    /// Conversation underway → shrink the header to give the answer room.
    private var hasConversation: Bool { hasAnswer || loading || failed }

    private var statusText: String {
        if seat.provider == nil { return "NO MODEL SELECTED" }
        if !connected { return "OFFLINE — KEY REQUIRED" }
        if loading { return "PROCESSING" }
        if failed { return "ERROR" }
        return hasAnswer ? "ACTIVE" : "STANDBY"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.top, 18)

            DashLine().stroke(Blue.glassStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 1).padding(.vertical, hasConversation ? 8 : 12)

            statusLine
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.view, value: hasConversation)
        .onHover { panelHover = $0 }
        // A provider actually got assigned (covers both direct pick and the dup-warning Continue)
        // → advance to the SELECT MODEL step. Clearing it (reset → nil) drops back to the picker.
        .onChange(of: seat.provider) { _, newValue in
            justPicked = (newValue != nil)
            if newValue == nil { begun = false }
        }
    }

    private var panelHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text((seat.provider?.panelName ?? answeredProvider ?? "—").uppercased())
                    .font(Blue.mono(hasConversation ? 13 : 18, .bold)).tracking(1).foregroundStyle(Blue.ink)
                    .lineLimit(1).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                if connected && !showingModelPicker { modelMenu }
                if isAdversary {
                    Text("ADVERSARY").font(Blue.mono(7, .bold)).tracking(2).foregroundStyle(Blue.dim)
                        .help("Devil's advocate — attacks the consensus in peer review")
                }
                if satOut {
                    Text("SAT OUT").font(Blue.mono(7, .bold)).tracking(2).foregroundStyle(Blue.dim)
                        .help("Not part of this round's deliberation — excluded, or this seat has no key right now")
                }
            }
            Spacer()
            if seat.provider != nil && !hasConversation {
                Button {
                    // onResetSeat clears the provider → the onChange(of: seat.provider) handler
                    // resets begun/justPicked. We only clear the key-entry scratch state here.
                    keyError = nil; keyDraft = ""
                    onResetSeat()
                } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 11)).foregroundStyle(Blue.sub)
                        .frame(width: 26, height: 26)
                        .glassHover(corner: 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Change model — back to picker")
                .accessibilityLabel("Change model")
            }
        }
        .padding(.bottom, hasConversation ? 8 : 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Blue.glassStroke).frame(height: 1) }
    }

    /// Small, quiet menu showing the active model id — transparency, and change it anytime.
    private var modelMenu: some View {
        Menu {
            ForEach(Array(modelChoices.prefix(60)), id: \.self) { m in
                Button { onSetModel(m) } label: {
                    if m == seat.model { Label(m, systemImage: "checkmark") } else { Text(m) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(seat.model).font(Blue.mono(9)).foregroundStyle(Blue.sub)
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)).foregroundStyle(Blue.sub)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Change this seat's model")
        .accessibilityLabel("Change model")
    }

    /// Status accent color drives the pill + text tint.
    private var statusColor: Color {
        if failed { return Blue.red }
        if loading { return Blue.accent }
        if hasAnswer { return Blue.ok }
        if seat.provider == nil || !connected { return Blue.dim }
        return Blue.warn   // standby
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.8), radius: loading ? 4 : 2)
            Text(statusText)
                .font(Blue.mono(hasConversation ? 9 : 11, .bold))
                .foregroundStyle(statusColor)
            Spacer()
            if panelHover && canRegenerate && (hasAnswer || failed) && !loading {
                Button(action: onRegenerate) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                        Text(failed ? "RETRY" : "REGEN").font(Blue.mono(8, .bold)).tracking(1)
                    }
                    .foregroundStyle(failed ? Blue.red : Blue.sub).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(failed ? "Retry this advisor" : "Regenerate this advisor's answer")
                .accessibilityLabel(failed ? "Retry advisor" : "Regenerate advisor")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if hasAnswer || loading || failed {
            answerView   // a conversation (incl. a loaded session's answers) always wins over setup
        } else if seat.provider == nil {
            providerPickerView           // 1. pick provider
        } else if showingModelPicker {
            modelSelectionView           // 2. pick model (then BEGIN)
        } else if !connected {
            keyEntryView                 // 3. key — only if BEGIN found this provider needs one
        } else {
            Text("Awaiting directive.")
                .font(Blue.body(15)).italic().foregroundStyle(Blue.sub)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Shown right after a provider is picked: pick a model, then BEGIN to confirm.
    private var modelSelectionView: some View {
        let all = modelChoices
        let filtered = modelSearch.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(modelSearch) }
        let long = all.count > 8   // OpenRouter-sized lists need search + a scroll cap
        return VStack(alignment: .leading, spacing: 14) {
            Text("SELECT MODEL").font(Blue.mono(11, .bold)).tracking(2).foregroundStyle(Blue.sub)
            if long {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Blue.dim)
                    TextField("filter \(all.count) models…", text: $modelSearch)
                        .textFieldStyle(.plain).font(Blue.mono(11)).foregroundStyle(Blue.ink)
                }
                .padding(.vertical, 7).padding(.horizontal, 10)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element) { idx, m in
                        Button { onSetModel(m) } label: {
                            HStack {
                                Text(m).font(Blue.mono(12)).foregroundStyle(Blue.ink)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                if m == seat.model {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Blue.ink)
                                }
                            }
                            .padding(.vertical, 10).padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(m == seat.model ? Blue.glassBright : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < filtered.count - 1 {
                            Rectangle().fill(Blue.glassStroke).frame(height: 1)
                        }
                    }
                }
            }
            .frame(maxHeight: long ? 240 : nil)
            // Short lists hug their content — without this the greedy ScrollView stretches a
            // 3-item list into a tall empty bordered box.
            .fixedSize(horizontal: false, vertical: !long)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))

            HStack {
                Spacer()
                Button { withAnimation(Motion.view) { begun = true } } label: {
                    HStack(spacing: 6) {
                        // If the chosen provider needs a key we don't have yet, BEGIN leads to key entry.
                        Text(connected ? "BEGIN" : "CONTINUE").font(Blue.mono(11, .bold)).tracking(1)
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Blue.paper)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Blue.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 300)
    }

    private var answerView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let answer, !answer.isEmpty {
                        if loading {
                            // Streaming fast path: verbatim text is near-free to relayout; the
                            // markdown parse happens exactly ONCE, when the stream finishes.
                            Text(verbatim: answer)
                                .font(Blue.body(14)).foregroundStyle(Blue.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            MarkdownView(text: answer).equatable().textSelection(.enabled)
                        }
                    }
                    if loading {
                        HStack(spacing: 0) { StreamingCaret(); Spacer(minLength: 0) }
                    }
                    if let failedMessage {
                        Text("! " + failedMessage).font(Blue.mono(11)).foregroundStyle(Blue.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
            }
            .onChange(of: answer) { _, _ in
                // While streaming, follow-scroll INSTANTLY — an animated scroll per flush stacks
                // interrupted 0.25s animations and forces extra layout passes at 10Hz × seats.
                if loading { proxy.scrollTo("end", anchor: .bottom) } else { scrollToEnd(proxy) }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("end", anchor: .bottom) }
    }

    /// First state of an empty seat: a box that opens on hover into the provider list.
    private var providerPickerView: some View {
        ProviderPicker(onPick: pick, ready: readyProviders)
    }

    /// Key entry — reached only after a model is chosen and BEGIN finds the provider needs a key.
    private var keyEntryView: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("> ENTER YOUR API KEY").font(Blue.mono(12, .bold)).foregroundStyle(Blue.ink)
            MaskedKeyField(text: $keyDraft, onSubmit: submitKey)
                .frame(height: 18)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                .disabled(validating)
                .opacity(validating ? 0.5 : 1)
            if validating {
                VStack(spacing: 6) {
                    Text("VALIDATING…").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    FillBar(once: true)
                }
            } else if let keyError {
                Text(keyError).font(Blue.mono(10)).foregroundStyle(Blue.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !validating, let url = seat.provider?.consoleURL {
                Link(destination: url) {
                    Text("Where do I get a key?  ↗").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: 280)
    }

    private func pick(_ provider: LLMProvider) {
        // Reset the per-step flags, then let the parent assign. We do NOT set justPicked here —
        // a duplicate-provider pick may be cancelled in the alert, so justPicked must follow the
        // ACTUAL assignment (onModelStepReady), never the click.
        begun = false; keyError = nil; keyDraft = ""
        onPickProvider(provider)
    }

    private func submitKey() {
        let k = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !validating else { return }
        validating = true
        keyError = nil
        Task {
            let error = await onValidateKey(k)   // tiny test call; saves only if it works
            validating = false
            if let error {
                keyError = error                 // invalid / no balance → stay, show why
            } else {
                keyDraft = ""                    // wipe in-memory draft
                begun = true                     // key valid → seat is ready (model already chosen)
            }
        }
    }
}

// MARK: - Provider picker (hover-to-open box)

/// A compact box that opens on HOVER (not click) into the provider list: ~2 options show fully,
/// the next fades into fog at the bottom edge, and the rest is reachable by scrolling.
private struct ProviderPicker: View {
    let onPick: (LLMProvider) -> Void
    /// Providers that are ready to use right now (keyed, or key-free like Ollama). They sort to the
    /// top: this list is the first thing a new user touches, and someone who came for the free
    /// local option shouldn't have to scroll past nine paid ones to find it.
    var ready: Set<LLMProvider> = []
    @State private var open = false
    /// Cards ignore clicks for a moment after the list opens. The list opens on HOVER and grows,
    /// which slides a card under a cursor that was aiming at the header — without this, the first
    /// click picks whichever provider happened to land there.
    @State private var armed = false

    private var ordered: [LLMProvider] {
        let all = LLMProvider.selectable
        let readyOnes = all.filter { ready.contains($0) }
        return readyOnes + all.filter { !ready.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(Blue.ink).frame(width: 14, height: 2)
                Text("PICK YOUR MODEL").font(Blue.mono(11, .bold)).tracking(3).foregroundStyle(Blue.sub)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Blue.sub)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .contentShape(Rectangle())

            if open {
                Rectangle().fill(Blue.ink.opacity(0.2)).frame(height: 1)
                ScrollView(showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(Array(ordered.enumerated()), id: \.element) { idx, prov in
                            ProviderCard(provider: prov, index: idx,
                                         ready: ready.contains(prov)) {
                                guard armed else { return }
                                onPick(prov)
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(height: 310)   // ~4 cards — most users find theirs without scrolling at all
                .mask(                 // fade the bottom edge into "fog" → signals scroll
                    LinearGradient(stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1.0)
                    ], startPoint: .top, endPoint: .bottom)
                )
                .transition(.opacity)
            }
        }
        .onChange(of: open) { _, isOpen in
            armed = false
            guard isOpen else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(220))
                armed = true
            }
        }
        .frame(maxWidth: 320)   // cap, but shrink to fit a narrow column instead of forcing it wider
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(Blue.glassBright, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(open ? Blue.glassStroke.opacity(2) : Blue.glassStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { h in withAnimation(Motion.quick) { open = h } }
    }
}

// MARK: - Provider card (animated tile in "PICK YOUR MODEL")

/// One provider tile: staggered fade/slide-in entrance, cursor-glow + lift + sliding arrow on hover.
private struct ProviderCard: View {
    let provider: LLMProvider
    let index: Int
    /// Usable right now — keyed, or key-free like Ollama. Marked so the ready ones read as ready.
    var ready = false
    let action: () -> Void
    @State private var hovered = false
    @State private var shown = false

    /// Every card gets a one-word descriptor (uses the provider note, else a type hint).
    private var note: String {
        if let n = provider.pickerNote { return n }
        switch provider {
        case .claude, .openAI, .gemini: return "frontier"
        case .grok:    return "contrarian"
        case .mistral: return "open-weight"
        default:       return ""
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(provider.panelName.uppercased())
                            .font(Blue.mono(13, .bold)).tracking(1).foregroundStyle(Blue.ink)
                        if ready {
                            Circle().fill(Blue.ok).frame(width: 5, height: 5)
                                .help("Ready to use — no setup needed")
                        }
                    }
                    if !note.isEmpty {
                        Text(note.uppercased()).font(Blue.mono(8, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(hovered ? Blue.ink : Blue.dim)
                    .offset(x: hovered ? 4 : 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(hovered ? Blue.glassBright : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Blue.glassStroke, lineWidth: hovered ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered ? 1.015 : 1)
        .onHover { h in withAnimation(Motion.quick) { hovered = h } }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 12)
        .onAppear {
            withAnimation(Motion.reveal.delay(Double(index) * 0.045)) { shown = true }
        }
    }
}

// MARK: - Masked key field (plain NSTextField + manual masking → NO AutoFill popup)

/// macOS shows the "Passwords…" AutoFill popover for ANY `NSSecureTextField`, and there
/// is no public API to suppress it. So we do NOT use a secure field. Instead this is a
/// plain `NSTextField` that only ever *displays* bullets; the real characters live solely
/// in the bound @State (wiped right after they're handed to the Keychain). Because it is a
/// plain field, macOS does not treat it as a credential field — so no AutoFill popover.
///
/// Trade-off vs. NSSecureTextField: we lose the OS "secure input" keystroke isolation.
/// For a local BYO-keys app that's an acceptable cost; the key is still masked on screen,
/// never written to disk/UserDefaults, never logged, and goes straight to the Keychain.
private struct MaskedKeyField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "paste key, press enter"
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = .labelColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingHead
        field.delegate = context.coordinator
        field.cell?.sendsActionOnEndEditing = false
        field.stringValue = String(repeating: "•", count: text.count)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let target = String(repeating: "•", count: text.count)
        if nsView.stringValue != target { nsView.stringValue = target }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: MaskedKeyField
        init(_ parent: MaskedKeyField) { self.parent = parent }

        /// Reconstruct the real value from the edit, using the caret position so that
        /// inserts, pastes, and mid-string deletes all map to the right characters —
        /// then re-mask the field so only bullets are ever shown.
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let shown = Array(field.stringValue)
            let newLen = shown.count
            let oldLen = parent.text.count
            let caret = field.currentEditor()?.selectedRange.location ?? newLen
            var real = Array(parent.text)

            if newLen > oldLen {                       // insertion / paste
                let count = newLen - oldLen
                let start = max(caret - count, 0)
                let chars = Array(shown[start..<caret])
                real.insert(contentsOf: chars, at: min(start, real.count))
            } else if newLen < oldLen {                // deletion
                let count = oldLen - newLen
                let start = min(caret, real.count)
                let end = min(start + count, real.count)
                real.removeSubrange(start..<end)
            } else if let a = shown.firstIndex(where: { $0 != "•" }) {
                // same length: a selection was replaced — splice the typed run in place
                var b = a
                while b < shown.count, shown[b] != "•" { b += 1 }
                let chars = Array(shown[a..<b])
                let lo = min(a, real.count), hi = min(b, real.count)
                real.replaceSubrange(lo..<hi, with: chars)
            }

            let newReal = String(real)
            parent.text = newReal
            field.stringValue = String(repeating: "•", count: newReal.count)
            field.currentEditor()?.selectedRange = NSRange(location: min(caret, newReal.count), length: 0)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - Plain text field (AppKit-backed, no AutoFill popup)

/// A normal (non-secure) text field backed by `NSTextField`. SwiftUI's `TextField`
/// triggers macOS's "Passwords…" AutoFill heuristic when programmatically focused;
/// a plain `NSTextField` does not. Used for the project name and the directive input.
private struct PlainTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var fontSize: CGFloat = 14
    var weight: NSFont.Weight = .regular
    var filter: ((String) -> String)? = nil
    var onSubmit: () -> Void = {}
    /// If set, pasting (⌘V) an image into the field hands the image here instead of
    /// pasting text. Text pastes still work normally.
    var onPasteImage: ((NSImage) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> PasteAwareTextField {
        let field = PasteAwareTextField()
        field.placeholderString = placeholder
        field.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        field.textColor = .labelColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.cell?.sendsActionOnEndEditing = false
        field.onPasteImage = onPasteImage
        return field
    }

    func updateNSView(_ nsView: PasteAwareTextField, context: Context) {
        nsView.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        nsView.onPasteImage = onPasteImage
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PlainTextField
        init(_ parent: PlainTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            var value = field.stringValue
            if let filter = parent.filter {
                let cleaned = filter(value)
                if cleaned != value { field.stringValue = cleaned; value = cleaned }
            }
            parent.text = value
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

/// An `NSTextField` that intercepts an image paste (⌘V). Paste of an `NSTextField` is
/// actually handled by the shared field editor, so we hook the ⌘V key equivalent: when
/// the field is being edited and the clipboard holds an image, capture it; otherwise fall
/// through so normal text paste still works.
final class PasteAwareTextField: NSTextField {
    var onPasteImage: ((NSImage) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let onPasteImage,
           currentEditor() != nil,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "v",
           let img = NSImage(pasteboard: NSPasteboard.general) {
            onPasteImage(img)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Multi-line composer (Enter sends, Shift+Enter newline)

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onPasteImage: ((NSImage) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> NSScrollView {
        let tv = PasteImageTextView()
        tv.delegate = context.coordinator
        tv.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.isRichText = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 2, height: 3)
        tv.allowsUndo = true
        tv.string = text
        tv.onPasteImage = onPasteImage
        tv.placeholderString = placeholder
        tv.textColor = .labelColor
        tv.identifier = NSUserInterfaceItemIdentifier("council.composer")

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .none
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? PasteImageTextView else { return }
        if tv.string != text { tv.string = text; tv.needsDisplay = true }
        tv.onPasteImage = onPasteImage
        tv.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: ComposerTextView
        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                // Shift+Enter → newline; plain Enter → send.
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

/// NSTextView that captures an image paste and draws a placeholder when empty.
final class PasteImageTextView: NSTextView {
    var onPasteImage: ((NSImage) -> Void)?
    var placeholderString: String = ""

    override func paste(_ sender: Any?) {
        if let onPasteImage, let img = NSImage(pasteboard: .general) { onPasteImage(img); return }
        super.paste(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, !placeholderString.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? .monospacedSystemFont(ofSize: 15, weight: .regular)
            ]
            placeholderString.draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height),
                                   withAttributes: attrs)
        }
    }
}

// MARK: - Settings

/// Appearance + the (now editable) system prompt + where conversations are saved.
private struct SettingsSheet: View {
    @Bindable var store: CouncilStore
    @Binding var appearance: String
    var engram: EngramService
    var onClose: () -> Void
    @State private var engramConnectError: String?

    /// Whether exported images carry the "made with Council" watermark. Default on (growth).
    @AppStorage("council.shareWatermark") private var shareWatermark = true
    /// Session layout: "flow" (one page) or "classic" (stage screens in the sidebar).
    @AppStorage("council.layout") private var layoutMode = "flow"
    /// Spend alert: notify once when all-time spend crosses this dollar threshold.
    @AppStorage("council.spendAlertOn") private var spendAlertOn = false
    @AppStorage("council.spendAlertAmt") private var spendAlertAmt = 10.0
    /// Mirror the chosen background tint so the sheet harmonizes with the app behind it.
    @AppStorage("council.bgTint") private var bgTintIndex = 0
    @AppStorage("council.liteMode") private var liteMode = false
    /// Local Ollama base URL — blank = localhost. Lets you point at Ollama on another machine.
    @AppStorage("council.ollamaHost") private var ollamaHost = ""
    @State private var ollamaTesting = false
    @State private var ollamaTestResult: EndpointTestResult? = nil
    /// Custom OpenAI-compatible endpoints (llama.cpp, LM Studio, vLLM, a second Ollama…), 2 slots.
    @AppStorage("council.custom1.name") private var custom1Name = ""
    @AppStorage("council.custom1.host") private var custom1Host = ""
    @AppStorage("council.custom2.name") private var custom2Name = ""
    @AppStorage("council.custom2.host") private var custom2Host = ""
    @State private var customTesting: Int? = nil
    @State private var customResults: [Int: EndpointTestResult] = [:]
    /// A council config staged for import, awaiting confirmation (it overwrites the live setup).
    @State private var pendingImport: CouncilConfig?
    /// A preset staged for "load" confirmation.
    @State private var pendingPreset: CouncilConfig?

    /// Settings categories shown in the left rail.
    enum Tab: String, CaseIterable, Identifiable {
        case models = "Models", deliberation = "Deliberation", councils = "Councils", app = "App"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .models: return "cube"
            case .deliberation: return "arrow.triangle.branch"
            case .councils: return "square.grid.2x2"
            case .app: return "gearshape"
            }
        }
    }
    @State private var tab: Tab = .models

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SETTINGS").font(Blue.serif(28)).foregroundStyle(Blue.ink).tracking(-0.5)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Blue.ink)
                        .frame(width: 32, height: 32)
                        .glassHover(corner: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close settings")
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)

            HStack(alignment: .top, spacing: 0) {
                // Left category rail.
                VStack(spacing: 4) {
                    ForEach(Tab.allCases) { t in
                        settingsTab(t)
                    }
                    Spacer()
                }
                .frame(width: 168)
                .padding(.horizontal, 12).padding(.top, 4)

                // Right content pane.
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch tab {
                        case .models:       modelsTab
                        case .deliberation: deliberationTab
                        case .councils:     councilsTab
                        case .app:          appTab
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 4).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: 640, height: 600)
        .background {
            ZStack {
                LinearGradient(colors: [
                    Color.adaptive(Color(red: 0.96, green: 0.96, blue: 0.97), Color(red: 0.10, green: 0.10, blue: 0.105)),
                    Color.adaptive(Color(red: 0.92, green: 0.92, blue: 0.94), Color(red: 0.06, green: 0.06, blue: 0.065))
                ], startPoint: .top, endPoint: .bottom)
                // Harmonize with the app's chosen background tint (plain blend — matches the main
                // backdrop and avoids the costly .color blend mode).
                if let s = Blue.tintStyle(bgTintIndex) {
                    Rectangle().fill(s).opacity(0.4)
                }
            }
        }
        .modifier(SettingsAlerts(store: store,
                                 pendingImport: $pendingImport, pendingPreset: $pendingPreset))
    }

    /// One row in the left category rail.
    private func settingsTab(_ t: Tab) -> some View {
        SettingsTabRow(tab: t, selected: tab == t) { tab = t }
    }

    // MARK: Grouped tabs

    private func priceLabel(_ p: LLMProvider) -> String {
        p.requiresAPIKey ? String(format: "$%g/$%g", p.pricePer1MInput, p.pricePer1MOutput) : "free"
    }

    /// Read-only providers reference (connection dot + price), shown in the Models tab.
    private var providersBoard: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                  alignment: .leading, spacing: 4) {
            ForEach(LLMProvider.selectable) { p in
                HStack(spacing: 7) {
                    Circle().fill(store.keyExists(p) ? Blue.ink : Color.clear)
                        .overlay(Circle().strokeBorder(Blue.glassStroke))
                        .frame(width: 6, height: 6)
                    Text(p.panelName).font(Blue.mono(9, .bold)).foregroundStyle(Blue.ink).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(priceLabel(p)).font(Blue.mono(8)).foregroundStyle(Blue.dim).lineLimit(1)
                }
                .padding(.vertical, 5).padding(.horizontal, 7)
            }
        }
    }

    /// Status line under an endpoint test — neutral on success, amber if empty, red on failure.
    @ViewBuilder private func ollamaResultLine(_ r: EndpointTestResult) -> some View {
        let (icon, text, color): (String, String, Color) = {
            switch r {
            case .ok(let n) where n > 0:
                return ("checkmark.circle", "Connected · \(n) model\(n == 1 ? "" : "s") found — they're in the model picker now.", Blue.ok)
            case .ok:
                return ("exclamationmark.triangle", "Reachable, but no models on that server yet.", Blue.warn)
            case .failed(let m):
                return ("xmark.circle", m, Blue.red)
            }
        }()
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(color)
            Text(text).font(Blue.mono(10)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One custom-endpoint slot: short name + base URL + per-slot test with inline result.
    @ViewBuilder private func customEndpointRow(slot: Int, name: Binding<String>, host: Binding<String>) -> some View {
        let provider: LLMProvider = slot == 1 ? .custom1 : .custom2
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                TextField("Custom \(slot)", text: name)
                    .textFieldStyle(.plain).font(Blue.mono(12)).foregroundStyle(Blue.ink)
                    .padding(.vertical, 9).padding(.horizontal, 10)
                    .frame(width: 120)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .help("Shown on the seat's panel")
                TextField("http://192.168.1.20:8080", text: host)
                    .textFieldStyle(.plain).font(Blue.mono(12)).foregroundStyle(Blue.ink)
                    .padding(.vertical, 9).padding(.horizontal, 10)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .onChange(of: host.wrappedValue) { customResults[slot] = nil }
                    .onSubmit { Task { await store.refreshModels(for: provider) } }
                Button {
                    customTesting = slot; customResults[slot] = nil
                    Task { let r = await store.testEndpoint(for: provider); customTesting = nil; customResults[slot] = r }
                } label: {
                    Text(customTesting == slot ? "TESTING…" : "TEST").font(Blue.mono(9, .bold)).tracking(1)
                        .foregroundStyle(Blue.ink)
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(customTesting != nil || host.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Test custom endpoint \(slot)")
            }
            if let r = customResults[slot] { ollamaResultLine(r) }
        }
    }

    @ViewBuilder private var modelsTab: some View {
        section("OLLAMA ENDPOINT") {
            Text("Where your local Ollama runs. Point it at Ollama on another machine on your network (e.g. a GPU box) — blank uses localhost.")
                .font(Blue.body(11)).foregroundStyle(Blue.sub)
                .fixedSize(horizontal: false, vertical: true)
            TextField("http://localhost:11434", text: $ollamaHost)
                .textFieldStyle(.plain).font(Blue.mono(12)).foregroundStyle(Blue.ink)
                .padding(.vertical, 9).padding(.horizontal, 10)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                .onChange(of: ollamaHost) { ollamaTestResult = nil }              // edited host → old result is stale
                .onSubmit { Task { await store.refreshModels(for: .ollama) } }    // Enter re-pulls the model list
            HStack(spacing: 10) {
                Button {
                    ollamaTesting = true; ollamaTestResult = nil
                    Task { let r = await store.testEndpoint(for: .ollama); ollamaTesting = false; ollamaTestResult = r }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: ollamaTesting ? "ellipsis" : "bolt.horizontal").font(.system(size: 10, weight: .bold))
                        Text(ollamaTesting ? "TESTING…" : "TEST CONNECTION").font(Blue.mono(9, .bold)).tracking(1)
                    }
                    .foregroundStyle(Blue.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(ollamaTesting)
                if !ollamaHost.isEmpty {
                    Button { ollamaHost = ""; ollamaTestResult = nil } label: {
                        Text("RESET TO LOCALHOST").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let r = ollamaTestResult { ollamaResultLine(r) }
        }
        section("CUSTOM ENDPOINTS") {
            Text("Any OpenAI-compatible server — llama.cpp, LM Studio, vLLM, or a second Ollama box. Set a URL and it joins the seat picker; TEST pulls its real model list.")
                .font(Blue.body(11)).foregroundStyle(Blue.sub)
                .fixedSize(horizontal: false, vertical: true)
            customEndpointRow(slot: 1, name: $custom1Name, host: $custom1Host)
            customEndpointRow(slot: 2, name: $custom2Name, host: $custom2Host)
        }
        section("PROVIDERS") {
            Text("Filled dot = a key is saved. Prices are per 1M tokens (input / output).")
                .font(Blue.body(11)).foregroundStyle(Blue.sub)
                .fixedSize(horizontal: false, vertical: true)
            providersBoard
        }
        section("SYSTEM PROMPT — ALL MODELS") {
            promptEditor($store.sharedSystemPrompt, placeholder: "Shared instruction…", tall: true)
            Button { store.sharedSystemPrompt = CouncilStore.defaultSystemPrompt } label: {
                Text("RESET TO DEFAULT").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.sub)
            }
            .buttonStyle(.plain)
        }
        section("PER-MODEL PROMPT (OPTIONAL)") {
            Text("Leave empty to use the shared prompt.")
                .font(Blue.body(11)).foregroundStyle(Blue.sub)
            ForEach(store.seats) { seat in
                promptEditor(seatBinding(seat),
                             placeholder: "— shared prompt —",
                             label: (seat.provider?.panelName ?? "Seat \(seat.id + 1)").uppercased())
            }
        }
        section("SAMPLING — PER MODEL (OPTIONAL)") {
            Text("Temperature trades focus for variety. Max tokens caps each reply. Leave on AUTO for the model's own default.")
                .font(Blue.body(11)).foregroundStyle(Blue.sub)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(store.seats) { seat in
                samplingControls(for: seat)
            }
        }
    }

    @ViewBuilder private var deliberationTab: some View {
        section("NEUTRAL CHAIR") {
            Text("An optional fourth model that runs divergence and synthesis — and wraps up debates — without ever answering the question itself. No position to defend, no debate it argued in. It spends that provider's credit for those calls.")
                .font(Blue.body(11)).foregroundStyle(Blue.sub)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                chairRow(nil, label: "None — an advisor synthesizes (default)")
                ForEach(chairChoices, id: \.self) { p in
                    Rectangle().fill(Blue.glassStroke).frame(height: 1)
                    chairRow(p, label: p.panelName)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
            if let chair = store.chairSeat, !store.isChairActive {
                Text("\(chair.provider?.panelName ?? "The chair") has no API key right now — an advisor synthesizes until it does.")
                    .font(Blue.mono(9)).foregroundStyle(Blue.red)
            }
            // A local chair is pinned to its provider's default model unless you say otherwise —
            // and for Ollama that default is usually NOT what the user actually pulled.
            if let chair = store.chairSeat, let p = chair.provider {
                HStack(spacing: 8) {
                    Text("MODEL").font(Blue.mono(9)).foregroundStyle(Blue.sub)
                    Menu {
                        ForEach(Array((store.providerModels[p] ?? p.modelOptions).prefix(60)), id: \.self) { m in
                            Button { store.setChairModel(m) } label: {
                                if m == chair.model { Label(m, systemImage: "checkmark") } else { Text(m) }
                            }
                        }
                    } label: {
                        Text(chair.model.isEmpty ? "default" : chair.model)
                            .font(Blue.mono(10)).foregroundStyle(Blue.ink)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                }
                .task(id: p) { await store.refreshModels(for: p) }
            }
            if chairChoices.isEmpty {
                Text("Connect a provider in Models — any connected one can chair.")
                    .font(Blue.mono(9)).foregroundStyle(Blue.dim)
            }
        }

        section("DIVERGENCE & SYNTHESIS MODEL") {
                        Text("These two are written by one model — it spends that provider's credit, and the analysis carries that model's lens.")
                            .font(Blue.body(11)).foregroundStyle(Blue.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        if store.isChairActive {
                            Text("The neutral chair writes these while it's set. If it can't run, the advisor you pick here writes them instead — and the stage says who did.")
                                .font(Blue.mono(9)).foregroundStyle(Blue.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(store.seats.enumerated()), id: \.element.id) { idx, seat in
                                Button { store.synthesizerSeatID = seat.id } label: {
                                    HStack {
                                        Text(seat.provider?.panelName ?? "Seat \(seat.id + 1)").font(Blue.mono(12)).foregroundStyle(Blue.ink)
                                        Spacer()
                                        if store.synthesizerSeatID == seat.id {
                                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Blue.ink)
                                        }
                                    }
                                    .padding(.vertical, 10).padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(store.synthesizerSeatID == seat.id ? Blue.glassBright : Color.clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if idx < store.seats.count - 1 {
                                    Rectangle().fill(Blue.glassStroke).frame(height: 1)
                                }
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                        .opacity(store.isChairActive ? 0.45 : 1)
                        .disabled(store.isChairActive)
                    }

        section("DEVIL'S ADVOCATE") {
            Text("One advisor steelmans the emerging consensus, then attacks it — mandated dissent in peer review. Off by default.")
                .font(Blue.body(11)).foregroundStyle(Blue.sub)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                advocateRow(id: -1, label: "None")
                Rectangle().fill(Blue.glassStroke).frame(height: 1)
                ForEach(Array(store.seats.enumerated()), id: \.element.id) { idx, seat in
                    advocateRow(id: seat.id, label: seat.provider?.panelName ?? "Seat \(seat.id + 1)")
                    if idx < store.seats.count - 1 {
                        Rectangle().fill(Blue.glassStroke).frame(height: 1)
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
        }
    }

    @ViewBuilder private var councilsTab: some View {
        section("COUNCILS") {
                        Text("A council is your seat lineup, personas, and sampling — saved as a shareable file. No API keys are included.")
                            .font(Blue.body(11)).foregroundStyle(Blue.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            councilButton("EXPORT…", filled: true) {
                                Exporter.saveCouncil(store.currentConfig(name: "My council"))
                            }
                            councilButton("IMPORT…", filled: false) {
                                Exporter.openCouncil { c in if let c { pendingImport = c } }
                            }
                        }
                        Text("PRESETS").font(Blue.mono(9, .bold)).tracking(2).foregroundStyle(Blue.dim)
                            .padding(.top, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(CouncilConfig.presets.enumerated()), id: \.element.id) { idx, preset in
                                Button { pendingPreset = preset } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(preset.name).font(Blue.mono(11, .bold)).foregroundStyle(Blue.ink)
                                            if let d = preset.detail {
                                                Text(d).font(Blue.body(10)).foregroundStyle(Blue.sub)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.down.circle").font(.system(size: 12)).foregroundStyle(Blue.sub)
                                    }
                                    .padding(.vertical, 9).padding(.horizontal, 11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if idx < CouncilConfig.presets.count - 1 {
                                    Rectangle().fill(Blue.glassStroke).frame(height: 1)
                                }
                            }
                        }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
        }
    }

    @ViewBuilder private var appTab: some View {
        section("LAYOUT") {
            Text("How a session reads. Flow is one page — analysis appears beneath the answers. Classic keeps every stage as its own screen in the sidebar.")
                .font(Blue.body(11)).foregroundStyle(Blue.sub)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                LayoutOption(label: "FLOW", icon: "rectangle.stack", value: "flow", layout: $layoutMode)
                LayoutOption(label: "CLASSIC", icon: "sidebar.left", value: "classic", layout: $layoutMode)
            }
        }
        section("APPEARANCE") {
            HStack(spacing: 0) {
                AppearanceOption(label: "LIGHT", value: "light", icon: "sun.max", appearance: $appearance)
                AppearanceOption(label: "DARK", value: "dark", icon: "moon", appearance: $appearance)
            }
        }
        section("UPDATES") {
            HStack(spacing: 8) {
                Text("Version").font(Blue.body(12)).foregroundStyle(Blue.sub)
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    .font(Blue.mono(12, .bold)).foregroundStyle(Blue.ink)
                    .textSelection(.enabled)
                Spacer()
            }
            // Engine attribution — the app is a thin shell over the open-source CouncilKit package.
            Text(CouncilKit.signature).font(Blue.mono(9)).foregroundStyle(Blue.dim)
            Toggle(isOn: Binding(
                get: { Updater.controller.updater.automaticallyChecksForUpdates },
                set: { Updater.controller.updater.automaticallyChecksForUpdates = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check for updates automatically")
                        .font(Blue.body(12)).foregroundStyle(Blue.ink)
                    Text("New versions install in-app — no need to revisit GitHub.")
                        .font(Blue.body(11)).foregroundStyle(Blue.dim)
                }
            }
            .toggleStyle(.switch).tint(Blue.accent)
            Button { Updater.controller.checkForUpdates(nil) } label: {
                Text("CHECK FOR UPDATES").font(Blue.mono(10, .bold)).tracking(1)
                    .foregroundStyle(Blue.ink)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Blue.glassBright, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        section("PERFORMANCE") {
            Toggle(isOn: $liteMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reduce glass for performance")
                        .font(Blue.body(12)).foregroundStyle(Blue.ink)
                    Text("Uses a lighter frosted material instead of real Liquid Glass. Turn on if scrolling feels heavy on your Mac.")
                        .font(Blue.body(11)).foregroundStyle(Blue.dim)
                }
            }
            .toggleStyle(.switch).tint(Blue.accent)
        }
        // Shown only when Engram is actually on this Mac (or already connected) — an integration
        // for people who have it, never an ad for people who don't.
        if engram.detected {
            section("ENGRAM") {
                Text("Engram is a local, shared memory for your AIs (same maker). Connect your Engram folder and journal decisions gain a “Remember in Engram” action — so your other AI tools can recall what you decided, and why. Local files only; nothing leaves this Mac.")
                    .font(Blue.body(11)).foregroundStyle(Blue.sub)
                    .fixedSize(horizontal: false, vertical: true)
                if engram.connected {
                    HStack(spacing: 8) {
                        Circle().fill(Blue.ok).frame(width: 6, height: 6)
                        Text("Connected").font(Blue.mono(11, .bold)).foregroundStyle(Blue.ink)
                        Spacer()
                        Button { engram.disconnect() } label: {
                            Text("DISCONNECT").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.sub)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .glassHover(corner: 8).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Running AI tools see new memories after they restart.")
                        .font(Blue.mono(9)).foregroundStyle(Blue.dim)
                } else {
                    Button { engramConnectError = engram.connect() } label: {
                        Text("CONNECT ENGRAM…").font(Blue.mono(10, .bold)).tracking(1)
                            .foregroundStyle(Blue.ink)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Blue.glassBright, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Pick your Engram folder once — Council keeps a scoped grant to write decision memories there")
                }
                if let engramConnectError {
                    Text(engramConnectError).font(Blue.mono(9)).foregroundStyle(Blue.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        section("SHARING") {
            Toggle(isOn: $shareWatermark) {
                Text("Show “made with Council” on exported images")
                    .font(Blue.body(12)).foregroundStyle(Blue.ink)
            }
            .toggleStyle(.switch).tint(Blue.accent)
        }
        section("SPEND ALERT") {
            Toggle(isOn: $spendAlertOn) {
                Text("Notify me once my total spend crosses a threshold")
                    .font(Blue.body(12)).foregroundStyle(Blue.ink)
            }
            .toggleStyle(.switch).tint(Blue.accent)
            .onChange(of: spendAlertOn) { _, on in
                if on {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                    CouncilStore.rearmSpendAlert()   // re-enabling should be able to fire again
                }
            }
            .onChange(of: spendAlertAmt) { _, _ in
                CouncilStore.rearmSpendAlert()        // a new threshold re-arms the one-shot
            }
            if spendAlertOn {
                HStack(spacing: 8) {
                    Text("Alert at").font(Blue.body(12)).foregroundStyle(Blue.sub)
                    Text("$").font(Blue.mono(12, .bold)).foregroundStyle(Blue.ink)
                    TextField("10", value: $spendAlertAmt, format: .number)
                        .textFieldStyle(.plain)
                        .font(Blue.mono(12, .bold)).foregroundStyle(Blue.ink)
                        .frame(width: 60)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.adaptive(.black.opacity(0.05), .black.opacity(0.22)),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    Text("total").font(Blue.body(12)).foregroundStyle(Blue.sub)
                    Spacer()
                }
                Text("Estimated spend across all sessions (you pay providers directly).")
                    .font(Blue.body(11)).foregroundStyle(Blue.dim)
            }
        }
        section("KEYBOARD SHORTCUTS") {
            shortcutRow("\u{2318}N", "New directive")
            shortcutRow("\u{2318}1 / \u{2318}2 / \u{2318}3", "Home / Roundtable / Journal")
            shortcutRow("\u{2318}[ / \u{2318}]", "Previous / next round")
            shortcutRow("\u{2318}E", "Copy session as markdown")
            shortcutRow("\u{21E7}\u{2318}E", "Save decision memo")
            shortcutRow("\u{2318},", "Settings")
            shortcutRow("\u{21A9}", "Focus the composer / send")
        }
        section("CONVERSATION STORAGE") {
            Text("Stored on this Mac — no cloud, no server.")
                .font(Blue.body(12)).foregroundStyle(Blue.sub)
            Text(store.conversationFileDisplayPath)
                .font(Blue.mono(10)).foregroundStyle(Blue.ink)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Button { store.revealConversationFolder() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("REVEAL IN FINDER").font(Blue.mono(10, .bold)).tracking(1)
                }
                .foregroundStyle(Blue.ink).padding(.horizontal, 14).padding(.vertical, 9).background(Blue.glassBright, in: RoundedRectangle(cornerRadius: 10, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    /// EXPORT / IMPORT button in the COUNCILS section.
    private func councilButton(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(Blue.mono(10, .bold)).tracking(1)
                .foregroundStyle(Blue.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .background(filled ? Blue.glassBright : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortcutRow(_ keys: String, _ what: String) -> some View {
        HStack(spacing: 10) {
            Text(keys).font(Blue.mono(10, .bold)).foregroundStyle(Blue.ink)
                .frame(width: 110, alignment: .leading)
            Text(what).font(Blue.body(11)).foregroundStyle(Blue.sub)
            Spacer()
        }
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Blue.mono(10, .bold)).tracking(2).foregroundStyle(Blue.sub)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // Neutral card (NO material — material sampled the warm desktop behind the sheet and
        // turned these cards brown). A flat adaptive lift keeps them clean in both modes.
        .background(Color.adaptive(.black.opacity(0.045), .white.opacity(0.05)),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
    }

    private func seatBinding(_ seat: Seat) -> Binding<String> {
        Binding(
            get: { store.seats.first { $0.id == seat.id }?.systemPrompt ?? "" },
            set: { store.setSeatPrompt($0, seatID: seat.id) }
        )
    }

    /// One row of the devil's-advocate picker (id -1 = none).
    /// Providers eligible to chair: connected AND actually offerable — `selectable` is the same
    /// gate the seat picker uses, so an unconfigured custom slot (no host set) can't be chosen as
    /// chair and then fail every call while Settings claims a chair is in charge.
    private var chairChoices: [LLMProvider] {
        _ = store.keyRevision
        return LLMProvider.selectable.filter { store.keyExists($0) }
    }

    @ViewBuilder private func chairRow(_ provider: LLMProvider?, label: String) -> some View {
        let isOn = provider == nil ? store.chairSeat == nil : store.chairSeat?.provider == provider
        Button { store.setChair(provider) } label: {
            HStack {
                Text(label).font(Blue.mono(12)).foregroundStyle(Blue.ink)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Blue.ink)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? Blue.glassBright : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "\(label), current chair" : label)
    }

    @ViewBuilder private func advocateRow(id: Int, label: String) -> some View {
        Button { store.devilsAdvocateSeatID = id } label: {
            HStack {
                Text(label).font(Blue.mono(12)).foregroundStyle(Blue.ink)
                Spacer()
                if store.devilsAdvocateSeatID == id {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Blue.ink)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(store.devilsAdvocateSeatID == id ? Blue.glassBright : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Temperature slider + max-tokens field for one seat. nil = AUTO (provider default).
    @ViewBuilder private func samplingControls(for seat: Seat) -> some View {
        let live = store.seats.first { $0.id == seat.id }
        let temp = live?.temperature
        let tempBinding = Binding<Double>(
            get: { temp ?? 1.0 },
            set: { store.setTemperature($0, seatID: seat.id) }
        )
        let maxBinding = Binding<String>(
            get: { live?.maxTokens.map(String.init) ?? "" },
            set: { store.setMaxTokens(Int($0.filter(\.isNumber)), seatID: seat.id) }
        )
        VStack(alignment: .leading, spacing: 7) {
            Text((seat.provider?.panelName ?? "Seat \(seat.id + 1)").uppercased())
                .font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.ink)

            HStack(spacing: 10) {
                Text("TEMP").font(Blue.mono(9)).foregroundStyle(Blue.sub)
                    .frame(width: 56, alignment: .leading)
                Slider(value: tempBinding, in: 0...2, step: 0.1).tint(Blue.ink)
                Text(temp == nil ? "AUTO" : String(format: "%.1f", temp ?? 1.0))
                    .font(Blue.mono(10)).foregroundStyle(temp == nil ? Blue.dim : Blue.ink)
                    .frame(width: 40, alignment: .trailing)
                Button { store.setTemperature(nil, seatID: seat.id) } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Blue.sub)
                }
                .buttonStyle(.plain).help("Reset to model default")
                .accessibilityLabel("Reset temperature to default")
            }

            HStack(spacing: 10) {
                Text("MAX TOK").font(Blue.mono(9)).foregroundStyle(Blue.sub)
                    .frame(width: 56, alignment: .leading)
                PlainTextField(text: maxBinding, placeholder: "auto", fontSize: 11,
                               filter: { String($0.filter(\.isNumber).prefix(6)) })
                    .frame(height: 16)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func promptEditor(_ text: Binding<String>, placeholder: String,
                                           label: String? = nil, tall: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let label { Text(label).font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.ink) }
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder).font(Blue.body(12)).foregroundStyle(Blue.dim)
                        .padding(.horizontal, 9).padding(.vertical, 10).allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(Blue.body(12)).foregroundStyle(Blue.ink)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .frame(height: tall ? 96 : 60)
            }
            .background(Color.adaptive(.black.opacity(0.05), .black.opacity(0.22)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
        }
    }
}

private struct SettingsAlerts: ViewModifier {
    let store: CouncilStore
    @Binding var pendingImport: CouncilConfig?
    @Binding var pendingPreset: CouncilConfig?
    func body(content: Content) -> some View {
        content
        .alert("Load this council?",
               isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
               presenting: pendingImport) { config in
            Button("Load") { store.applyConfig(config); pendingImport = nil }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: { config in
            Text("“\(config.name)” will replace your current seats, personas, and sampling. Your API keys stay untouched.")
        }
        .alert("Load preset?",
               isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } }),
               presenting: pendingPreset) { preset in
            Button("Load") { store.applyConfig(preset); pendingPreset = nil }
            Button("Cancel", role: .cancel) { pendingPreset = nil }
        } message: { preset in
            Text("“\(preset.name)” will replace your current seats and personas. Keys for any models you've already set up are reused.")
        }
    }
}

/// One row in the Settings left rail. Glass pill shows when selected OR hovered.
private struct SettingsTabRow: View {
    let tab: SettingsSheet.Tab
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon).font(.system(size: 13)).frame(width: 18)
                Text(tab.rawValue).font(Blue.mono(11, .bold)).tracking(0.5)
                Spacer()
            }
            .foregroundStyle(Blue.ink)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Blue.glassBright))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .opacity(selected ? 1 : (hovered ? 0.6 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isOver in withAnimation(Motion.quick) { hovered = isOver } }
    }
}

/// One session-layout choice (Settings → App → Layout). Same visual language as the
/// appearance picker — glow on hover, steady glow when selected.
private struct LayoutOption: View {
    let label: String
    let icon: String
    let value: String
    @Binding var layout: String
    @State private var hovered = false

    var body: some View {
        let on = layout == value
        let lit = on || hovered
        return Button {
            withAnimation(Motion.view) { layout = value }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 22, weight: lit ? .bold : .light))
                Text(label).font(Blue.mono(13, .bold)).tracking(3)
            }
            .foregroundStyle(lit ? Blue.ink : Blue.dim)
            .shadow(color: lit ? Blue.ink.opacity(0.4) : .clear, radius: lit ? 12 : 0)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .contentShape(Rectangle())
            .cursorGlow(selected: on)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(Motion.quick, value: hovered)
    }
}

/// One appearance choice. The glow follows the cursor on hover (via `cursorGlow`); when the
/// option is selected and not hovered, the glow rests at the top as a steady indicator.
private struct AppearanceOption: View {
    let label: String
    let value: String
    let icon: String
    @Binding var appearance: String
    @State private var hovered = false

    var body: some View {
        let on = appearance == value
        let lit = on || hovered
        return Button {
            withAnimation(Motion.view) { appearance = value }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 22, weight: lit ? .bold : .light))
                Text(label).font(Blue.mono(13, .bold)).tracking(3)
            }
            .foregroundStyle(lit ? Blue.ink : Blue.dim)
            .shadow(color: lit ? Blue.ink.opacity(0.4) : .clear, radius: lit ? 12 : 0)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .contentShape(Rectangle())
            .cursorGlow(selected: on)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(Motion.quick, value: hovered)
    }
}

/// Box that fills up (loading / linking) instead of a spinner.
private struct FillBar: View {
    let once: Bool
    @State private var p: CGFloat = 0
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().stroke(Blue.ink, lineWidth: 2)
                Rectangle().fill(Blue.ink.opacity(0.85)).frame(width: g.size.width * p)
            }
        }
        .frame(height: 22)
        .onAppear {
            if once { withAnimation(.easeInOut(duration: 1.1)) { p = 1 } }
            else { withAnimation(Motion.pulse.repeatForever(autoreverses: true)) { p = 1 } }
        }
    }
}

/// A blinking block caret shown at the tail of a streaming answer — terminal feel.
/// Lower-right triangle — used to paint half of a two-color swatch (the other half shows underneath).
private struct DiagonalSplit: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Diagonal slash — marks the "None" swatch as "no tint / default".
private struct Slash: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.22, y: r.maxY - r.height * 0.22))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.22, y: r.minY + r.height * 0.22))
        return p
    }
}

/// One background-tint swatch in the color rail. Grows on hover (so it reads as selectable) and
/// wears a ring when active. None = slashed outline; one color = solid; two colors = a split disc
/// (half/half) so it's obvious it's a mix.
private struct ColorSwatch: View {
    let index: Int
    var dot: CGFloat = 18
    var cell: CGFloat = 30
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    @ViewBuilder private var fill: some View {
        let colors = Blue.bgTints[index].colors
        if colors.isEmpty {
            Circle().fill(Color.clear).overlay(Slash().stroke(Blue.dim, lineWidth: 1.5))
        } else if colors.count == 1 {
            Circle().fill(colors[0])
        } else {
            ZStack {
                Rectangle().fill(colors[0])
                DiagonalSplit().fill(colors[1])
            }
            .clipShape(Circle())
        }
    }

    var body: some View {
        Button(action: action) {
            fill
                .frame(width: dot, height: dot)
                .overlay(Circle().strokeBorder(selected ? Blue.ink : Blue.glassStroke,
                                               lineWidth: selected ? 2 : 1))
                .scaleEffect(hovered ? 1.35 : (selected ? 1.1 : 1.0))
                .frame(maxWidth: .infinity)
                .frame(height: cell)                 // full-cell hit area — easy to click
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Blue.bgTints[index].name)
        .accessibilityLabel("Background tint: \(Blue.bgTints[index].name)")
        .onHover { h in withAnimation(Motion.quick) { hovered = h } }
    }
}

/// Ambient "three advisors" motif — three orbs slowly orbiting while breathing in and out
/// (converge → diverge), embodying the council. Pure decoration; drives the home hero's life.
private struct AdvisorOrbs: View {
    /// Animate ONLY while the hero is hovered. A continuous TimelineView never lets the app idle,
    /// which made everything (especially scrolling) janky — so the orbs rest static and come alive
    /// when you actually look at them.
    var animate: Bool
    var body: some View {
        Group {
            if animate {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                    orbs(at: ctx.date.timeIntervalSinceReferenceDate)
                }
            } else {
                orbs(at: 0)   // static resting pose
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func orbs(at t: Double) -> some View {
        let r = 13.0 + sin(t * 0.7) * 9.0          // breathe: converge ↔ diverge
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let a = Double(i) / 3.0 * 2.0 * .pi + t * 0.45   // slow rotation
                Circle()
                    .fill(Blue.ink.opacity(0.9 - Double(i) * 0.14))
                    .frame(width: 13, height: 13)
                    .offset(x: CGFloat(cos(a) * r), y: CGFloat(sin(a) * r))
            }
        }
        .frame(width: 76, height: 76)
    }
}

/// The home hero — the living top of the dashboard. The ambient orbs + a rotating example directive
/// (click to start it) + a rotating ethos line. Gives the otherwise-static dashboard a pulse.
private struct HomeHero: View {
    var onPick: (String) -> Void
    @State private var exIndex = 0
    @State private var ethIndex = 0
    @State private var heroHover = false   // orbs animate only while the hero is hovered

    private let examples = [
        "Should I take the job offer or keep looking?",
        "How should I prioritize my week?",
        "What am I missing in this plan?",
        "Is now a good time to make this purchase, or should I wait?",
        "Should I learn a new skill or go deeper on one I have?",
        "Rewrite this paragraph to be sharper and shorter.",
        "What are the trade-offs of renting versus buying?",
        "How do I give difficult feedback without burning the bridge?",
        "Should I focus on one project or keep several going?",
        "What would make this idea stronger?",
        "How do I structure this decision I'm stuck on?",
        "What questions should I be asking that I'm not?",
        "Is it better to specialize or stay a generalist?",
        "How can I make this message clearer and more persuasive?",
        "What are the strongest arguments against my current plan?",
        "Should I automate this or just do it manually for now?",
        "How do I weigh a stable option against a riskier one?",
        "What's a reasonable way to split shared costs fairly?",
        "How should I spend the first 90 days in a new role?",
        "Is this goal realistic for the time I have?",
        "What are the second-order effects of this choice?",
        "How do I say no to this without damaging the relationship?",
        "Should I ship the simple version now or wait for the full one?",
        "What's the best way to learn this topic from scratch?",
        "How do I tell if this is worth my time?",
        "What would I regret not trying a year from now?",
        "How should I prepare for this conversation?",
        "Is this feedback worth acting on, or should I let it go?",
        "What's a fair price to ask for this?",
        "How do I break this big task into manageable steps?",
        "Should I delegate this or keep it myself?",
        "What assumptions am I making that might be wrong?",
        "How do I balance speed and quality here?",
        "What's the simplest version of this that still works?",
        "How do I decide between two good options?",
        "What's the risk I'm underestimating?",
        "How can I make this routine easier to stick to?",
        "Should I keep investing in this or cut my losses?",
        "How do I make a strong first impression here?",
        "What would an outsider notice about this right away?",
        "How do I phrase this so it lands well?",
        "Is this the right problem to be solving?",
        "How should I think about this trade-off?",
        "What's a good way to test this before committing?",
        "How do I stay focused when everything feels urgent?",
        "What would make this plan more resilient?",
        "Should I optimize this now or leave it for later?",
        "How do I get unstuck on this?",
        "What's the honest case for and against this?",
        "How do I know when this is good enough?",
    ]
    private let ethos = [
        "Disagreement is the signal.",
        "Many minds answer — you decide.",
        "Blind peer review keeps them honest.",
        "One question, several lenses.",
        "The council never picks a winner for you.",
    ]

    var body: some View {
        HStack(spacing: 18) {
            AdvisorOrbs(animate: heroHover)
                .frame(width: 76, height: 76)
                .contentShape(Rectangle())
                .onHover { isOver in heroHover = isOver }   // animate only while the cursor is on the orbs
            VStack(alignment: .leading, spacing: 7) {
                Text("COUNCIL").font(Blue.mono(17, .bold)).tracking(6).foregroundStyle(Blue.ink)
                Button { onPick(examples[exIndex]) } label: {
                    HStack(spacing: 9) {
                        Text("“\(examples[exIndex])”")
                            .font(Blue.body(14)).foregroundStyle(Blue.sub)
                            .lineLimit(1).truncationMode(.tail)
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Blue.sub)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(exIndex)
                .transition(.opacity)
                .help("Start a directive with this question")
                Text(ethos[ethIndex])
                    .font(Blue.mono(10)).tracking(1).foregroundStyle(Blue.dim)
                    .id(100 + ethIndex)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(corner: 20)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                withAnimation(.easeInOut(duration: 0.5)) {
                    exIndex = (exIndex + 1) % examples.count
                    ethIndex = (ethIndex + 1) % ethos.count
                }
            }
        }
    }
}

/// Insertion transition: focuses in out of a blur while scaling up — used for the onboarding card.
private struct RevealBlur: ViewModifier {
    let p: Double   // 0 = hidden, 1 = shown
    func body(content: Content) -> some View {
        content
            .blur(radius: (1 - p) * 22)          // match the COUNCIL wordmark's blur-focus feel
            .scaleEffect(0.84 + p * 0.16)
            .offset(y: (1 - p) * 14)
            .opacity(p)
    }
}
private extension AnyTransition {
    static var revealBlur: AnyTransition { .modifier(active: RevealBlur(p: 0), identity: RevealBlur(p: 1)) }
}

/// The CONTINUE button. Not blue — on hover it simply fills solid black, label flips to white.
private struct OnboardingEnterButton: View {
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("CONTINUE")
                .font(Blue.mono(11, .bold)).tracking(3)
                .foregroundStyle(hovered ? .white : Blue.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hovered ? Color.black : Blue.glassBright)
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.quick) { hovered = h } }
    }
}

/// First-run onboarding — shown once (gated by @AppStorage "council.didOnboard"). Two beats:
/// (1) just the COUNCIL wordmark fades up over a frosted backdrop; (2) tapping anywhere reveals
/// the full explainer card. Lowers BYO-key friction ("one key is enough"). No canvas clutter.
private struct OnboardingCard: View {
    var dismiss: () -> Void
    @State private var appeared = false   // initial frost + wordmark fade
    @State private var revealed = false   // false = wordmark only, true = full card

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("·").font(Blue.mono(12, .bold)).foregroundStyle(Blue.ink)
            Text(text).font(Blue.body(12)).foregroundStyle(Blue.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        ZStack {
            // Frosted, dimmed backdrop — the whole app blurs behind. Tap to advance / dismiss.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
                .opacity(appeared ? 1 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if revealed { dismiss() }
                    else { withAnimation(Motion.cinematic) { revealed = true } }   // same slow, cinematic feel as the COUNCIL reveal
                }

            if !revealed {
                // BEAT 1 — just the wordmark + a quiet hint.
                VStack(spacing: 16) {
                    Text("COUNCIL")
                        .font(Blue.mono(34, .bold)).tracking(12).foregroundStyle(Blue.ink)
                    Text("tap anywhere to begin")
                        .font(Blue.mono(10)).tracking(3).foregroundStyle(Blue.dim)
                }
                .scaleEffect(appeared ? 1 : 0.82)
                .blur(radius: appeared ? 0 : 20)
                .offset(y: appeared ? 0 : 12)
                .opacity(appeared ? 1 : 0)
                .transition(.opacity.combined(with: .scale(scale: 1.08)))
            } else {
                // BEAT 2 — the full explainer card.
                VStack(alignment: .leading, spacing: 0) {
                    Text("COUNCIL").font(Blue.mono(13, .bold)).tracking(5).foregroundStyle(Blue.ink)
                    Text("Parallel answers. Honest disagreement. Your call.")
                        .font(Blue.body(13)).foregroundStyle(Blue.sub)
                        .padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 11) {
                        bullet("Ask once — your advisors answer in parallel, then critique each other.")
                        bullet("Bring your own API keys. They stay in your Mac's Keychain — never sent anywhere but the model.")
                        bullet("100% local. No account, no server, no telemetry.")
                    }
                    .padding(.top, 20)

                    Text("One key is enough to begin — pick a model in any panel to start.")
                        .font(Blue.mono(11)).foregroundStyle(Blue.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)

                    OnboardingEnterButton(action: dismiss)
                        .padding(.top, 22)
                }
                .padding(28)
                .frame(width: 420, alignment: .leading)
                .glassPanel(corner: 24)
                .transition(.revealBlur)
            }
        }
        .onAppear {
            // Slow, cinematic first reveal of the COUNCIL wordmark.
            withAnimation(Motion.cinematic.delay(0.1)) { appeared = true }
        }
        // Esc dismisses (from either beat).
        .background {
            Button("", action: dismiss).keyboardShortcut(.escape, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
        }
    }
}

private struct StreamingCaret: View {
    // Static on purpose: the growing text IS the liveness signal. A repeatForever blink kept the
    // compositor from ever idling between streaming commits (part of the RenderBox stall).
    var body: some View {
        Rectangle().fill(Blue.ink)
            .frame(width: 7, height: 14)
            .opacity(0.7)
            .accessibilityHidden(true)
    }
}

/// A clean, screenshot-worthy card used to export a divergence/synthesis as a shareable image.
/// Monochrome, current-theme, with a small "made with Council" watermark (toggleable).
private struct ShareCard: View {
    let title: String
    let via: String?
    let question: String
    let markdown: String
    let watermark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("COUNCIL").font(Blue.serif(26)).foregroundStyle(Blue.ink).tracking(-0.5)
                Spacer()
                Text(via != nil ? "\(title) · VIA \(via!.uppercased())" : title)
                    .font(Blue.mono(10, .bold)).tracking(2).foregroundStyle(Blue.sub)
            }
            if !question.isEmpty {
                Text(question).font(Blue.body(15)).foregroundStyle(Blue.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Blue.glassStroke).frame(height: 1)
            MarkdownView(text: markdown, baseSize: 14).equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
            if watermark {
                HStack {
                    Spacer()
                    Text("made with Council").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                }
                .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(width: 900, alignment: .leading)
        .background(Blue.paper)
    }
}

private struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

#Preview {
    ContentView(store: CouncilStore())
}
