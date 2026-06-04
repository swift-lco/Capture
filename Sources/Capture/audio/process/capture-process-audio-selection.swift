import Foundation

public enum CaptureProcessAudioSelection: Sendable, Codable, Hashable {
    case pid(Int32)
    case application_name(String)
    case bundle_identifier(String)
}
