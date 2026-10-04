import SwiftUI

/// Shared motion timing, so passes don't scatter magic numbers.
enum Motion {
    static let snapSpring = Animation.spring(response: 0.3, dampingFraction: 0.75)
    static let liftSpring = Animation.spring(response: 0.22, dampingFraction: 0.8)
    static let zoneHighlightFade = Animation.easeOut(duration: 0.12)
    static let reducedFade = Animation.easeOut(duration: 0.15)
    static let liftScale: CGFloat = 1.08


    // Receipt review: paper-feed strip, item sheet, summary tiles.
    static let stripTickCount = 3
    static let stripTickDuration = 0.12
    static let stripTick = Animation.easeOut(duration: stripTickDuration)
    static let sheetExit = Animation.easeIn(duration: 0.18)
    static let sheetEnter = Animation.spring(response: 0.22, dampingFraction: 0.85)
    static let tileStagger = 0.04
    static let tileStaggerCap = 0.6
    static let tileDrop = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Springs become a plain short fade under Reduce Motion.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedFade : animation
    }
}
