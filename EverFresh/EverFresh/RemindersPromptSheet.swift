import SwiftUI

/// One-time, in-context offer to turn on expiry reminders.
struct RemindersPromptSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Get a heads-up before food expires")
                .font(.everFreshTitle)
                .tracking(-0.4)
            Text("EverFresh can remind you the day before and the day something expires. Reminders stay on your phone.")
                .font(.everFreshBody)
            Spacer(minLength: 0)
            Button {
                Task {
                    let scheduler = ReminderScheduler.shared
                    if await scheduler.requestAuthorization() {
                        scheduler.remindersEnabled = true
                        scheduler.requestRefresh()
                    }
                    dismiss()
                }
            } label: {
                Text("Turn on reminders")
                    .font(.system(.body, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(Color.freezerUltramarine, in: RoundedRectangle(cornerRadius: 14))
            }
            Button("Not now") {
                ReminderScheduler.shared.promptDeclined = true
                dismiss()
            }
            .foregroundStyle(Color.shelfSteel)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.enamel)
        .presentationDetents([.medium])
    }
}
