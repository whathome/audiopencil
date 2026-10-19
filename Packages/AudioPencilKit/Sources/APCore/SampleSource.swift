/// A growing buffer of 16 kHz mono samples (the current recording).
public protocol SampleSource: Sendable {
    var count: Int { get }
    /// Copies samples from `start` to the current end.
    func samples(from start: Int) -> [Float]
}
