import SwiftUI

// MARK: - Excluded apps management sheet (~420×420 centered modal).
//
// Lists the apps AirCopy will never read clipboard contents from. Each row can
// be removed; the footer adds the current frontmost app. Reads live state from
// the coordinator (`excludedApplications`, `frontmostApplicationName`) and calls
// `addFrontmostApplicationToExclusions()` / `removeExcludedApplication(_:)`.

struct ACExcludedAppsSheet: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(ACColor.border06)
            body(for: coordinator.excludedApplications)
            Divider().background(ACColor.border06)
            footer
        }
        .frame(width: 420, height: 420)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .acBorder(ACColor.border12, radius: 16)
        .shadow(color: .black.opacity(0.22), radius: 40, x: 0, y: 24)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            Text("Excluded apps")
                .font(ACFont.sans(14, weight: .semibold))
                .foregroundStyle(ACColor.ink)
            Spacer(minLength: 0)
            ExcludedCloseButton {
                isPresented = false
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: 50)
    }

    // MARK: Body

    @ViewBuilder
    private func body(for apps: [AppExclusion]) -> some View {
        if apps.isEmpty {
            VStack {
                Spacer(minLength: 0)
                Text("No excluded apps yet.")
                    .font(ACFont.sans(13))
                    .foregroundStyle(ACColor.textTertiary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(apps) { app in
                        ExcludedAppRow(app: app) {
                            coordinator.removeExcludedApplication(app)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Footer

    private var footer: some View {
        Button {
            coordinator.addFrontmostApplicationToExclusions()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Add current app (\(coordinator.frontmostApplicationName))")
                    .font(ACFont.sans(13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(ACColor.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ACColor.accentSoft12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(16)
    }
}

// MARK: - Row

private struct ExcludedAppRow: View {
    let app: AppExclusion
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.appName)
                    .font(ACFont.sans(13.5, weight: .medium))
                    .foregroundStyle(ACColor.ink)
                Text(app.bundleID)
                    .font(ACFont.mono(11))
                    .foregroundStyle(ACColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hovering ? ACColor.danger : ACColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(hovering ? ACColor.dangerSoft : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ACColor.border06)
                .frame(height: 1)
        }
    }
}

// MARK: - Close button

private struct ExcludedCloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ACColor.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? ACColor.controlHover : ACColor.controlTrack)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
