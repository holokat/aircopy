import SwiftUI

// MARK: - "Add a Mac" pairing sheet
//
// AirDrop-style radar that surfaces nearby Macs from the live multipeer
// session. Pixel-for-pixel re-creation of the design handoff. All colors and
// fonts come from the shared `ACColor` / `ACFont` tokens so the surface stays
// consistent with the rest of the redesign.

struct ACAddMacSheet: View {
    @EnvironmentObject var coordinator: AirCopyCoordinator
    @EnvironmentObject var toast: ACToastCenter
    @Binding var isPresented: Bool

    // 300 x 300 radar coordinate space; center tile sits at (150, 150).
    private let radarSize: CGFloat = 300
    private let center = CGPoint(x: 150, y: 150)

    // Deterministic placement points for up to ~5 found Macs.
    private let foundPoints: [CGPoint] = [
        CGPoint(x: 150, y: 42),
        CGPoint(x: 252, y: 214),
        CGPoint(x: 50, y: 206),
        CGPoint(x: 70, y: 90),
        CGPoint(x: 230, y: 250),
    ]

    private var foundDevices: [PeerDeviceState] {
        coordinator.peerDevices
            .filter { $0.trustState != .blocked && ($0.isDiscovered || $0.trustState == .trusted) }
            .prefix(foundPoints.count)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .frame(height: 1)
                .overlay(ACColor.border06)
            body(found: foundDevices)
        }
        .frame(width: 440)
        .background(ACColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ACColor.border12, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 40, x: 0, y: 24)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Add a Mac")
                .font(ACFont.sans(14, weight: .semibold))
                .foregroundStyle(ACColor.ink)
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(ACColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(ACColor.controlTrack, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 52)
    }

    // MARK: - Body

    private func body(found: [PeerDeviceState]) -> some View {
        VStack(spacing: 0) {
            ACRadarView(
                size: radarSize,
                center: center,
                found: found,
                points: foundPoints,
                onTap: handleTap(_:)
            )
            .frame(width: radarSize, height: radarSize)

            statusLine
                .padding(.top, 18)

            Text("Tap a Mac to pair. Both Macs need AirCopy open on the same network.")
                .font(ACFont.sans(12))
                .foregroundStyle(ACColor.textTertiary)
                .lineSpacing(12 * 0.5)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.horizontal, 8)
        }
        .padding(.top, 14)
        .padding(.horizontal, 24)
        .padding(.bottom, 26)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            ACBreathingDot()
            Text("Searching for nearby Macs…")
                .font(ACFont.sans(13))
                .foregroundStyle(ACColor.textSecondary2)
        }
    }

    // MARK: - Actions

    private func handleTap(_ device: PeerDeviceState) {
        if device.trustState == .trusted {
            toast.show("\(device.displayName) is already synced", accent: ACColor.success)
        } else {
            coordinator.trustPeer(device.id)
            toast.show("Pairing with \(device.displayName)…", accent: ACColor.accent)
        }
    }
}

// MARK: - Radar

private struct ACRadarView: View {
    let size: CGFloat
    let center: CGPoint
    let found: [PeerDeviceState]
    let points: [CGPoint]
    let onTap: (PeerDeviceState) -> Void

    private let period: Double = 3.4

    @State private var sweepAngle: Angle = .degrees(0)

