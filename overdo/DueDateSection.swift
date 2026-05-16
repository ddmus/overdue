//
//  DueDateSection.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import SwiftUI

/// A reusable "Due" form section: a date & time picker plus quick-set buttons.
/// Shared by the single-task sheet and the bulk-edit sheet.
struct DueDateSection: View {

    @Binding var dueDate: Date

    var body: some View {
        Section("Due") {
            DatePicker(
                "Date & time",
                selection: $dueDate,
                displayedComponents: [.date, .hourAndMinute]
            )

            quickButtons
        }
    }

    /// Quick controls for setting the due time relative to now.
    private var quickButtons: some View {
        HStack(spacing: 8) {
            quickButton("15 min", offset: 15 * 60)
            quickButton("1 hour", offset: 60 * 60)
            quickButton("3 hours", offset: 3 * 60 * 60)
            quickButton("Tomorrow", date: tomorrowMorning)
        }
        .frame(maxWidth: .infinity)
    }

    private func quickButton(_ title: String, offset: TimeInterval) -> some View {
        quickButton(title, date: .now.addingTimeInterval(offset))
    }

    private func quickButton(_ title: String, date: Date) -> some View {
        Button(title) { dueDate = date }
            .font(.footnote)
            .buttonStyle(.bordered)
    }

    /// 9:00 AM on the next day.
    private var tomorrowMorning: Date {
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: nextDay
        ) ?? nextDay
    }
}
