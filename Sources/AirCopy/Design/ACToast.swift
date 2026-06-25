import SwiftUI

// Bottom-center dark pill toast that auto-hides (~1.7s), matching the design.
@MainActor
final class ACToastCenter: ObservableObject {
    @Published var message: String?
    @Published var accent: Color = ACColor.success

    private var token = 0

    func show(_ message: String, accent: Color = ACColor.success) {
        self.message = message
        self.accent = accent
        token += 1
        let current = token
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            guard let self, self.token == current else { return }
            withAnimation(.easeOut(duration: 0.35)) { self.message = nil }
        }
    }
}

struct ACToastOverlay: View {
    @ObservedObject var toast: ACToastCenter

    var body: some View {
        VStack {
            Spacer()
            if let message = toast.message {
                HStack(spacing: 9) {
                    Circle()
                        .fill(toast.accent)
                        .frame(width: 8, height: 8)
                    Text(message)
                        .font(ACFont.sans(13.5, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.leading, 14)
                .padding(.trailing, 18)
                .padding(.vertical, 12)
                .background(ACColor.ink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 22, x: 0, y: 16)
                .padding(.bottom, 48)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: toast.message)
        .allowsHitTesting(false)
    }
}
