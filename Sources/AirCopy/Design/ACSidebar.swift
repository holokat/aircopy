import SwiftUI

struct ACSidebarDevice: Identifiable {
    let id: String
    let name: String
    let isThis: Bool
    let symbol: String
    let syncOn: Bool
    let clipCount: Int
}

struct ACSidebar: View {
    let devices: [ACSidebarDevice]
    let selectedDeviceID: String?
    let syncShort: String
    let onSelect: (String) -> Void
    let onToggle: (String) -> Void
    let onAddMac: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Devices")
                    .font(ACFont.sans(10.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(ACColor.textTertiary)
                Spacer()
                Text(syncShort)
                    .font(ACFont.sans(10.5))
                    .foregroundStyle(ACColor.textTertiary2)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(devices) { device in
                        deviceRow(device)
                    }
                }
            }

            Spacer(minLength: 18)

            Button(action: onAddMac) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    Text("Add a Mac").font(ACFont.sans(12.5, weight: .medium))
                }
                .foregroundStyle(ACColor.textSecondary2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(ACColor.border18)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(width: 240)
        .background(ACColor.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(ACColor.border08).frame(width: 1) }
    }

    private func deviceRow(_ device: ACSidebarDevice) -> some View {
        let active = selectedDeviceID == device.id
        let nameColor: Color = device.syncOn ? (active ? ACColor.accent : ACColor.ink) : Color(hex: 0xA8ACB4)
        let iconColor: Color = device.syncOn ? (active ? ACColor.accent : ACColor.textSecondary) : Color(hex: 0xB4B8C0)

        return Button {
            onSelect(device.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: device.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(iconColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 7) {
                        Text(device.name)
                            .font(ACFont.sans(13, weight: .medium))
                            .foregroundStyle(nameColor)
                            .lineLimit(1)
                        if device.isThis {
                            Text("THIS")
                                .font(ACFont.sans(8.5, weight: .semibold))
                                .tracking(0.3)
                                .foregroundStyle(ACColor.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(ACColor.accentSoft12, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(device.syncOn ? "Syncing · \(device.clipCount) clip\(device.clipCount == 1 ? "" : "s")" : "Paused")
                        .font(ACFont.sans(10.5))
                        .foregroundStyle(device.syncOn ? ACColor.success : Color(hex: 0xA8ACB4))
                }
                Spacer(minLength: 0)
                ACMiniToggle(isOn: device.syncOn) { onToggle(device.id) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(active ? ACColor.accentSoft12 : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 34×20 sync toggle used in device rows.
struct ACMiniToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? ACColor.accent : ACColor.toggleOff)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                    .padding(2)
            }
            .frame(width: 34, height: 20)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
    }
}