    var body: some View {
        ZStack {
            // Concentric ring circles (diameters 300 / 200 / 100).
            ForEach([300.0, 200.0, 100.0], id: \.self) { diameter in
                Circle()
                    .strokeBorder(ACColor.accentSoft12, lineWidth: 1)
                    .frame(width: diameter, height: diameter)
                    .position(center)
            }

            // Rotating conic sweep, clipped to the radar circle.
            AngularGradient(
                gradient: Gradient(stops: [
                    .init(color: ACColor.accentSoft16, location: 0.0),
                    .init(color: Color(hex: 0x0A6CFF, alpha: 0.0), location: 0.65),
                    .init(color: Color(hex: 0x0A6CFF, alpha: 0.0), location: 1.0),
                ]),
                center: .center
            )
            .frame(width: size, height: size)
            .clipShape(Circle())
            .rotationEffect(sweepAngle)
            .position(center)

            // Two pulsing radar rings (one offset by half the period).
            ACPulseRing(period: period, delay: 0)
                .position(center)
            ACPulseRing(period: period, delay: period / 2)
                .position(center)

            // Found Macs around the radar.
            ForEach(Array(found.enumerated()), id: \.element.id) { index, device in
                ACFoundTile(device: device, index: index) {
                    onTap(device)
                }
                .position(points[min(index, points.count - 1)])
            }

            // Center tile = this Mac. Sits above the sweep.
            ACCenterTile()
                .position(center)
                .zIndex(10)
        }
        .frame(width: size, height: size)
        .onAppear {
            sweepAngle = .degrees(0)
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                sweepAngle = .degrees(360)
            }
        }
    }
}

// MARK: - Center tile (this Mac)

private struct ACCenterTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(ACColor.darkTile)
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white)
            )
            .shadow(color: ACColor.accent.opacity(0.35), radius: 18, x: 0, y: 6)
    }
}

// MARK: - Found tile

private struct ACFoundTile: View {
    let device: PeerDeviceState
    let index: Int
    let onTap: () -> Void

    @State private var appeared = false
    @State private var isHovering = false

    private var isSynced: Bool { device.trustState == .trusted }

    var body: some View {
        VStack(spacing: 6) {
            tile
            VStack(spacing: 2) {
                Text(device.displayName)
                    .font(ACFont.sans(10.5, weight: .medium))
                    .foregroundStyle(ACColor.textMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color.white.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                Text(isSynced ? "Synced" : "Tap to pair")
                    .font(ACFont.sans(9, weight: .semibold))
                    .foregroundStyle(isSynced ? ACColor.successText : ACColor.textTertiary)
            }
        }
        .frame(width: 96)
        .scaleEffect(appeared ? (isHovering ? 1.04 : 1.0) : 0.6)
        .opacity(appeared ? 1 : 0)
        .onHover { isHovering = $0 }
        .onAppear {
            withAnimation(
                .spring(response: 0.45, dampingFraction: 0.7)
                    .delay(0.12 * Double(index))
            ) {
                appeared = true
            }
        }
        .onTapGesture(perform: onTap)
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white)
            .frame(width: 48, height: 48)
            .overlay(
                Image(systemName: device.deviceSymbolName)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isSynced ? ACColor.successText : ACColor.ink)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tileBorder, lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                if isSynced {
                    checkBadge
                        .offset(x: 4, y: 4)
                }
            }
    }

    private var tileBorder: Color {
        if isSynced {
            return Color(hex: 0x22C55E, alpha: 0.55)
        }
        return isHovering ? ACColor.accent : ACColor.border12
    }

    private var checkBadge: some View {
        Circle()
            .fill(ACColor.success)
            .frame(width: 19, height: 19)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            )
            .overlay(
                Circle().strokeBorder(Color.white, lineWidth: 2)
            )
    }
}

// MARK: - Pulse ring

private struct ACPulseRing: View {
    let period: Double
    let delay: Double

    @State private var animating = false

    var body: some View {
        Circle()
            .strokeBorder(Color(hex: 0x0A6CFF, alpha: 0.4), lineWidth: 1.5)
            .frame(width: 90, height: 90)
            .scaleEffect(animating ? 2.1 : 0.3)
            .opacity(animating ? 0 : 1)
            .onAppear {
                withAnimation(
                    .easeOut(duration: period)
                        .repeatForever(autoreverses: false)
                        .delay(delay)
                ) {
                    animating = true
                }
            }
    }
}

// MARK: - Breathing status dot

private struct ACBreathingDot: View {
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(ACColor.accent)
            .frame(width: 7, height: 7)
            .scaleEffect(breathing ? 1.25 : 0.85)
            .opacity(breathing ? 1 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}
