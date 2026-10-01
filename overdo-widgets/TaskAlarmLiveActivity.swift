//
//  TaskAlarmLiveActivity.swift
//  overdo-widgets
//
//  Created by tomas on 02.10.2026.
//

import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Live Activity AlarmKit shows for an urgent task's alarm — on the Lock Screen,
/// in the Dynamic Island and in StandBy. Mostly seen while the alarm is snoozed: it
/// counts down to the next ring and offers Stop.
struct TaskAlarmLiveActivity: Widget {

    private static let iconName = "alarm.waves.left.and.right.fill"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<TaskAlarmMetadata>.self) { context in
            lockScreenView(context)
                .padding()
                .activitySystemActionForegroundColor(context.attributes.tintColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.presentation.alert.title)
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: Self.iconName)
                            .foregroundStyle(context.attributes.tintColor)
                    }
                    .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    remainingText(context.state)
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        statusText(context.state)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        stopButton(context)
                    }
                }
            } compactLeading: {
                Image(systemName: Self.iconName)
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                remainingText(context.state)
                    .monospacedDigit()
                    .foregroundStyle(context.attributes.tintColor)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: Self.iconName)
                    .foregroundStyle(context.attributes.tintColor)
            }
            .keylineTint(context.attributes.tintColor)
        }
    }

    private func lockScreenView(_ context: ActivityViewContext<AlarmAttributes<TaskAlarmMetadata>>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: Self.iconName)
                .font(.title2)
                .foregroundStyle(context.attributes.tintColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.presentation.alert.title)
                    .font(.headline)
                    .lineLimit(2)
                statusText(context.state)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            remainingText(context.state)
                .font(.title.monospacedDigit())
                .foregroundStyle(context.attributes.tintColor)
                .frame(maxWidth: 110, alignment: .trailing)

            stopButton(context)
        }
    }

    /// A live countdown to the next ring while snoozed; otherwise a short state label.
    @ViewBuilder
    private func remainingText(_ state: AlarmPresentationState) -> some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...max(Date.now, countdown.fireDate), countsDown: true)
                .multilineTextAlignment(.trailing)
        case .paused:
            Text("Paused")
        default:
            Text("Now")
        }
    }

    private func statusText(_ state: AlarmPresentationState) -> Text {
        switch state.mode {
        case .countdown: Text("Snoozed")
        case .paused: Text("Paused")
        default: Text("Ringing")
        }
    }

    private func stopButton(_ context: ActivityViewContext<AlarmAttributes<TaskAlarmMetadata>>) -> some View {
        Button(intent: StopTaskAlarmIntent(alarmID: context.state.alarmID)) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(context.attributes.tintColor)
        .accessibilityLabel("Stop alarm")
    }
}
