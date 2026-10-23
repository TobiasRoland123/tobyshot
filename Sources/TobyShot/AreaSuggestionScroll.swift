import Foundation

/// Wheel ticks step once; trackpad motion accumulates and is rate limited.
/// Momentum is discarded by SelectionView before it reaches this filter.
struct AreaSuggestionScroll {
    private var accumulated: CGFloat = 0
    private var lastEvent: TimeInterval = -.infinity
    private var lastStep: TimeInterval = -.infinity
    private var direction: Bool?

    mutating func reset() { self = Self() }

    mutating func step(delta: CGFloat, precise: Bool, timestamp: TimeInterval) -> Bool? {
        guard delta != 0 else { return nil }
        let outward = delta > 0
        if timestamp - lastEvent > 0.3 || direction != outward {
            accumulated = 0
            lastStep = -.infinity
        }
        direction = outward
        lastEvent = timestamp
        guard precise else { return outward }
        accumulated += abs(delta)
        guard accumulated >= 24, timestamp - lastStep >= 0.15 else { return nil }
        accumulated = 0
        lastStep = timestamp
        return outward
    }
}
