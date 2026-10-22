import SwiftUI
import UIKit

/// Readout's animation vocabulary (R-50).
///
/// A handful of named curves rather than a fresh spring at every call site, so the whole app
/// moves alike: quick and settled for state changes, a little softer for things arriving, and
/// a touch of bounce only where something has actually happened. Nothing here is decoration
/// for its own sake — each one shows where a change came from or where it went.
extension Animation {
    /// State changes: a control's value, a badge appearing, digits rolling over.
    static let readoutSnappy = Animation.snappy(duration: 0.32)
    /// Larger movements: a panel arriving, a chart's window changing.
    static let readoutSmooth = Animation.smooth(duration: 0.45)
    /// The few moments of arrival — a recording saved, the level reaching zero.
    static let readoutSpring = Animation.spring(duration: 0.5, bounce: 0.18)
    /// An instrument following its sensor: quick enough to keep up, soft enough not to jitter.
    static let readoutFollow = Animation.interactiveSpring(duration: 0.22, extraBounce: 0.02)
}

extension View {
    /// `.animation(_:value:)` that stands down under Reduce Motion, where the change simply
    /// happens (R-50).
    func motion<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }

    /// Fades and lifts a view into place the first time it appears, `delay` seconds after
    /// its neighbours, so a screen settles into being rather than snapping on (R-50).
    func arrival(delay: Double = 0, isActive: Bool = true) -> some View {
        modifier(Arrival(delay: delay, isActive: isActive))
    }
}

/// `withAnimation` that stands down under Reduce Motion, for changes made in an action.
@MainActor
func withReadoutAnimation<Result>(_ animation: Animation = .readoutSnappy, _ body: () throws -> Result) rethrows -> Result {
    if UIAccessibility.isReduceMotionEnabled {
        return try body()
    }
    return try withAnimation(animation, body)
}

private struct MotionAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct Arrival: ViewModifier {
    let delay: Double
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasArrived = false

    func body(content: Content) -> some View {
        let isShown = hasArrived || !isActive || reduceMotion
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : 14)
            .scaleEffect(isShown ? 1 : 0.97, anchor: .top)
            .onAppear {
                guard !hasArrived else { return }
                withAnimation(.readoutSmooth.delay(delay)) {
                    hasArrived = true
                }
            }
    }
}
