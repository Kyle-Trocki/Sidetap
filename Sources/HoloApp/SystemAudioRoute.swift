import CoreAudio
import Foundation
import HoloCore

enum SystemAudioRouteError: Error, LocalizedError {
    case propertyReadFailed(selector: AudioObjectPropertySelector, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .propertyReadFailed(_, let status):
            return "Core Audio could not inspect the current audio route (error \(status))."
        }
    }
}

enum SystemAudioRouteInspector {
    /// Reports the devices Sidetap pins capture and the probe to. These are the
    /// built-in devices even when AirPods or a display are the system default.
    /// The default appears only when no built-in device exists, so the policy
    /// can name what it found.
    static func currentRoute() throws -> AudioRouteInfo {
        let input = try routedDevice(isInput: true).map(endpoint)
        let output = try? routedDevice(isInput: false).map(endpoint)
        return AudioRouteInfo(input: input, output: output)
    }

    /// The default device when it is built in; otherwise the first built-in
    /// device with streams in that direction.
    static func builtInDevice(isInput: Bool) throws -> AudioDeviceID? {
        if let device = try defaultDevice(isInput: isInput), try transportType(device) == kAudioDeviceTransportTypeBuiltIn {
            return device
        }
        return try allDevices().first { device in
            (try? transportType(device)) == kAudioDeviceTransportTypeBuiltIn && hasStreams(device, isInput: isInput)
        }
    }

    private static func routedDevice(isInput: Bool) throws -> AudioDeviceID? {
        try builtInDevice(isInput: isInput) ?? defaultDevice(isInput: isInput)
    }

    private static func endpoint(_ deviceID: AudioDeviceID) throws -> AudioEndpointInfo {
        let name = (try? deviceName(deviceID)) ?? "Unknown audio device"
        let transport = try transportType(deviceID)
        return AudioEndpointInfo(
            name: name,
            isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn
        )
    }

    private static func allDevices() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else {
            throw SystemAudioRouteError.propertyReadFailed(selector: kAudioHardwarePropertyDevices, status: status)
        }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
        guard status == noErr else {
            throw SystemAudioRouteError.propertyReadFailed(selector: kAudioHardwarePropertyDevices, status: status)
        }
        // A device can disappear between the two reads; size then shrinks.
        return Array(devices.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size))
    }

    private static func hasStreams(_ deviceID: AudioDeviceID, isInput: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: isInput ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func defaultDevice(isInput: Bool) throws -> AudioDeviceID? {
        let selector = isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else {
            throw SystemAudioRouteError.propertyReadFailed(selector: selector, status: status)
        }
        return deviceID == kAudioObjectUnknown ? nil : deviceID
    }

    private static func deviceName(_ deviceID: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &unmanagedName
        )
        guard status == noErr else {
            throw SystemAudioRouteError.propertyReadFailed(
                selector: kAudioObjectPropertyName,
                status: status
            )
        }
        return (unmanagedName?.takeUnretainedValue() as String?) ?? "Unknown audio device"
    }

    private static func transportType(_ deviceID: AudioDeviceID) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = kAudioDeviceTransportTypeUnknown
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        guard status == noErr else {
            throw SystemAudioRouteError.propertyReadFailed(
                selector: kAudioDevicePropertyTransportType,
                status: status
            )
        }
        return transport
    }
}
