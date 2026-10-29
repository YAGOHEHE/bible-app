import Foundation

extension Array {
    /// Element at `i`, or nil when out of range.
    public subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
