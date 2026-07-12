import SwiftUI
import CouncilKit

// The empty-state welcome: a calm, slowly breathing orb over the session canvas when the council
// is connected but nothing has been asked yet. Replaces three empty "Awaiting directive." panels
// with one quiet invitation. The composer below stays the way in; CONFIGURE reveals the panels.

struct OrbWelcome: View {
    var onConfigure: () -> Void
    @State private var breathing = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            orb
            Spacer().frame(height: 44)
            Text("Ask your council.")
                .font(Blue.body(24, .medium))
                .foregroundStyle(Blue.ink)
            Spacer().frame(height: 10)
            Text("One question, several minds — answers, blind peer review, and where they disagree.")
                .font(Blue.body(13))
                .foregroundStyle(Blue.sub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer().frame(height: 18)
            Text("Type below to begin")
                .font(Blue.mono(11)).tracking(0.6)
                .foregroundStyle(Blue.dim)
            Spacer()
            Button(action: onConfigure) {
                Text("CONFIGURE COUNCIL")
                    .font(Blue.mono(10, .medium)).tracking(1.4)
                    .foregroundStyle(Blue.dim)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }

    /// Layered soft circles around the single accent — no hard edges, a 5.5s breath.
    private var orb: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Blue.accent.opacity(0.32), .clear],
                                     center: .center, startRadius: 8, endRadius: 130))
                .frame(width: 260, height: 260)
                .blur(radius: 18)
                .scaleEffect(breathing ? 1.08 : 0.94)
            Circle()
                .fill(RadialGradient(colors: [Blue.accent.opacity(0.5), Blue.accent.opacity(0.06)],
                                     center: .center, startRadius: 2, endRadius: 62))
                .frame(width: 120, height: 120)
                .blur(radius: 6)
                .scaleEffect(breathing ? 1.05 : 0.97)
            Circle()
                .strokeBorder(Blue.glassStroke, lineWidth: 1)
                .frame(width: 152, height: 152)
                .scaleEffect(breathing ? 1.03 : 0.98)
                .opacity(breathing ? 0.9 : 0.5)
        }
        .drawingGroup()   // rasterize the blurred layers once; the breath animates a cheap texture transform
        .frame(height: 260)
        .accessibilityHidden(true)
    }
}
