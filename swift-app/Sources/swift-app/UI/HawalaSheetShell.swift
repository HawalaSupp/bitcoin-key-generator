import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Hawala Overlay Shell
// Reusable ZStack overlay: dark backdrop + glass card + silk shimmer + header.
// Use for small/medium views that replace .sheet() presentation.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct HawalaOverlayShell<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var closeHovered = false

    var body: some View {
        ZStack {
            // ── Backdrop ──
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // ── Glass Card ──
            VStack(spacing: 0) {
                headerBar
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        content()
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
            .frame(width: width, height: height)
            .background(cardBackground)
            .overlay(cardStroke)
            .shadow(color: .black.opacity(0.5), radius: 50, y: 25)
            .scaleEffect(cardScale)
            .opacity(contentOpacity)
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismiss)
        )
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                silkPhase = 1.5
            }
        }
    }

    // ── Header ──
    private var headerBar: some View {
        ZStack {
            Text(title.uppercased())
                .font(.clashGroteskMedium(size: 14))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))

            HStack {
                Spacer()
                Button(action: dismiss) {
                    Circle()
                        .fill(closeHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // ── Glass background + silk shimmer ──
    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.0), .white.opacity(0.02), .white.opacity(0.0)],
                        startPoint: UnitPoint(x: silkPhase - 0.3, y: 0),
                        endPoint: UnitPoint(x: silkPhase + 0.3, y: 1)
                    )
                )
        }
    }

    // ── Border stroke ──
    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.10), .white.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 1
            )
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Hawala Sheet Shell
// For views that stay as .sheet() — provides the same glass interior
// without the backdrop (the system sheet chrome handles that).
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct HawalaSheetShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var contentOpacity: Double = 0
    @State private var silkPhase: CGFloat = 0
    @State private var closeHovered = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    content()
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .frame(width: width, height: height)
        .background(
            ZStack {
                Color(red: 0.10, green: 0.10, blue: 0.12)
                    .ignoresSafeArea()
                LinearGradient(
                    colors: [.white.opacity(0.0), .white.opacity(0.02), .white.opacity(0.0)],
                    startPoint: UnitPoint(x: silkPhase - 0.3, y: 0),
                    endPoint: UnitPoint(x: silkPhase + 0.3, y: 1)
                )
                .ignoresSafeArea()
            }
        )
        .opacity(contentOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                contentOpacity = 1
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                silkPhase = 1.5
            }
        }
    }

    private var headerBar: some View {
        ZStack {
            Text(title.uppercased())
                .font(.clashGroteskMedium(size: 14))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))

            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(closeHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}
