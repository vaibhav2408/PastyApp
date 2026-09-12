import AppKit
import Carbon

/// Register a shortcut without global key monitoring or Accessibility permission.
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init?(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &eventType, context, &handler)
        guard installed == noErr else { return nil }

        let identifier = EventHotKeyID(signature: 0x43323048, id: 1)
        let registered = RegisterEventHotKey(
            UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey), identifier,
            GetApplicationEventTarget(), 0, &hotKey
        )
        guard registered == noErr else {
            if let handler { RemoveEventHandler(handler) }
            self.handler = nil
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
