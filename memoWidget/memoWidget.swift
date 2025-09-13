//
//  memoWidget.swift
//  memoWidget
//
//  Created by Noam Koren on 13/09/2025.
//

import WidgetKit
import SwiftUI

// MARK: - Shared Data Models
// These models match exactly with the main app's data models

struct Reminder: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    var createdDate: Date
    
    init(title: String, isCompleted: Bool = false, dueDate: Date? = nil) {
        self.id = UUID()
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.createdDate = Date()
    }
}

struct ReminderList: Identifiable, Codable {
    let id: UUID
    var name: String
    var reminders: [Reminder]
    var createdDate: Date
    var notificationSettings: NotificationSettings?
    
    static let defaultListName = "Reminders"
    
    init(name: String, reminders: [Reminder] = [], notificationSettings: NotificationSettings? = nil) {
        self.id = UUID()
        self.name = name
        self.reminders = reminders
        self.createdDate = Date()
        self.notificationSettings = notificationSettings
    }
}

struct NotificationSettings: Codable {
    var isEnabled: Bool
    var notificationType: NotificationType
    var dailyTime: Date
    var scheduleType: ScheduleType
    var selectedWeekdays: Set<Int>
    
    enum NotificationType: String, Codable, CaseIterable {
        case eachItem = "each_item"
        case listReminder = "list_reminder"
    }
    
    enum ScheduleType: String, Codable, CaseIterable {
        case daily = "daily"
        case weekdays = "weekdays"
    }
    
    init(isEnabled: Bool, notificationType: NotificationType, dailyTime: Date, scheduleType: ScheduleType = .daily, selectedWeekdays: Set<Int> = []) {
        self.isEnabled = isEnabled
        self.notificationType = notificationType
        self.dailyTime = dailyTime
        self.scheduleType = scheduleType
        self.selectedWeekdays = selectedWeekdays.isEmpty ? Set(1...7) : selectedWeekdays
    }
}

// MARK: - Widget Entry
struct MemWidgetEntry: TimelineEntry {
    let date: Date
    let reminders: [Reminder]
    let listName: String
}

// MARK: - Timeline Provider
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> MemWidgetEntry {
        return MemWidgetEntry(
            date: Date(),
            reminders: [
                Reminder(title: "Sample reminder", isCompleted: false, dueDate: nil),
                Reminder(title: "Another task", isCompleted: true, dueDate: Date()),
                Reminder(title: "Important meeting", isCompleted: false, dueDate: Date().addingTimeInterval(3600))
            ],
            listName: "Reminders"
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (MemWidgetEntry) -> ()) {
        let entry = loadReminders()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<MemWidgetEntry>) -> ()) {
        let entry = loadReminders()
        
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        
        completion(timeline)
    }
    
    private func loadReminders() -> MemWidgetEntry {
        // Load data from shared UserDefaults (shared with main app)
        let listsKey = "SavedReminderLists"
        let selectedListKey = "SelectedListID"
        let appGroupID = "group.com.yourname.mem.shared" // Replace with your actual App Group ID
        
        // Use shared UserDefaults container
        let sharedUserDefaults = UserDefaults(suiteName: appGroupID) ?? UserDefaults.standard
        
        var reminders: [Reminder] = []
        var listName = "Reminders"
        
        print("Widget: Loading reminders from shared UserDefaults...")
        print("Widget: Using app group: \(appGroupID)")
        
        // Debug: Print all UserDefaults keys
        let allKeys = sharedUserDefaults.dictionaryRepresentation().keys
        print("Widget: All UserDefaults keys: \(Array(allKeys))")
        
        // Check if the specific keys exist
        let hasListsData = sharedUserDefaults.data(forKey: listsKey) != nil
        let hasSelectedListID = sharedUserDefaults.string(forKey: selectedListKey) != nil
        print("Widget: Has lists data: \(hasListsData)")
        print("Widget: Has selected list ID: \(hasSelectedListID)")
        
        if let data = sharedUserDefaults.data(forKey: listsKey) {
            print("Widget: Found data in UserDefaults, size: \(data.count) bytes")
            
            // Debug: Print raw data as string to see what we're trying to decode
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Widget: Raw JSON data: \(jsonString.prefix(200))...")
            }
            
            do {
                let lists = try JSONDecoder().decode([ReminderList].self, from: data)
                print("Widget: Successfully decoded \(lists.count) lists")
                
                // Print details about each list
                for (index, list) in lists.enumerated() {
                    print("Widget: List \(index): '\(list.name)' with \(list.reminders.count) reminders")
                    for (reminderIndex, reminder) in list.reminders.enumerated() {
                        print("Widget:   Reminder \(reminderIndex): '\(reminder.title)' (completed: \(reminder.isCompleted))")
                    }
                }
                
                // Get selected list or first list
                var selectedList: ReminderList?
                if let selectedIDString = sharedUserDefaults.string(forKey: selectedListKey),
                   let selectedID = UUID(uuidString: selectedIDString) {
                    selectedList = lists.first { $0.id == selectedID }
                    print("Widget: Found selected list with ID: \(selectedIDString)")
                } else {
                    print("Widget: No selected list ID found")
                }
                
                if selectedList == nil {
                    selectedList = lists.first
                    print("Widget: Using first list as fallback")
                }
                
                if let list = selectedList {
                    listName = list.name
                    print("Widget: Using list '\(listName)' with \(list.reminders.count) reminders")
                    
                    // Get incomplete reminders first, then completed ones
                    let incompleteReminders = list.reminders.filter { !$0.isCompleted }
                    let completedReminders = list.reminders.filter { $0.isCompleted }
                    
                    print("Widget: Found \(incompleteReminders.count) incomplete, \(completedReminders.count) completed")
                    
                    // Take up to 6 reminders total (prioritize incomplete)
                    let allReminders = incompleteReminders + completedReminders
                    reminders = Array(allReminders.prefix(6))
                    print("Widget: Final reminders count: \(reminders.count)")
                    
                    // Print final reminders
                    for (index, reminder) in reminders.enumerated() {
                        print("Widget: Final reminder \(index): '\(reminder.title)' (completed: \(reminder.isCompleted))")
                    }
                } else {
                    print("Widget: No lists found after decoding")
                }
            } catch {
                print("Widget: Failed to decode reminders: \(error)")
                print("Widget: Error details: \(error.localizedDescription)")
                if let decodingError = error as? DecodingError {
                    print("Widget: Decoding error description: \(decodingError)")
                }
            }
        } else {
            print("Widget: No data found in UserDefaults for key: \(listsKey)")
            print("Widget: Checking if shared UserDefaults has any data at all...")
            let allData = sharedUserDefaults.dictionaryRepresentation()
            print("Widget: Total shared UserDefaults entries: \(allData.count)")
        }
        
        let entry = MemWidgetEntry(
            date: Date(),
            reminders: reminders,
            listName: listName
        )
        
        print("Widget: Returning entry with \(entry.reminders.count) reminders for list '\(entry.listName)'")
        return entry
    }
}

