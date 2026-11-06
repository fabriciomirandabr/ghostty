import Combine
import Foundation
import IOKit.ps

enum WorkspacePowerMode: String, Equatable, Sendable {
    case performance
    case saver

    static func resolve(lowPower: Bool, thermal: ProcessInfo.ThermalState, onBattery: Bool) -> WorkspacePowerMode {
        let hot = thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        return lowPower || hot || onBattery ? .saver : .performance
    }

    var chromeThrottleInterval: TimeInterval {
        switch self {
        case .performance: 0.2
        case .saver: 1.0
        }
    }

    var snapshotInterval: TimeInterval {
        switch self {
        case .performance: 0.5
        case .saver: 2.0
        }
    }

    var thumbnailRefreshInterval: TimeInterval {
        switch self {
        case .performance: 0.5
        case .saver: 2.0
        }
    }
}

struct WorkspacePowerInputs: Equatable {
    var lowPower: Bool
    var thermal: ProcessInfo.ThermalState
    var onBattery: Bool

    var mode: WorkspacePowerMode {
        WorkspacePowerMode.resolve(lowPower: lowPower, thermal: thermal, onBattery: onBattery)
    }
}

enum WorkspacePowerSource {
    static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
            Ghostty.logger.warning("power source unavailable, treating the machine as plugged in")
            return false
        }
        return (type as String) == kIOPSBatteryPowerValue
    }

    static func currentInputs() -> WorkspacePowerInputs {
        WorkspacePowerInputs(
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermal: ProcessInfo.processInfo.thermalState,
            onBattery: isOnBattery())
    }
}

@MainActor
final class WorkspacePowerMonitor: ObservableObject {
    static let shared = WorkspacePowerMonitor(observingSystem: true)

    @Published private(set) var mode: WorkspacePowerMode

    private let readInputs: () -> WorkspacePowerInputs

    init(
        readInputs: @escaping () -> WorkspacePowerInputs = WorkspacePowerSource.currentInputs,
        observingSystem: Bool = false
    ) {
        self.readInputs = readInputs
        self.mode = readInputs().mode
        if observingSystem {
            observeSystem()
        }
    }

    func refresh() {
        let resolved = readInputs().mode
        guard resolved != mode else { return }
        mode = resolved
        Ghostty.logger.info("workspace power mode: \(resolved.rawValue, privacy: .public)")
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }

        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<WorkspacePowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            Ghostty.logger.warning("power source notifications unavailable")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
}
