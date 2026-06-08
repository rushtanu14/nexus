import AppKit
import CoreGraphics

@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var action: (() -> Void)?

    func registerShiftSpace(action: @escaping () -> Void) {
        self.action = action
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard type == .keyDown, let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
                Task { @MainActor in
                    manager.handle(event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 49 else { return }
        let flags = event.flags
        guard flags.contains(.maskShift),
              !flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              !flags.contains(.maskAlternate) else { return }
        guard !focusedElementIsTextInput() else { return }
        action?()
    }

    private func focusedElementIsTextInput() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else {
            return false
        }
        let element = focused as! AXUIElement
        var roleValue: CFTypeRef?
        let role = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success ? roleValue as? String : nil
        var subroleValue: CFTypeRef?
        let subrole = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success ? subroleValue as? String : nil
        let textRoles: Set<String> = [
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            kAXComboBoxRole as String
        ]
        let textSubroles: Set<String> = [
            "AXSearchField",
            "AXSecureTextField"
        ]
        return role.map(textRoles.contains) == true || subrole.map(textSubroles.contains) == true
    }
}
