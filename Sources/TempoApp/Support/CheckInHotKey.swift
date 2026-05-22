import AppKit
import Carbon
import Foundation

struct CheckInHotKey: Equatable {
    let keyCode: UInt32
    let modifierFlags: UInt32

    init(keyCode: UInt32, modifierFlags: UInt32) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    init?(event: NSEvent) {
        guard let modifierFlags = Self.carbonModifierFlags(from: event.modifierFlags) else {
            return nil
        }

        self.keyCode = UInt32(event.keyCode)
        self.modifierFlags = modifierFlags
    }

    var displayString: String {
        "\(Self.modifierDisplayString(for: modifierFlags))\(Self.keyDisplayString(for: keyCode))"
    }

    static func modifierFlags(
        command: Bool = false,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false
    ) -> UInt32 {
        var result: UInt32 = 0
        if command {
            result |= UInt32(cmdKey)
        }
        if option {
            result |= UInt32(optionKey)
        }
        if control {
            result |= UInt32(controlKey)
        }
        if shift {
            result |= UInt32(shiftKey)
        }
        return result
    }

    static func carbonModifierFlags(from flags: NSEvent.ModifierFlags) -> UInt32? {
        let normalized = flags.intersection([.command, .option, .control, .shift])
        guard normalized.contains(.command) || normalized.contains(.option) || normalized.contains(.control) else {
            return nil
        }

        return modifierFlags(
            command: normalized.contains(.command),
            option: normalized.contains(.option),
            control: normalized.contains(.control),
            shift: normalized.contains(.shift)
        )
    }

    private static func modifierDisplayString(for flags: UInt32) -> String {
        var result = ""
        if flags & UInt32(controlKey) != 0 {
            result += "Control+"
        }
        if flags & UInt32(optionKey) != 0 {
            result += "Option+"
        }
        if flags & UInt32(shiftKey) != 0 {
            result += "Shift+"
        }
        if flags & UInt32(cmdKey) != 0 {
            result += "Command+"
        }
        return result
    }

    private static func keyDisplayString(for keyCode: UInt32) -> String {
        if let specialKey = specialKeyDisplayStrings[keyCode] {
            return specialKey
        }

        guard let translated = translatedKeyDisplayString(for: keyCode), !translated.isEmpty else {
            return "Key \(keyCode)"
        }

        return translated.uppercased()
    }

    private static func translatedKeyDisplayString(for keyCode: UInt32) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layoutData) else {
            return nil
        }

        let keyboardLayout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )

        guard status == noErr, length > 0 else {
            return nil
        }

        return String(utf16CodeUnits: characters, count: length)
    }

    private static let specialKeyDisplayStrings: [UInt32: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        71: "Clear",
        76: "Enter",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        114: "Help",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        118: "F4",
        119: "End",
        120: "F2",
        121: "Page Down",
        122: "F1",
        123: "Left Arrow",
        124: "Right Arrow",
        125: "Down Arrow",
        126: "Up Arrow",
    ]
}

@MainActor
protocol CheckInHotKeyStoring {
    func load() -> CheckInHotKey?
    func save(_ hotKey: CheckInHotKey?)
}

struct UserDefaultsCheckInHotKeyStore: CheckInHotKeyStoring {
    private enum Key {
        static let keyCode = "checkInHotKey.keyCode"
        static let modifierFlags = "checkInHotKey.modifierFlags"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> CheckInHotKey? {
        guard userDefaults.object(forKey: Key.keyCode) != nil,
              userDefaults.object(forKey: Key.modifierFlags) != nil else {
            return nil
        }

        let keyCode = userDefaults.integer(forKey: Key.keyCode)
        let modifierFlags = userDefaults.integer(forKey: Key.modifierFlags)
        guard keyCode >= 0, modifierFlags > 0 else {
            return nil
        }

        return CheckInHotKey(keyCode: UInt32(keyCode), modifierFlags: UInt32(modifierFlags))
    }

    func save(_ hotKey: CheckInHotKey?) {
        guard let hotKey else {
            userDefaults.removeObject(forKey: Key.keyCode)
            userDefaults.removeObject(forKey: Key.modifierFlags)
            return
        }

        userDefaults.set(Int(hotKey.keyCode), forKey: Key.keyCode)
        userDefaults.set(Int(hotKey.modifierFlags), forKey: Key.modifierFlags)
    }
}

@MainActor
protocol CheckInHotKeyRegistering: AnyObject {
    func register(_ hotKey: CheckInHotKey?, action: @escaping @MainActor () -> Void) throws
    func unregister()
}

enum CheckInHotKeyRegistrationError: LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .registrationFailed(status):
            return "macOS could not register that shortcut. It may already be used by another app. (\(status))"
        }
    }
}

@MainActor
final class CarbonCheckInHotKeyRegistrar: CheckInHotKeyRegistering {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    func register(_ hotKey: CheckInHotKey?, action: @escaping @MainActor () -> Void) throws {
        unregister()
        guard let hotKey else {
            return
        }

        self.action = action
        try installEventHandlerIfNeeded()

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        var registeredHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifierFlags,
            identifier,
            GetApplicationEventTarget(),
            0,
            &registeredHotKeyRef
        )

        guard status == noErr, let registeredHotKeyRef else {
            self.action = nil
            throw CheckInHotKeyRegistrationError.registrationFailed(status)
        }

        hotKeyRef = registeredHotKeyRef
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        action = nil
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        guard status == noErr else {
            throw CheckInHotKeyRegistrationError.registrationFailed(status)
        }
    }

    private func handleEvent(_ event: EventRef?) -> OSStatus {
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )

        guard status == noErr, identifier.signature == Self.signature else {
            return status
        }

        Task { @MainActor [weak self] in
            self?.action?()
        }
        return noErr
    }

    private static let signature = OSType(
        UInt32(UInt8(ascii: "T")) << 24 |
            UInt32(UInt8(ascii: "M")) << 16 |
            UInt32(UInt8(ascii: "P")) << 8 |
            UInt32(UInt8(ascii: "O"))
    )

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let registrar = Unmanaged<CarbonCheckInHotKeyRegistrar>
            .fromOpaque(userData)
            .takeUnretainedValue()
        return registrar.handleEvent(event)
    }
}
