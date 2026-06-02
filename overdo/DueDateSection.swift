//
//  DueDateSection.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import SwiftUI

/// A reusable "Due" form section: a date & time picker plus controls for adjusting
/// the selected due date. Shared by the single-task sheet and the bulk-edit sheet.
struct DueDateSection: View {

    @Binding var dueDate: Date

    /// On-the-hour presets, applied to the currently selected day.
    private let hourOptions = [7, 9, 12, 18, 20]

    var body: some View {
        Section("Due") {
            DatePicker(
                "Date & time",
                selection: $dueDate,
                displayedComponents: [.date, .hourAndMinute]
            )

            // Set the time on the currently selected day.
            FlowLayout(spacing: 8) {
                ForEach(hourOptions, id: \.self) { hour in
                    Button(hourLabel(hour)) {
                        dueDate = dateOnSelectedDay(hour: hour)
                    }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)

            // Nudge the selected date/time up or down.
            FlowLayout(spacing: 8) {
                adjustButton("-1 d", .day, -1)
                adjustButton("-1 h", .hour, -1)
                adjustButton("-10 min", .minute, -10)
                adjustButton("+10 min", .minute, 10)
                adjustButton("+1 h", .hour, 1)
                adjustButton("+1 d", .day, 1)
            }
            .padding(.vertical, 4)
        }
    }

    private func adjustButton(_ title: String, _ component: Calendar.Component, _ value: Int) -> some View {
        Button(title) {
            dueDate = Calendar.current.date(byAdding: component, value: value, to: dueDate) ?? dueDate
        }
        .font(.footnote)
        .buttonStyle(.bordered)
    }

    /// `hour:00` on the day currently selected in the picker.
    private func dateOnSelectedDay(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: dueDate) ?? dueDate
    }

    private func hourLabel(_ hour: Int) -> String {
        dateOnSelectedDay(hour: hour).formatted(.dateTime.hour().minute())
    }
}
