//
//  ContentView.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import SwiftUI

struct ContentView: View {

    /// Which task sheet, if any, is currently presented.
    private enum ActiveSheet: Identifiable {
        case create
        case edit(TodoItem)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let task): return task.id.uuidString
            }
        }
    }

    @State private var store = TaskStore()
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        NavigationStack {
            // Periodic timeline keeps the calculated relative-time labels live.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                taskList(now: context.date)
            }
            .navigationTitle("Overdo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New task")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                TaskSheet(mode: .create) { text, dueDate in
                    store.add(text: text, dueDate: dueDate)
                }
            case .edit(let task):
                TaskSheet(mode: .edit(task)) { text, dueDate in
                    var updated = task
                    updated.text = text
                    updated.dueDate = dueDate
                    store.update(updated)
                } onComplete: {
                    store.complete(task)
                }
            }
        }
    }

    @ViewBuilder
    private func taskList(now: Date) -> some View {
        if store.activeTasks.isEmpty {
            ContentUnavailableView(
                "No tasks",
                systemImage: "checkmark.circle",
                description: Text("Tap + to add your first task.")
            )
        } else {
            List {
                ForEach(store.activeTasks) { task in
                    TaskRow(task: task, now: now)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            activeSheet = .edit(task)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                store.complete(task)
                            } label: {
                                Label("Complete", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.delete(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
