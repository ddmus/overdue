//
//  TaskRow.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import SwiftUI

/// A single row in the task list: the task text plus the calculated relative-time field.
struct TaskRow: View {

    let task: TodoItem
    /// The current time, passed in so the relative label stays live.
    let now: Date
    /// When `true`, the due label includes the day (e.g. "Friday 15:00") — used in
    /// the Upcoming section where tasks fall on later days.
    var showsDueDay: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.text)
                    .font(.body)

                Text(task.relativeText(at: now))
                    .font(.caption)
                    .foregroundStyle(task.isOverdue(at: now) ? Color.red : Color.secondary)
            }

            Spacer(minLength: 0)

            Text(showsDueDay ? task.dueDayTimeText(at: now) : task.dueTimeText())
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        TaskRow(
            task: TodoItem(text: "Call the dentist", dueDate: .now.addingTimeInterval(18 * 60)),
            now: .now
        )
        TaskRow(
            task: TodoItem(text: "Submit the report", dueDate: .now.addingTimeInterval(-18 * 60)),
            now: .now
        )
    }
}
