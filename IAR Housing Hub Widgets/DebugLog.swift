import Foundation

/// Logs in Debug builds only. Release builds were printing full API
/// responses, chat prompts and replies, and request cookies to the device
/// console, where anyone with a cable and Console.app could read them.
/// Widget-extension copy of ReportsApp/Utilities/DebugLog.swift.
@inline(__always)
func debugLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
    #endif
}
