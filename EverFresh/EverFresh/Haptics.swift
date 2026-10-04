import UIKit

/// Long-lived generators so the first tick isn't late; call `prepare()` when a gesture begins.
@MainActor
enum Haptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)

    static func prepare() {
        lightGenerator.prepare()
        softGenerator.prepare()
    }

    static func lift() { lightGenerator.impactOccurred() }
    static func settle() { softGenerator.impactOccurred() }
}
