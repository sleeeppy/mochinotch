import Foundation
import IOKit.ps

struct PowerSnapshot: Equatable {
    var percent: Int
    var onAC: Bool
    var charging: Bool
    var charged: Bool
}

enum PowerEvent: Equatable {
    case plugged(percent: Int)
    case unplugged(percent: Int)
    case charged(percent: Int)
    case percent(Int)
}

/// 충전기 연결/해제를 감시한다. 콜백은 메인 스레드로 올리지 않는다.
final class PowerMonitor {
    var onEvent: ((PowerEvent) -> Void)?
    private var source: CFRunLoopSource?
    private var last: PowerSnapshot?

    func start() {
        last = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.poll()
        }, context) else {
            return
        }
        let runLoopSource = created.takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        source = runLoopSource
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        source = nil
    }

    private func poll() {
        let snapshot = Self.read()
        let event = Self.diff(from: last, to: snapshot)
        last = snapshot
        guard let event else { return }
        let handler = onEvent
        DispatchQueue.main.async {
            handler?(event)
        }
    }

    private static func diff(from old: PowerSnapshot?, to new: PowerSnapshot) -> PowerEvent? {
        guard let old else { return nil }
        if new.onAC && !old.onAC {
            return new.charged ? .charged(percent: new.percent) : .plugged(percent: new.percent)
        }
        if !new.onAC && old.onAC {
            return .unplugged(percent: new.percent)
        }
        if new.onAC && new.charged && !old.charged {
            return .charged(percent: new.percent)
        }
        if new.onAC && new.percent != old.percent {
            return .percent(new.percent)
        }
        return nil
    }

    static func read() -> PowerSnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSnapshot(percent: 0, onAC: false, charging: false, charged: false)
        }
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? NSArray else {
            return PowerSnapshot(percent: 0, onAC: false, charging: false, charged: false)
        }

        var chosen: [String: Any]?
        for case let item as CFTypeRef in list {
            guard let description = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = description[kIOPSTypeKey] as? String
            if type == kIOPSInternalBatteryType {
                chosen = description
                break
            }
            if chosen == nil {
                chosen = description
            }
        }

        guard let chosen else {
            return PowerSnapshot(percent: 0, onAC: false, charging: false, charged: false)
        }

        let current = Self.number(chosen[kIOPSCurrentCapacityKey])
        let maxCapacity = Self.number(chosen[kIOPSMaxCapacityKey])
        let percent: Int
        if maxCapacity > 0 {
            percent = min(100, Int((Double(current) / Double(maxCapacity) * 100).rounded()))
        } else {
            percent = min(100, current)
        }
        let state = chosen[kIOPSPowerSourceStateKey] as? String
        let onAC = state == kIOPSACPowerValue
        let charging = Self.flag(chosen[kIOPSIsChargingKey])
        let charged = Self.flag(chosen[kIOPSIsChargedKey]) || (onAC && percent >= 100 && !charging)
        return PowerSnapshot(percent: percent, onAC: onAC, charging: charging, charged: charged)
    }

    private static func number(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    private static func flag(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }
}
