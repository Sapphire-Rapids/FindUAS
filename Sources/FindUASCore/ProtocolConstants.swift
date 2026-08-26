import Foundation

public enum FindUASProtocol {
    public static let serviceUUID = "00FF"
    public static let telemetryCharacteristicUUID = "FF01"
    public static let configurationCharacteristicUUID = "FF02"
    public static let experimentalWriteCharacteristicUUID = "FF03"
    public static let advertisedNames = ["FindUAV Device", "FindUAS Device"]

    public static func isCompatibleAdvertisementName(_ name: String) -> Bool {
        advertisedNames.contains {
            name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
