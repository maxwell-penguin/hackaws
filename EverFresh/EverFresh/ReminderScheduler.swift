import Combine
import UIKit
import UserNotifications

@MainActor
final class ReminderScheduler: ObservableObject {
    static let shared = ReminderScheduler()

    private static let prefix = "everfresh.expiry."
    private let defaults = UserDefaults.standard

    @Published var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: "reminders.enabled") }
    }
    @Published var reminderMinutes: Int {
        didSet { defaults.set(reminderMinutes, forKey: "reminders.minutes") }
    }
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var pendingRefresh: Task<Void, Never>?

    private init() {
        remindersEnabled = defaults.bool(forKey: "reminders.enabled")
        reminderMinutes = defaults.object(forKey: "reminders.minutes") as? Int ?? 540
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorizationStatus()
        return granted
    }

    /// Debounced so a burst of saves (a receipt flow) causes one reschedule.
    func requestRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    func refresh() async {
        let center = UNUserNotificationCenter.current()
        await refreshAuthorizationStatus()

        func removeOurs() async {
            let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }

        guard remindersEnabled, authorizationStatus == .authorized || authorizationStatus == .provisional else {
            await removeOurs()
            return
        }

        let items: [ScannedItem]
        do {
            items = try await ItemService.fetchActiveItems()
        } catch {
            #if DEBUG
            print("[Reminders] fetch failed, schedule unchanged")
            #endif
            return
        }

        let calendar = Calendar.current
        let plan = planReminders(items: items, now: Date(), calendar: calendar, reminderMinutes: reminderMinutes)
        await removeOurs()
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.userInfo = ["destination": "fridge"]
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
        #if DEBUG
        print("[Reminders] scheduled \(plan.count) reminders for \(Set(plan.map(\.expiryDay)).count) days")
        #endif
    }
}

/// Lets reminders show as banners while the app is open. Tap handling (didReceive) comes later.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
