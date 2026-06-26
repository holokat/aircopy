import Foundation
import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - HotkeyBinding

/// A system-wide global keyboard shortcut described in Carbon terms.
struct HotkeyBinding: Equatable, Codable {
    /// Carbon / virtual key code (one of the `kVK_*` constants).
    var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey | shiftKey | optionKey | controlKey`).
    var modifiers: UInt32
    /// Human-readable representation, e.g. `"⌘ ⇧ V"`. Computed at construction.
    var displayString: String

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = HotkeyBinding.makeDisplayString(keyCode: keyCode, carbonModifiers: modifiers)
    }

    // MARK: Building from AppKit input

    /// Build a binding from an AppKit key-down event.
    init?(event: NSEvent) {
        guard event.type == .keyDown || event.type == .flagsChanged else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifierFlags: event.modifierFlags)
    }

    /// Build a binding from a virtual key code and `NSEvent.ModifierFlags`.
    init(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) {
        let carbon = HotkeyBinding.carbonModifiers(from: modifierFlags)
        self.init(keyCode: keyCode, modifiers: carbon)
    }

    // MARK: Modifier conversion

    /// Convert `NSEvent.ModifierFlags` into a Carbon modifier mask.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    // MARK: Display string

    /// Compose the display string: modifier glyphs followed by the key glyph.
    static func makeDisplayString(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    /// Map a virtual key code to a printable glyph / name.
    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Grave: return "`"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key\(keyCode)"
        }
    }

    // MARK: Defaults

    /// Default bindings keyed by action id: ⌘⇧V, ⌘⇧C, ⌘⇧B.
    static func defaultBindings() -> [String: HotkeyBinding] {
        let shiftCmd = UInt32(cmdKey) | UInt32(shiftKey)
        return [
            "open":      HotkeyBinding(keyCode: UInt32(kVK_ANSI_V), modifiers: shiftCmd),
            "copySync":  HotkeyBinding(keyCode: UInt32(kVK_ANSI_C), modifiers: shiftCmd),
            "pasteLast": HotkeyBinding(keyCode: UInt32(kVK_ANSI_B), modifiers: shiftCmd),
        ]
    }
}

// MARK: - GlobalHotkeyManager

/// Registers and dispatches system-wide global hotkeys via the Carbon
/// `RegisterEventHotKey` API. This works without Accessibility permission.
@MainActor
final class GlobalHotkeyManager {

    /// Internal record for a single registered hotkey.
    private struct Registration {
        let hotKeyID: UInt32
        let ref: EventHotKeyRef
        let handler: () -> Void
        let stringID: String
    }

    /// Numeric hotkey id → registration.
    private var registrations: [UInt32: Registration] = [:]
    /// Action string id → numeric hotkey id, so we can replace by string id.
    private var idsByString: [String: UInt32] = [:]

    /// The single installed Carbon event handler.
    private var eventHandlerRef: EventHandlerRef?
    /// Monotonically increasing signature/id source.
    private var nextID: UInt32 = 1

    /// Four-char-code signature shared by all our hotkeys.
    private let signature: OSType = {
        // 'ACpy'
        let chars: [UInt8] = [0x41, 0x43, 0x70, 0x79]
        return OSType(chars[0]) << 24 | OSType(chars[1]) << 16 | OSType(chars[2]) << 8 | OSType(chars[3])
    }()

    init() {}

    isolated deinit {
        // Isolated deinit (Swift 6) runs on the main actor, so it can safely
        // touch our main-actor state and clean up the Carbon resources we own.
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    // MARK: Public registration API

    /// (Re)register a hotkey for `id`, replacing any existing binding for it.
    func register(id: String, binding: HotkeyBinding, handler: @escaping () -> Void) {
        installEventHandlerIfNeeded()
        unregister(id: id)

        let hotKeyID = nextID
        nextID &+= 1

        let carbonID = EventHotKeyID(signature: signature, id: hotKeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            carbonID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            return
        }

        registrations[hotKeyID] = Registration(
            hotKeyID: hotKeyID,
            ref: ref,
            handler: handler,
            stringID: id
        )
        idsByString[id] = hotKeyID
    }

    /// Unregister the hotkey associated with `id`, if any.
    func unregister(id: String) {
        guard let hotKeyID = idsByString.removeValue(forKey: id),
              let registration = registrations.removeValue(forKey: hotKeyID) else {
            return
        }
        UnregisterEventHotKey(registration.ref)
    }

    /// Unregister every hotkey.
    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
        idsByString.removeAll()
    }

    // MARK: Persistence

    private static func defaultsKey(_ id: String) -> String { "ac.hotkey.\(id)" }

    /// Read a saved binding for `id`, falling back to `def`.
    func savedBinding(id: String, default def: HotkeyBinding) -> HotkeyBinding {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey(id)),
              let decoded = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else {
            return def
        }
        // Recompute the display string in case glyph mapping changed.
        return HotkeyBinding(keyCode: decoded.keyCode, modifiers: decoded.modifiers)
    }

    /// Persist `binding` for `id`.
    func saveBinding(id: String, _ binding: HotkeyBinding) {
        guard let data = try? JSONEncoder().encode(binding) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey(id))
    }

    // MARK: Carbon event handling

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var handlerRef: EventHandlerRef?

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotkeyEventHandlerCallback,
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )

        if status == noErr {
            eventHandlerRef = handlerRef
        }
    }

    /// Called (on the main thread) when a registered hotkey fires.
    fileprivate func handleHotKey(id hotKeyID: UInt32) {
        guard let registration = registrations[hotKeyID] else { return }
        registration.handler()
    }
}

// MARK: - Carbon C callback

/// C callback bridged back to the owning `GlobalHotkeyManager` instance.
private func hotkeyEventHandlerCallback(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    let numericID = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            manager.handleHotKey(id: numericID)
        }
    }
    return noErr
}

// MARK: - ShortcutRecorderField

/// A compact SwiftUI pill that displays a hotkey and, when clicked, records a
/// new key-with-modifiers combination via a local NSEvent monitor.
struct ShortcutRecorderField: View {
    @Binding var binding: HotkeyBinding

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            Text(isRecording ? "Recording… press keys" : binding.displayString)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
                .frame(minWidth: 90)
                .frame(height: 28)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                      lineWidth: isRecording ? 1.5 : 1)
                )
                .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels recording.
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            // Require at least one modifier for a sensible global shortcut.
            let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let active = event.modifierFlags.intersection(relevant)
            guard !active.isEmpty else {
                return nil // swallow modifier-less keys while recording
            }
            let newBinding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifierFlags: active)
            binding = newBinding
            stopRecording()
            return nil // consume the event
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}
