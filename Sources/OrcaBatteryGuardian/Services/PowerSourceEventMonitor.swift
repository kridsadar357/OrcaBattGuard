import CoreFoundation
import Foundation
import IOKit.ps

@MainActor
public protocol PowerSourceEventMonitoring: AnyObject {
    func start(handler: @escaping @MainActor @Sendable () -> Void)
    func stop()
}

@MainActor
public final class IOPowerSourceEventMonitor: PowerSourceEventMonitoring {
    private var source: CFRunLoopSource?
    private var handler: (@MainActor @Sendable () -> Void)?

    public init() {}

    public func start(handler: @escaping @MainActor @Sendable () -> Void) {
        guard source == nil else { return }
        self.handler = handler
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<IOPowerSourceEventMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.deliverEvent() }
        }, context)?.takeRetainedValue() else { return }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    public func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = nil
        handler = nil
    }

    private func deliverEvent() {
        handler?()
    }
}
