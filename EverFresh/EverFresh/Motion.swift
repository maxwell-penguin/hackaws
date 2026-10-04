import SwiftUI

/// Shared motion timing, so passes don't scatter magic numbers.
enum Motion {
    static let snapSpring = Animation.spring(response: 0.3, dampingFraction: 0.75)
    static let liftSpring = Animation.spring(response: 0.22, dampingFraction: 0.8)
    static let zoneHighlightFade = Animation.easeOut(duration: 0.12)
    static let reducedFade = Animation.easeOut(duration: 0.15)
    static let liftScale: CGFloat = 1.08

    /// Springs become a plain short fade under Reduce Motion.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedFade : animation
    }
}
