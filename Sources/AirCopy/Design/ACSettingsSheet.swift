import SwiftUI

// MARK: - Redesigned Settings sheet (660×480 centered modal).
//
// Pixel-faithful recreation of the design handoff. Presented by the caller via
// `.sheet(isPresented: $coordinator.settingsPresented)`; this view only lays out
// the fixed-size card. Colors/fonts come from ACColor / ACFont tokens.
//
// Every row binds to real backend state on `coordinator` / `settings` — there are
// no placeholder controls. Shortcuts are editable via `ShortcutRecorderField` and
// the "Excluded apps" button opens a dedicated management sheet.

struct ACSettingsSheet: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var toast: ACToastCenter

    @State private var tab: SettingsTab = .general
    @State private var showExcludedApps = false

    var body: some View {
        HStack(spacing: 0) {
            tabRail
            contentColumn
        }
        .frame(width: 660, height: 480)
        .background(ACColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .acBorder(ACColor.border12, radius: 16)
        .shadow(color: .black.opacity(0.22), radius: 40, x: 0, y: 24)
        .sheet(isPresented: $showExcludedApps) {
            ACExcludedAppsSheet(isPresented: $showExcludedApps)
                .environmentObject(coordinator)
                .preferredColorScheme(coordinator.effectiveColorScheme)
        }
    }

    // MARK: Left tab rail

    private var tabRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(ACFont.sans(13, weight: .bold))
                .foregroundStyle(ACColor.ink)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases) { item in
                    tabButton(item)
                }
            }

            Spacer(minLength: 0)

            Text("AirCopy \(Self.shortVersion)")
                .font(ACFont.mono(10.5))
                .foregroundStyle(ACColor.textTertiary2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(width: 182, alignment: .leading)
        .background(ACColor.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ACColor.border07)
                .frame(width: 1)
        }
    }

    private func tabButton(_ item: SettingsTab) -> some View {
        let active = tab == item
        return Button {
            tab = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 16, alignment: .center)
                Text(item.title)
                    .font(ACFont.sans(13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? ACColor.accent : ACColor.textMuted)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? ACColor.accentSoft12 : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Right content column

    private var contentColumn: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        ACSettingsRowView(row: row)
                    }
                }
                .padding(.top, 6)
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(tab.title)
                .font(ACFont.sans(14, weight: .semibold))
                .foregroundStyle(ACColor.ink)
            Spacer(minLength: 0)
            CloseButton {
                coordinator.settingsPresented = false
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: 50)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ACColor.border06)
                .frame(height: 1)
        }
    }

    // MARK: Rows per tab

    private var rows: [ACSettingsRow] {
        switch tab {
        case .general: return generalRows
        case .sync: return syncRows
        case .clipboard: return clipboardRows
        case .privacy: return privacyRows
        case .shortcuts: return shortcutRows
        case .about: return aboutRows
        }
    }

    private var generalRows: [ACSettingsRow] {
        [
            ACSettingsRow(title: "Appearance", description: "Match your Mac, or force a look",
                        control: .segmented(
                            options: [
                                ACSegmentOption(label: "Light", value: "light"),
                                ACSegmentOption(label: "Dark", value: "dark"),
                                ACSegmentOption(label: "System", value: "system"),
                            ],
                            selection: Binding(
                                get: {
                                    switch coordinator.appearancePreference {
                                    case .light: return "light"
                                    case .dark: return "dark"
                                    case .automatic: return "system"
                                    }
                                },
                                set: {
                                    switch $0 {
                                    case "light": coordinator.appearancePreference = .light
                                    case "dark": coordinator.appearancePreference = .dark
                                    default: coordinator.appearancePreference = .automatic
                                    }
                                }))),
            ACSettingsRow(title: "Launch at login", description: "Start AirCopy when you sign in",
                        control: .toggle(Binding(get: { settings.launchAtLogin },
                                                 set: { settings.launchAtLogin = $0 }))),
            ACSettingsRow(title: "Show in menu bar", description: "Keep the AirCopy icon up top",
                        control: .toggle(Binding(get: { settings.showInMenuBar },
                                                 set: { settings.showInMenuBar = $0 }))),
            ACSettingsRow(title: "Show in Dock", description: "Also show an icon in the Dock",
                        control: .toggle(Binding(get: { settings.showInDock },
                                                 set: { settings.showInDock = $0 }))),
            ACSettingsRow(title: "Sound on sync", description: "A soft chime when a clip arrives",
                        control: .toggle(Binding(get: { coordinator.soundEnabled },
                                                 set: { coordinator.soundEnabled = $0 }))),
        ]
    }

    private var syncRows: [ACSettingsRow] {
        [
            ACSettingsRow(title: "New Macs", description: "How to treat Macs that appear",
                        control: .segmented(
                            options: [
                                ACSegmentOption(label: "Auto-sync", value: "auto"),
                                ACSegmentOption(label: "Ask first", value: "ask"),
                            ],
                            selection: Binding(
                                get: { coordinator.autoSyncNewDevices ? "auto" : "ask" },
                                set: { coordinator.autoSyncNewDevices = ($0 == "auto") }))),
            ACSettingsRow(title: "Require approval", description: "Confirm before a Mac can pair",
                        control: .toggle(Binding(get: { coordinator.requireDeviceApproval },
                                                 set: { coordinator.requireDeviceApproval = $0 }))),
            ACSettingsRow(title: "Pause on battery", description: "Stop syncing while on battery",
                        control: .toggle(Binding(get: { coordinator.pauseOnBattery },
                                                 set: { coordinator.pauseOnBattery = $0 }))),
        ]
    }

    private var clipboardRows: [ACSettingsRow] {
        [
            ACSettingsRow(title: "Clips to keep", description: "How many recent clips to remember",
                        control: .stepper(
                            steps: Self.historySteps,
                            value: Binding(get: { coordinator.historyLimit },
                                           set: { coordinator.historyLimit = $0 }))),
            ACSettingsRow(title: "Include images", description: "Sync screenshots and copied images",
                        control: .toggle(Binding(get: { coordinator.imageSyncEnabled },
                                                 set: { coordinator.imageSyncEnabled = $0 }))),
            ACSettingsRow(title: "Max image size", description: "Skip images larger than this",
                        control: .segmented(
                            options: [
                                ACSegmentOption(label: "5 MB", value: "5"),
                                ACSegmentOption(label: "25 MB", value: "25"),
                                ACSegmentOption(label: "Any", value: "any"),
                            ],
                            selection: Binding(
                                get: { Self.maxImageSelection(coordinator.maxImageBytes) },
                                set: { coordinator.maxImageBytes = Self.maxImageBytes(for: $0) }))),
            ACSettingsRow(title: "Clear on quit", description: "Forget history when AirCopy quits",
                        control: .toggle(Binding(get: { coordinator.clearHistoryOnQuit },
                                                 set: { coordinator.clearHistoryOnQuit = $0 }))),
        ]
    }

    private var privacyRows: [ACSettingsRow] {
        [
            ACSettingsRow(title: "Local network only", description: "AirCopy never routes clips over the internet",
                        control: .info(value: "Always on", mono: false)),
            ACSettingsRow(title: "Encrypt transfers", description: "Every transfer is end-to-end encrypted",
                        control: .info(value: "Always on", mono: false)),
            ACSettingsRow(title: "Ignore password fields", description: "Skip clips from password managers",
                        control: .toggle(Binding(get: { coordinator.blockPasswordManagerClips },
                                                 set: { coordinator.blockPasswordManagerClips = $0 }))),
            ACSettingsRow(title: "Excluded apps", description: "Apps AirCopy never reads from",
                        control: .button(label: "Manage…", danger: false) {
                            showExcludedApps = true
                        }),
        ]
    }

    private var shortcutRows: [ACSettingsRow] {
        [
            ACSettingsRow(title: "Open AirCopy", description: "Bring the window forward",
                        control: .shortcut(hotkeyBinding(for: "open"))),
            ACSettingsRow(title: "Copy & sync", description: "Copy selection and push it",
                        control: .shortcut(hotkeyBinding(for: "copySync"))),
            ACSettingsRow(title: "Paste last clip", description: "Paste the most recent clip",
                        control: .shortcut(hotkeyBinding(for: "pasteLast"))),
            ACSettingsRow(title: "Reset to defaults", description: "Restore the default shortcuts",
                        control: .button(label: "Reset", danger: false) {
                            coordinator.resetHotkeys()
                            toast.show("Shortcuts reset", accent: ACColor.accent)
                        }),
        ]
    }

    private var aboutRows: [ACSettingsRow] {
        [
            ACSettingsRow(title: "Version", description: nil,
                        control: .info(value: Self.fullVersion, mono: true)),
            ACSettingsRow(title: "Sync engine", description: "Local peer discovery",
                        control: .info(value: "Bonjour", mono: false)),
            ACSettingsRow(title: "Check for updates",
                        description: coordinator.updateCheckStatus ?? "You're on the latest build",
                        control: .button(label: "Check", danger: false) {
                            coordinator.checkForUpdates()
                        }),
            ACSettingsRow(title: "Reset settings", description: "Restore everything to defaults",
                        control: .button(label: "Reset", danger: true) {
                            coordinator.resetAllSettings()
                            settings.resetToDefaults()
                            coordinator.resetHotkeys()
                            toast.show("Settings reset", accent: ACColor.accent)
                        }),
        ]
    }

    // MARK: Binding helpers

    private func hotkeyBinding(for id: String) -> Binding<HotkeyBinding> {
        Binding(
            get: { coordinator.hotkeyBindings[id] ?? HotkeyBinding.defaultBindings()[id]! },
            set: { coordinator.setHotkey(id, $0) })
    }

    private static let historySteps = [25, 50, 100, 200, 500]

    private static func maxImageSelection(_ bytes: Int) -> String {
        switch bytes {
        case 5 * 1024 * 1024: return "5"
        case 25 * 1024 * 1024: return "25"
        case 0: return "any"
        default: return "25"
        }
    }

    private static func maxImageBytes(for selection: String) -> Int {
        switch selection {
        case "5": return 5 * 1024 * 1024
        case "25": return 25 * 1024 * 1024
        case "any": return 0
        default: return 25 * 1024 * 1024
        }
    }

    private static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private static var fullVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