// MARK: - Widget Views
struct memoWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

struct SmallWidgetView: View {
    let entry: MemWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text(entry.listName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(entry.reminders.prefix(3)), id: \.id) { reminder in
                    HStack(spacing: 4) {
                        Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(reminder.isCompleted ? .green : .gray)
                            .font(.caption2)
                        
                        Text(reminder.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .strikethrough(reminder.isCompleted)
                            .foregroundColor(reminder.isCompleted ? .secondary : .primary)
                        
                        Spacer()
                    }
                }
                
                if entry.reminders.count > 3 {
                    Text("+\(entry.reminders.count - 3) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if entry.reminders.isEmpty {
                    Text("No reminders")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.all, 12)
    }
}

struct MediumWidgetView: View {
    let entry: MemWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.blue)
                Text(entry.listName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                
                let incompleteCount = entry.reminders.filter { !$0.isCompleted }.count
                if incompleteCount > 0 {
                    Text("\(incompleteCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
            
            Divider()
            
            if entry.reminders.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                            .font(.title2)
                        Text("All done!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entry.reminders.prefix(4)), id: \.id) { reminder in
                        ReminderRowView(reminder: reminder)
                    }
                    
                    if entry.reminders.count > 4 {
                        HStack {
                            Spacer()
                            Text("+ \(entry.reminders.count - 4) more reminders")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.all, 16)
    }
}

struct LargeWidgetView: View {
    let entry: MemWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.blue)
                    .font(.title3)
                Text(entry.listName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    let incompleteCount = entry.reminders.filter { !$0.isCompleted }.count
                    let totalCount = entry.reminders.count
                    
                    Text("\(incompleteCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    
                    Text("of \(totalCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            if entry.reminders.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                            .font(.title2)
                        Text("All done!")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.reminders, id: \.id) { reminder in
                        ReminderRowView(reminder: reminder, showDueDate: true)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.all, 16)
    }
}

struct ReminderRowView: View {
    let reminder: Reminder
    var showDueDate: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(reminder.isCompleted ? .green : .gray)
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.system(size: 13))
                    .lineLimit(showDueDate ? 2 : 1)
                    .strikethrough(reminder.isCompleted)
                    .foregroundColor(reminder.isCompleted ? .secondary : .primary)
                
                if showDueDate, let dueDate = reminder.dueDate {
                    Text(dueDate, style: .date)
                        .font(.caption2)
                        .foregroundColor(isOverdue(dueDate) ? .red : .secondary)
                }
            }
            
            Spacer()
        }
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        return date < Date() && !reminder.isCompleted
    }
}

// MARK: - Widget Configuration
struct memoWidget: Widget {
    let kind: String = "memoWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                memoWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                memoWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Reminders")
        .description("View your reminders at a glance")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews
#Preview(as: .systemSmall) {
    memoWidget()
} timeline: {
    MemWidgetEntry(
        date: Date(),
        reminders: [
            Reminder(title: "Buy groceries", isCompleted: false, dueDate: nil),
            Reminder(title: "Call dentist", isCompleted: true, dueDate: Date()),
            Reminder(title: "Walk the dog", isCompleted: false, dueDate: nil)
        ],
        listName: "My Tasks"
    )
}

#Preview(as: .systemMedium) {
    memoWidget()
} timeline: {
    MemWidgetEntry(
        date: Date(),
        reminders: [
            Reminder(title: "Buy groceries", isCompleted: false, dueDate: nil),
            Reminder(title: "Call dentist", isCompleted: true, dueDate: Date()),
            Reminder(title: "Finish project report", isCompleted: false, dueDate: Date().addingTimeInterval(86400))
        ],
        listName: "My Tasks"
    )
}

#Preview(as: .systemLarge) {
    memoWidget()
} timeline: {
    MemWidgetEntry(
        date: Date(),
        reminders: [
            Reminder(title: "Buy groceries for the weekend party", isCompleted: false, dueDate: Date().addingTimeInterval(3600)),
            Reminder(title: "Call dentist for appointment", isCompleted: true, dueDate: Date()),
            Reminder(title: "Finish project report", isCompleted: false, dueDate: Date().addingTimeInterval(86400))
        ],
        listName: "My Tasks"
    )
}
