//
//  QuickSaveSection.swift
//  overdo
//
//  Created by tomas on 17.05.2026.
//

import SwiftUI

/// A "Quick save" form section: each button both sets a new due date *and* saves
/// the task immediately (closing the detail). Grouped into relative offsets,
/// times later today, and times tomorrow.
struct QuickSaveSection: View {

    /// Sets the given due date and saves/closes the task.
    let onQuickSave: (Date) -> Void
    /// Disables the buttons (e.g. when the task text is empty).
    var isDisabled: Bool = false

    /// The on-the-hour times offered for "today" and "tomorrow".
    private let hours = [7, 9, 12, 18, 20]

    var body: some View {
        Section("Quick save") {
            group("In") {
                quickButton("15 min", date: .now.addingTimeInterval(15 * 60))
                quickButton("1 h", date: .now.addingTimeInterval(60 * 60))
                quickButton("3 h", date: .now.addingTimeInterval(3 * 60 * 60))
                quickButton("6 h", date: .now.addingTimeInterval(6 * 60 * 60))
                quickButton("9 h", date: .now.addingTimeInterval(9 * 60 * 60))
                quickButton("12 h", date: .now.addingTimeInterval(12 * 60 * 60))
            }

            // Only times still ahead of now.
            let todayDates = hours.compactMap { date(hour: $0, dayOffset: 0) }
                .filter { $0 > .now }
            if !todayDates.isEmpty {
                group("Today at") {
                    ForEach(todayDates, id: \.self) { date in
                        quickButton(timeLabel(date), date: date)
                    }
                }
            }

            group("Tomorrow at") {
                ForEach(hours.compactMap { date(hour: $0, dayOffset: 1) }, id: \.self) { date in
                    quickButton(timeLabel(date), date: date)
                }
            }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func group<Buttons: View>(
        _ title: String,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                buttons()
            }
        }
        .padding(.vertical, 4)
    }

    private func quickButton(_ title: String, date: Date) -> some View {
        Button(title) { onQuickSave(date) }
            .font(.footnote)
            .buttonStyle(.bordered)
            .disabled(isDisabled)
    }

    // MARK: - Helpers

    private func timeLabel(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// A date for `hour:00` on today (`dayOffset` 0) or a following day.
    private func date(hour: Int, dayOffset: Int) -> Date? {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: .now) else { return nil }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }
}

#Preview {
    Form {
        QuickSaveSection(onQuickSave: { _ in })
    }
}