// MARK: - Tabs

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, sync, clipboard, privacy, shortcuts, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .sync: return "Sync"
        case .clipboard: return "Clipboard"
        case .privacy: return "Privacy"
        case .shortcuts: return "Shortcuts"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .sync: return "arrow.triangle.2.circlepath"
        case .clipboard: return "doc.on.clipboard"
        case .privacy: return "lock.shield"
        case .shortcuts: return "command"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Row model

private struct ACSegmentOption: Identifiable {
    let label: String
    let value: String
    var id: String { value }
}

private enum ACSettingsControl {
    case toggle(Binding<Bool>)
    case segmented(options: [ACSegmentOption], selection: Binding<String>)
    case stepper(steps: [Int], value: Binding<Int>)
    case info(value: String, mono: Bool)
    case button(label: String, danger: Bool, action: () -> Void)
    case shortcut(Binding<HotkeyBinding>)
}

private struct ACSettingsRow: Identifiable {
    let id = UUID()
    let title: String
    let description: String?
    let control: ACSettingsControl
}

// MARK: - Row view

private struct ACSettingsRowView: View {
    let row: ACSettingsRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(ACFont.sans(13.5, weight: .medium))
                    .foregroundStyle(ACColor.ink)
                if let description = row.description, !description.isEmpty {
                    Text(description)
                        .font(ACFont.sans(12))
                        .foregroundStyle(ACColor.textTertiary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ACColor.border05)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch row.control {
        case let .toggle(binding):
            ACToggleSwitch(isOn: binding)
        case let .segmented(options, selection):
            ACSegmentedControl(options: options, selection: selection)
        case let .stepper(steps, value):
            ACStepperControl(steps: steps, value: value)
        case let .info(value, mono):
            Text(value)
                .font(mono ? ACFont.mono(12.5, weight: .medium) : ACFont.sans(12.5, weight: .medium))
                .foregroundStyle(ACColor.textSecondary2)
        case let .button(label, danger, action):
            ACRowButton(label: label, danger: danger, action: action)
        case let .shortcut(binding):
            ShortcutRecorderField(binding: binding)
        }
    }
}

