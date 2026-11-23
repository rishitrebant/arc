import Foundation

/// Console logging that exists only in Debug builds.
///
/// Release builds print nothing — in particular not the media adapter's
/// raw output, which includes the titles of what you're listening to.
@inline(__always)
func debugLog(_ items: Any..., separator: String = " ") {
    #if DEBUG
    print(items.map { "\($0)" }.joined(separator: separator))
    #endif
}
