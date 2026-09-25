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
        if task.isIdea {
            ideaBody
        } else {
            scheduledBody
        }
    }

    /// Dateless presentation for Ideas — just the text with a lightbulb.
    private var ideaBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.caption)
                .foregroundStyle(.yellow)
                .accessibilityLabel("Idea")
            Text(task.text)
                .font(.body)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// Full presentation for scheduled tasks — due time plus the live countdown.
    private var scheduledBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if task.isUrgent {
                        Image(systemName: "alarm.waves.left.and.right.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Urgent")
                    }
                    Text(task.text)
                        .font(.body)
                }

                Text(showsDueDay ? task.dueDayTimeText(at: now) : task.dueTimeText())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            Text(task.relativeText(at: now))
                .font(.subheadline)
                .foregroundStyle(task.isOverdue(at: now) ? Color.red : Color.secondary)
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
