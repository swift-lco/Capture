import AppKit
import CoreAudio
import Foundation

internal struct CoreAudioProcessResolution: Sendable, Hashable {
    internal let processID: pid_t
    internal let processObjectID: AudioObjectID
    internal let processName: String
    internal let bundleIdentifier: String?

    internal init(
        processID: pid_t,
        processObjectID: AudioObjectID,
        processName: String,
        bundleIdentifier: String?
    ) {
        self.processID = processID
        self.processObjectID = processObjectID
        self.processName = processName
        self.bundleIdentifier = bundleIdentifier
    }
}

internal struct CoreAudioProcessResolver: Sendable {
    internal init() {}

    internal func resolve(
        _ selection: CaptureProcessAudioSelection
    ) throws -> CoreAudioProcessResolution {
        switch selection {
        case .pid(let pid):
            return try resolve(
                pid: pid,
                processName: "pid \(pid)",
                bundleIdentifier: nil
            )

        case .application_name(let name):
            let application = try runningApplication(
                name: name
            )

            return try resolve(
                pid: application.processIdentifier,
                processName: application.localizedName ?? name,
                bundleIdentifier: application.bundleIdentifier
            )

        case .bundle_identifier(let bundleIdentifier):
            let application = try runningApplication(
                bundleIdentifier: bundleIdentifier
            )

            return try resolve(
                pid: application.processIdentifier,
                processName: application.localizedName ?? bundleIdentifier,
                bundleIdentifier: application.bundleIdentifier
            )
        }
    }
}

private extension CoreAudioProcessResolver {
    func runningApplication(
        name: String
    ) throws -> NSRunningApplication {
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedName.isEmpty else {
            throw CaptureError.audioCapture(
                "Missing application name for process audio capture."
            )
        }

        let matches = NSWorkspace.shared.runningApplications.filter { application in
            guard let localizedName = application.localizedName else {
                return false
            }

            return localizedName.localizedCaseInsensitiveCompare(
                trimmedName
            ) == .orderedSame
        }

        guard let application = matches.first else {
            throw CaptureError.audioCapture(
                "Application is not running: \(trimmedName). Launch it first, then run process audio capture."
            )
        }

        guard matches.count == 1 else {
            throw CaptureError.audioCapture(
                "Multiple running applications matched \(trimmedName). Use --pid or --bundle-id instead."
            )
        }

        return application
    }

    func runningApplication(
        bundleIdentifier: String
    ) throws -> NSRunningApplication {
        let trimmedBundleIdentifier = bundleIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedBundleIdentifier.isEmpty else {
            throw CaptureError.audioCapture(
                "Missing bundle identifier for process audio capture."
            )
        }

        let matches = NSRunningApplication.runningApplications(
            withBundleIdentifier: trimmedBundleIdentifier
        )

        guard let application = matches.first else {
            throw CaptureError.audioCapture(
                "Application is not running: \(trimmedBundleIdentifier). Launch it first, then run process audio capture."
            )
        }

        guard matches.count == 1 else {
            throw CaptureError.audioCapture(
                "Multiple running applications matched \(trimmedBundleIdentifier). Use --pid instead."
            )
        }

        return application
    }

    func resolve(
        pid: pid_t,
        processName: String,
        bundleIdentifier: String?
    ) throws -> CoreAudioProcessResolution {
        guard pid > 0 else {
            throw CaptureError.audioCapture(
                "Invalid process id for process audio capture: \(pid)."
            )
        }

        let processObjectID = try processObjectID(
            pid: pid
        )

        return CoreAudioProcessResolution(
            processID: pid,
            processObjectID: processObjectID,
            processName: processName,
            bundleIdentifier: bundleIdentifier
        )
    }

    func processObjectID(
        pid: pid_t
    ) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var qualifier = pid
        var processObjectID = AudioObjectID(
            kAudioObjectUnknown
        )
        var byteCount = UInt32(
            MemoryLayout<AudioObjectID>.size
        )

        let status = withUnsafePointer(
            to: &qualifier
        ) { qualifierPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                qualifierPointer,
                &byteCount,
                &processObjectID
            )
        }

        guard status == noErr,
              processObjectID != AudioObjectID(kAudioObjectUnknown) else {
            throw CaptureError.audioCapture(
                "Could not translate pid \(pid) to a Core Audio process object. OSStatus=\(status). The process may not be producing Core Audio output yet."
            )
        }

        return processObjectID
    }
}
