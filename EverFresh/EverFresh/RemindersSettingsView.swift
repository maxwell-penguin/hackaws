import SwiftUI
import UserNotifications

struct RemindersSettingsView: View {
    @ObservedObject private var scheduler = ReminderScheduler.shared
    @Environment(\.dismiss) private var dismiss

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: scheduler.reminderMinutes / 60, minute: scheduler.reminderMinutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            scheduler.reminderMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
            scheduler.requestRefresh()
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding {
            scheduler.remindersEnabled
        } set: { on in
            Task {
                if on {
                    if scheduler.authorizationStatus == .notDetermined {
                        guard await scheduler.requestAuthorization() else {
                            scheduler.remindersEnabled = false
                            return
                        }
                    }
                    scheduler.remindersEnabled = true
                } else {
                    scheduler.remindersEnabled = false
                }
                scheduler.requestRefresh()
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if scheduler.authorizationStatus == .denied {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notifications are turned off for EverFresh in iOS Settings.")
                                .font(.everFreshBody)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .foregroundStyle(Color.freezerUltramarine)
                        }
                    } else {
                        Toggle("Expiry reminders", isOn: toggleBinding)
                            .tint(Color.freezerUltramarine)
                    }
                    DatePicker("Remind me at", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .disabled(!scheduler.remindersEnabled)
                } footer: {
                    Text("You'll get a reminder the day before and the day an item expires.")
                        .foregroundStyle(Color.shelfSteel)
                }
                .listRowBackground(Color.enamel)
                .listRowSeparatorTint(Color.shelfSteel)

                #if DEBUG
                Section {
                    Button("Send a test reminder") { Self.sendTest() }
                        .foregroundStyle(Color.freezerUltramarine)
                }
                .listRowBackground(Color.enamel)
                #endif
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.enamel)
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await scheduler.refreshAuthorizationStatus() }
        }
    }

    #if DEBUG
    private static func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Test reminder"
        content.sound = .default
        content.userInfo = ["destination": "fridge"]
        let request = UNNotificationRequest(
            identifier: "everfresh.debug",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
    #endif
}