// MARK: - Toggle

private struct ACToggleSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 100, style: .continuous)
                    .fill(isOn ? ACColor.accent : ACColor.toggleOff)
                    .frame(width: 38, height: 22)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                    .padding(.horizontal, 2)
            }
            .frame(width: 38, height: 22)
            .contentShape(RoundedRectangle(cornerRadius: 100, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented

private struct ACSegmentedControl: View {
    let options: [ACSegmentOption]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let active = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(ACFont.sans(12, weight: .medium))
                        .foregroundStyle(active ? ACColor.accent : ACColor.textSecondary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(active ? Color.white : Color.clear)
                                .shadow(color: active ? Color(hex: 0x141E3C, alpha: 0.14) : .clear,
                                        radius: active ? 2 : 0, x: 0, y: active ? 1 : 0)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(ACColor.controlTrack)
        )
    }
}

// MARK: - Stepper

private struct ACStepperControl: View {
    let steps: [Int]
    @Binding var value: Int

    @State private var hoverMinus = false
    @State private var hoverPlus = false

    private var index: Int {
        steps.firstIndex(of: value) ?? closestIndex
    }

    private var closestIndex: Int {
        var best = 0
        var bestDelta = Int.max
        for (i, step) in steps.enumerated() {
            let delta = abs(step - value)
            if delta < bestDelta { bestDelta = delta; best = i }
        }
        return best
    }

    var body: some View {
        HStack(spacing: 0) {
            stepperButton(symbol: "−", hovering: hoverMinus) {
                let i = max(0, index - 1)
                value = steps[i]
            }
            .onHover { hoverMinus = $0 }

            Text("\(value)")
                .font(ACFont.sans(13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ACColor.ink)
                .frame(minWidth: 46)
                .frame(height: 30)

            stepperButton(symbol: "+", hovering: hoverPlus) {
                let i = min(steps.count - 1, index + 1)
                value = steps[i]
            }
            .onHover { hoverPlus = $0 }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .acBorder(ACColor.border10, radius: 9)
    }

    private func stepperButton(symbol: String, hovering: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(ACColor.textSecondary)
                .frame(width: 30, height: 30)
                .background(hovering ? ACColor.controlHover : ACColor.controlSearch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row button

private struct ACRowButton: View {
    let label: String
    let danger: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(ACFont.sans(12.5, weight: .medium))
                .foregroundStyle(danger ? ACColor.danger : ACColor.ink)
                .padding(.vertical, 8)
                .padding(.horizontal, 15)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(danger ? ACColor.dangerSoft : ACColor.controlSearch)
                )
                .acBorder(danger ? ACColor.dangerBorder : ACColor.border12, radius: 9)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Close button

private struct CloseButton: View {
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

// MARK: - Local token shims
//
// A couple of design values requested by the spec don't have a named token in
// ACColor yet (the .05 row divider and the .07 rail border). Provide them here
// without touching the shared token file.
private extension ACColor {
    static let border05 = dyn(light: 0x14141E, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.05)
    static let border07 = dyn(light: 0x14141E, lightAlpha: 0.07, dark: 0xFFFFFF, darkAlpha: 0.07)
}
