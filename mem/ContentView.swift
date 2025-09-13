//
//  ContentView.swift
//  mem
//
//  Created by Noam Koren on 13/09/2025.
//

import SwiftUI
import UserNotifications

// MARK: - Data Models
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
    var dailyTime: Date // Time of day for notifications
    var scheduleType: ScheduleType
    var selectedWeekdays: Set<Int> // 1 = Sunday, 2 = Monday, etc.
    
    enum NotificationType: String, Codable, CaseIterable {
        case eachItem = "each_item"
        case listReminder = "list_reminder"
        
        var displayName: String {
            switch self {
            case .eachItem:
                return "Each item separately"
            case .listReminder:
                return "Single list reminder"
            }
        }
        
        var description: String {
            switch self {
            case .eachItem:
                return "Get a notification for each incomplete item"
            case .listReminder:
                return "Get a single reminder to check the list"
            }
        }
    }
    
    enum ScheduleType: String, Codable, CaseIterable {
        case daily = "daily"
        case weekdays = "weekdays"
        
        var displayName: String {
            switch self {
            case .daily:
                return "Every day"
            case .weekdays:
                return "Specific days"
            }
        }
        
        var description: String {
            switch self {
            case .daily:
                return "Send notifications every day"
            case .weekdays:
                return "Send notifications only on selected days"
            }
        }
    }
    
    init(isEnabled: Bool, notificationType: NotificationType, dailyTime: Date, scheduleType: ScheduleType = .daily, selectedWeekdays: Set<Int> = []) {
        self.isEnabled = isEnabled
        self.notificationType = notificationType
        self.dailyTime = dailyTime
        self.scheduleType = scheduleType
        self.selectedWeekdays = selectedWeekdays.isEmpty ? Set(1...7) : selectedWeekdays // Default to all days if empty
    }
}

// MARK: - Main App View
struct ContentView: View {
    @State private var lists: [ReminderList] = []
    @State private var selectedListID: UUID?
    @State private var activeSheet: ActiveSheet?
    
    private let listsKey = "SavedReminderLists"
    private let selectedListKey = "SelectedListID"
    private let appGroupID = "group.com.yourname.mem.shared" // Replace with your actual App Group ID
    
    private var sharedUserDefaults: UserDefaults {
        return UserDefaults(suiteName: appGroupID) ?? UserDefaults.standard
    }
    
    enum ActiveSheet: Identifiable {
        case listPicker
        case addList
        case editList(ReminderList)
        
        var id: String {
            switch self {
            case .listPicker:
                return "listPicker"
            case .addList:
                return "addList"
            case .editList(let list):
                return "editList_\(list.id.uuidString)"
            }
        }
    }
    
    var selectedList: ReminderList? {
        lists.first { $0.id == selectedListID }
    }
    
    var body: some View {
        NavigationView {
            if let currentList = selectedList {
                ReminderListView(
                    list: currentList,
                    onUpdate: { updatedList in
                        updateList(updatedList)
                    }
                )
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            activeSheet = .listPicker
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet")
                                Text("Lists")
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            // Swipe right to show list picker
                            if value.translation.width > 100 && abs(value.translation.height) < 50 {
                                activeSheet = .listPicker
                            }
                        }
                )
            } else {
                Text("Loading...")
                    .navigationTitle("Reminders")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .listPicker:
                ListPickerView(
                    lists: lists,
                    selectedListID: selectedListID,
                    onSelectList: { listID in
                        selectedListID = listID
                        saveSelectedList()
                        activeSheet = nil
                    },
                    onAddList: {
                        activeSheet = .addList
                    },
                    onEditList: { list in
                        activeSheet = .editList(list)
                    },
                    onDeleteList: { listID in
                        deleteList(listID)
                        // Close the sheet after deletion
                        activeSheet = nil
                    }
                )
            case .addList:
                AddListView { newListName, notificationSettings in
                    addNewList(name: newListName, notificationSettings: notificationSettings)
                    activeSheet = nil
                }
            case .editList(let list):
                EditListView(list: list) { updatedList in
                    updateList(updatedList)
                    activeSheet = nil
                }
            }
        }
        .onAppear {
            loadLists()
        }
    }
    
    private func deleteList(_ listID: UUID) {
        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else {
            print("⚠️ List not found")
            return
        }
        
        let listToDelete = lists[listIndex]
        
        // Don't allow deleting the default list if there are other lists
        if listToDelete.name == ReminderList.defaultListName && lists.count > 1 {
            print("⚠️ Cannot delete default list when other lists exist")
            return
        }
        
        print("🗑️ Deleting list: \(listToDelete.name)")
        
        // Cancel any notifications for this list before deleting
        cancelNotificationsForList(listID)
        
        // Remove the list
        lists.remove(at: listIndex)
        
        // Handle the case where we deleted all lists
        if lists.isEmpty {
            print("📝 All lists deleted, creating new default list")
            createDefaultList()
        }
        
        // If we deleted the selected list, select the first available list
        if selectedListID == listID {
            selectedListID = lists.first?.id
            saveSelectedList()
            print("📝 Switched to list: \(lists.first?.name ?? "None")")
        }
        
        saveLists()
    }
    
    private func addNewList(name: String, notificationSettings: NotificationSettings?) {
        let newList = ReminderList(name: name, notificationSettings: notificationSettings)
        lists.append(newList)
        selectedListID = newList.id
        saveSelectedList()
        saveLists()
        
        // Request notification permissions and schedule notifications if needed
        if let settings = notificationSettings, settings.isEnabled {
            requestNotificationPermission { granted in
                if granted {
                    scheduleNotificationsForList(newList)
                }
            }
        }
    }
    
    private func updateList(_ updatedList: ReminderList) {
        if let index = lists.firstIndex(where: { $0.id == updatedList.id }) {
            lists[index] = updatedList
            saveLists()
            
            // Reschedule notifications if the list has notification settings
            if let settings = updatedList.notificationSettings, settings.isEnabled {
                scheduleNotificationsForList(updatedList)
            }
        }
    }
    
    // MARK: - Notification Methods
    private func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    private func scheduleNotificationsForList(_ list: ReminderList) {
        guard let settings = list.notificationSettings, settings.isEnabled else { return }
        
        print("🔄 Scheduling notifications for list: \(list.name)")
        checkNotificationStatus()
        
        // Remove existing notifications for this list
        cancelNotificationsForList(list.id)
        
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: settings.dailyTime)
        let minute = calendar.component(.minute, from: settings.dailyTime)
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        switch settings.scheduleType {
        case .daily:
            // Schedule for every day
            switch settings.notificationType {
            case .eachItem:
                scheduleIndividualItemNotifications(for: list, at: dateComponents)
            case .listReminder:
                scheduleListReminderNotification(for: list, at: dateComponents)
            }
        case .weekdays:
            // Schedule for specific weekdays
            for weekday in settings.selectedWeekdays {
                var weekdayComponents = dateComponents
                weekdayComponents.weekday = weekday
                
                switch settings.notificationType {
                case .eachItem:
                    scheduleIndividualItemNotifications(for: list, at: weekdayComponents, weekday: weekday)
                case .listReminder:
                    scheduleListReminderNotification(for: list, at: weekdayComponents, weekday: weekday)
                }
            }
        }
    }
    
    private func scheduleIndividualItemNotifications(for list: ReminderList, at dateComponents: DateComponents, weekday: Int? = nil) {
        let incompleteReminders = list.reminders.filter { !$0.isCompleted }
        let weekdayText = weekday != nil ? " for weekday \(weekday!)" : ""
        
        print("📱 Scheduling \(incompleteReminders.count) individual notifications for list: \(list.name)\(weekdayText)")
        
        for (index, reminder) in incompleteReminders.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Reminder from \(list.name)"
            content.body = reminder.title
            content.sound = .default
            
            // Calculate proper time with second intervals to avoid grouping
            var adjustedDateComponents = dateComponents
            
            // Add seconds instead of minutes to avoid time overflow issues
            // Each notification will be 30 seconds apart
            if let minute = dateComponents.minute {
                let totalSeconds = index * 30 // 30 seconds between each notification
                let additionalMinutes = totalSeconds / 60
                let remainingSeconds = totalSeconds % 60
                
                adjustedDateComponents.minute = minute + additionalMinutes
                adjustedDateComponents.second = remainingSeconds
                
                // Handle minute overflow (ensure we don't go over 59 minutes)
                if let newMinute = adjustedDateComponents.minute, newMinute >= 60 {
                    if let hour = dateComponents.hour {
                        adjustedDateComponents.hour = (hour + (newMinute / 60)) % 24
                        adjustedDateComponents.minute = newMinute % 60
                    }
                }
            }
            
            let weekdayIdentifier = weekday != nil ? "_wd\(weekday!)" : ""
            print("⏰ Scheduling notification \(index + 1) at \(adjustedDateComponents.hour ?? 0):\(String(format: "%02d", adjustedDateComponents.minute ?? 0)):\(String(format: "%02d", adjustedDateComponents.second ?? 0))\(weekdayText)")
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: adjustedDateComponents, repeats: true)
            let identifier = "\(list.id.uuidString)_item_\(reminder.id.uuidString)\(weekdayIdentifier)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ Failed to schedule notification for '\(reminder.title)': \(error)")
                } else {
                    print("✅ Scheduled notification \(index + 1) for: \(reminder.title)")
                }
            }
        }
        
        // Check total pending notifications after a short delay to ensure they're all processed
        if weekday == nil || weekday == 1 { // Only run this once for weekday scheduling
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                    let listNotifications = requests.filter { $0.identifier.hasPrefix(list.id.uuidString) }
                    print("📊 Final count - notifications for this list: \(listNotifications.count)")
                    print("📊 Final count - total pending notifications: \(requests.count)")
                    
                    // Print details of scheduled notifications for debugging
                    for request in listNotifications {
                        if request.trigger is UNCalendarNotificationTrigger {
                            // Note: dateMatching is read-only, so we'll just print the notification content
                            print("🔍 Notification scheduled: \(request.content.body)")
                        }
                    }
                }
            }
        }
    }
    
    private func scheduleListReminderNotification(for list: ReminderList, at dateComponents: DateComponents, weekday: Int? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "Daily Reminder"
        content.body = "Don't forget to check the list \(list.name)"
        content.sound = .default
        
        let weekdayIdentifier = weekday != nil ? "_wd\(weekday!)" : ""
        let weekdayText = weekday != nil ? " for weekday \(weekday!)" : ""
        
        print("📅 Scheduling list reminder for: \(list.name)\(weekdayText)")
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let identifier = "\(list.id.uuidString)_list_reminder\(weekdayIdentifier)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule list reminder: \(error)")
            } else {
                print("✅ Scheduled list reminder for: \(list.name)")
            }
        }
    }
    
    private func cancelNotificationsForList(_ listID: UUID) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiersToCancel = requests
                .map { $0.identifier }
                .filter { $0.hasPrefix(listID.uuidString) }
            
            print("🗑️ Canceling \(identifiersToCancel.count) notifications for list")
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
        }
    }
    
    // Helper method to check notification system status
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                print("🔔 Notification Authorization: \(settings.authorizationStatus.rawValue)")
                print("🔔 Alert Setting: \(settings.alertSetting.rawValue)")
                print("🔔 Sound Setting: \(settings.soundSetting.rawValue)")
            }
        }
        
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                print("📊 Total pending notifications: \(requests.count)")
                if requests.count >= 60 {
                    print("⚠️ Warning: Approaching iOS notification limit (64 max)")
                }
            }
        }
    }
    
    // MARK: - Persistence Methods
    private func saveLists() {
        do {
            let data = try JSONEncoder().encode(lists)
            sharedUserDefaults.set(data, forKey: listsKey)
        } catch {
            print("Failed to save lists: \(error)")
        }
    }
    
    private func saveSelectedList() {
        if let selectedListID = selectedListID {
            sharedUserDefaults.set(selectedListID.uuidString, forKey: selectedListKey)
        }
    }
    
    private func loadSelectedList() {
        if let uuidString = sharedUserDefaults.string(forKey: selectedListKey),
           let uuid = UUID(uuidString: uuidString),
           lists.contains(where: { $0.id == uuid }) {
            selectedListID = uuid
        } else {
            selectedListID = lists.first?.id
            saveSelectedList()
        }
    }
    
    private func loadLists() {
        // First, try to migrate any existing data from standard UserDefaults to shared container
        migrateToSharedContainer()
        
        // Try to load existing lists from shared container
        if let data = sharedUserDefaults.data(forKey: listsKey) {
            do {
                lists = try JSONDecoder().decode([ReminderList].self, from: data)
                print("✅ Loaded \(lists.count) lists from shared container")
            } catch {
                print("Failed to load lists from shared container: \(error)")
                createDefaultList()
            }
        } else {
            // Check for old reminders data and migrate
            migrateOldData()
        }
        
        // Ensure we have a default list
        if lists.isEmpty {
            createDefaultList()
        }
        
        // Load the last selected list
        loadSelectedList()
    }
    
    private func migrateToSharedContainer() {
        // Check if we already have data in shared container
        if sharedUserDefaults.data(forKey: listsKey) != nil {
            print("📱 Data already exists in shared container, skipping migration")
            return
        }
        
        // Check if we have data in standard UserDefaults to migrate
        if let existingData = UserDefaults.standard.data(forKey: listsKey) {
            print("📱 Migrating existing lists data to shared container...")
            sharedUserDefaults.set(existingData, forKey: listsKey)
            
            // Also migrate selected list ID if it exists
            if let selectedID = UserDefaults.standard.string(forKey: selectedListKey) {
                print("📱 Migrating selected list ID to shared container...")
                sharedUserDefaults.set(selectedID, forKey: selectedListKey)
            }
            
            // Remove from standard UserDefaults to avoid confusion
            UserDefaults.standard.removeObject(forKey: listsKey)
            UserDefaults.standard.removeObject(forKey: selectedListKey)
            
            print("✅ Migration completed!")
        } else {
            print("📱 No existing data found in standard UserDefaults to migrate")
        }
    }
    
    private func createDefaultList() {
        let defaultList = ReminderList(name: ReminderList.defaultListName)
        lists = [defaultList]
        selectedListID = defaultList.id
    }
    
    private func migrateOldData() {
        // Try to load old reminders format and migrate
        if let data = sharedUserDefaults.data(forKey: "SavedReminders") {
            do {
                let oldReminders = try JSONDecoder().decode([Reminder].self, from: data)
                let defaultList = ReminderList(name: ReminderList.defaultListName, reminders: oldReminders)
                lists = [defaultList]
                selectedListID = defaultList.id
                
                // Remove old data
                sharedUserDefaults.removeObject(forKey: "SavedReminders")
                saveLists()
            } catch {
                createDefaultList()
            }
        } else {
            createDefaultList()
        }
    }
}

// MARK: - ReminderListView
struct ReminderListView: View {
    let list: ReminderList
    let onUpdate: (ReminderList) -> Void
    
    // Unified editing system
    @State private var editingReminderID: UUID? = nil // nil means editing new reminder
    @State private var editingTitle = ""
    @State private var editingHasDueDate = false
    @State private var editingDueDate = Date()
    @State private var isActivelyEditing = false // Separate state for UI control
    
    var body: some View {
        List {
            ForEach(list.reminders) { reminder in
                if editingReminderID == reminder.id {
                    // Show editing interface for this reminder
                    UnifiedEditingRow(
                        title: $editingTitle,
                        hasDueDate: $editingHasDueDate,
                        dueDate: $editingDueDate,
                        isActivelyEditing: $isActivelyEditing,
                        onSave: saveCurrentEdit,
                        onCancel: stopEditing
                    )
                } else {
                    // Show regular reminder row
                    ReminderDisplayRow(reminder: reminder, onTap: {
                        startEditingReminder(reminder)
                    }, onToggleComplete: { updatedReminder in
                        updateReminder(id: updatedReminder.id, title: updatedReminder.title, dueDate: updatedReminder.dueDate)
                        var updatedList = list
                        if let index = updatedList.reminders.firstIndex(where: { $0.id == updatedReminder.id }) {
                            updatedList.reminders[index] = updatedReminder
                            onUpdate(updatedList)
                        }
                    })
                }
            }
            .onDelete(perform: deleteReminders)
            
            // New reminder area
            if editingReminderID == nil {
                // Always show editing interface when editingReminderID is nil (new reminder mode)
                UnifiedEditingRow(
                    title: $editingTitle,
                    hasDueDate: $editingHasDueDate,
                    dueDate: $editingDueDate,
                    isActivelyEditing: $isActivelyEditing,
                    onSave: saveCurrentEdit,
                    onCancel: stopEditing
                )
                .onAppear {
                    print("📝 UnifiedEditingRow appeared - editingReminderID: \(String(describing: editingReminderID))")
                    print("📝 editingTitle: '\(editingTitle)', isActivelyEditing: \(isActivelyEditing)")
                }
            } else {
                // Show "Add New Reminder" button when editing existing reminder
                Button(action: {
                    startEditingNewReminder()
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.blue)
                        Text("Add New Reminder")
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .navigationTitle(list.name)
    }
    
    private func deleteReminders(offsets: IndexSet) {
        var updatedList = list
        updatedList.reminders.remove(atOffsets: offsets)
        onUpdate(updatedList)
    }
    
    // MARK: - Unified Editing Methods
    
    private func startEditingReminder(_ reminder: Reminder) {
        editingReminderID = reminder.id
        editingTitle = reminder.title
        editingHasDueDate = reminder.dueDate != nil
        editingDueDate = reminder.dueDate ?? Date()
        isActivelyEditing = true
    }
    
    private func startEditingNewReminder() {
        editingReminderID = nil
        editingTitle = ""
        editingHasDueDate = false
        editingDueDate = Date()
        isActivelyEditing = true
    }
    
    private func saveCurrentEdit() {
        let trimmedTitle = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            stopEditing()
            return
        }
        
        if let reminderID = editingReminderID {
            // Update existing reminder
            updateReminder(id: reminderID, title: trimmedTitle, dueDate: editingHasDueDate ? editingDueDate : nil)
        } else {
            // Create new reminder
            addNewReminder(title: trimmedTitle, dueDate: editingHasDueDate ? editingDueDate : nil)
        }
        
        // Continue editing a new reminder for rapid entry
        startEditingNewReminder()
    }
    
    private func stopEditing() {
        editingReminderID = nil
        editingTitle = ""
        editingHasDueDate = false
        editingDueDate = Date()
        isActivelyEditing = false
    }
    
    private func addNewReminder(title: String, dueDate: Date?) {
        let newReminder = Reminder(title: title, dueDate: dueDate)
        var updatedList = list
        updatedList.reminders.append(newReminder)
        onUpdate(updatedList)
    }
    
    private func updateReminder(id: UUID, title: String, dueDate: Date?) {
        var updatedList = list
        if let index = updatedList.reminders.firstIndex(where: { $0.id == id }) {
            updatedList.reminders[index].title = title
            updatedList.reminders[index].dueDate = dueDate
            onUpdate(updatedList)
        }
    }
}

// MARK: - ListPickerView
struct ListPickerView: View {
    let lists: [ReminderList]
    let selectedListID: UUID?
    let onSelectList: (UUID) -> Void
    let onAddList: () -> Void
    let onEditList: (ReminderList) -> Void
    let onDeleteList: (UUID) -> Void
    
    @Environment(\.presentationMode) var presentationMode
    
    private func shouldAllowDeletion(_ list: ReminderList) -> Bool {
        // Allow deleting any list if it's the only one, otherwise don't allow deleting the default list
        return list.name != ReminderList.defaultListName || lists.count == 1
    }
    
    var body: some View {
        NavigationView {
            List {
                Section("My Lists") {
                    ForEach(lists) { list in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(list.name)
                                        .foregroundColor(.primary)
                                        .font(.headline)
                                    
                                    if list.notificationSettings?.isEnabled == true {
                                        Image(systemName: "bell.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                }
                                
                                HStack {
                                    Text("\(list.reminders.count) reminders")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    
                                let incompleteCount = list.reminders.filter({ !$0.isCompleted }).count
                                if incompleteCount > 0 {
                                    Text("• \(incompleteCount) incomplete")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                                }
                            }
                            
                            Spacer()
                            
                            if selectedListID == list.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectList(list.id)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: shouldAllowDeletion(list)) {
                            // Left swipe - Delete action
                            if shouldAllowDeletion(list) {
                                Button(role: .destructive, action: {
                                    // Add small delay to prevent gesture conflicts
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        onDeleteList(list.id)
                                    }
                                }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            // Right swipe - Edit action
                            Button(action: {
                                // Add small delay to prevent gesture conflicts
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    onEditList(list)
                                }
                            }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let list = lists[index]
                            if shouldAllowDeletion(list) {
                                onDeleteList(list.id)
                            }
                        }
                    }
                }
                
                Section {
                    Button(action: onAddList) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("Add New List")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Choose List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Text("💡 Tip")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Text("Swipe left to delete • Swipe right to edit")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
        }
        .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - EditListView
struct EditListView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var listName: String
    @State private var enableNotifications: Bool
    @State private var notificationType: NotificationSettings.NotificationType
    @State private var notificationTime: Date
    @State private var scheduleType: NotificationSettings.ScheduleType
    @State private var selectedWeekdays: Set<Int>
    
    let list: ReminderList
    let onSave: (ReminderList) -> Void
    
    init(list: ReminderList, onSave: @escaping (ReminderList) -> Void) {
        self.list = list
        self.onSave = onSave
        
        // Initialize state from existing list
        self._listName = State(initialValue: list.name)
        self._enableNotifications = State(initialValue: list.notificationSettings?.isEnabled ?? false)
        self._notificationType = State(initialValue: list.notificationSettings?.notificationType ?? .eachItem)
        self._notificationTime = State(initialValue: list.notificationSettings?.dailyTime ?? Date())
        self._scheduleType = State(initialValue: list.notificationSettings?.scheduleType ?? .daily)
        self._selectedWeekdays = State(initialValue: list.notificationSettings?.selectedWeekdays ?? Set(1...7))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("List Details")) {
                    TextField("List name", text: $listName)
                }
                
                Section(header: Text("Daily Notifications")) {
                    Toggle("Enable daily reminders", isOn: $enableNotifications)
                    
                    if enableNotifications {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notification Type")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Picker("Notification Type", selection: $notificationType) {
                                    ForEach(NotificationSettings.NotificationType.allCases, id: \.self) { type in
                                        VStack(alignment: .leading) {
                                            Text(type.displayName)
                                                .font(.headline)
                                            Text(type.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Schedule")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Picker("Schedule", selection: $scheduleType) {
                                    Text("Daily").tag(NotificationSettings.ScheduleType.daily)
                                    Text("Custom").tag(NotificationSettings.ScheduleType.weekdays)
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            
                            if scheduleType == .weekdays {
                                WeekdaySelector(selectedWeekdays: $selectedWeekdays)
                                    .padding(.vertical, 4)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Reminder Time")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                DatePicker("Daily reminder time", selection: $notificationTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .animation(.easeInOut(duration: 0.3), value: scheduleType)
                    }
                }
                
                Section(header: Text("List Statistics")) {
                    HStack {
                        Text("Total reminders")
                        Spacer()
                        Text("\(list.reminders.count)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Completed")
                        Spacer()
                        Text("\(list.reminders.filter { $0.isCompleted }.count)")
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("Incomplete")
                        Spacer()
                        Text("\(list.reminders.filter { !$0.isCompleted }.count)")
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle("Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveList()
                    }
                    .disabled(listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveList() {
        let trimmedName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        let notificationSettings = enableNotifications ? NotificationSettings(
            isEnabled: true,
            notificationType: notificationType,
            dailyTime: notificationTime,
            scheduleType: scheduleType,
            selectedWeekdays: selectedWeekdays
        ) : nil
        
        var updatedList = list
        updatedList.name = trimmedName
        updatedList.notificationSettings = notificationSettings
        
        onSave(updatedList)
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - WeekdaySelector
struct WeekdaySelector: View {
    @Binding var selectedWeekdays: Set<Int>
    
    private let weekdays: [(Int, String)] = [
        (1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"),
        (5, "Thu"), (6, "Fri"), (7, "Sat")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select days")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(weekdays, id: \.0) { weekdayData in
                    let weekdayNumber = weekdayData.0
                    let weekdayName = weekdayData.1
                    
                    Button(action: {
                        if selectedWeekdays.contains(weekdayNumber) {
                            selectedWeekdays.remove(weekdayNumber)
                        } else {
                            selectedWeekdays.insert(weekdayNumber)
                        }
                    }) {
                        Text(weekdayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(selectedWeekdays.contains(weekdayNumber) ? .white : .blue)
                            .frame(width: 40, height: 30)
                            .background(selectedWeekdays.contains(weekdayNumber) ? Color.blue : Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            if selectedWeekdays.isEmpty {
                Text("Please select at least one day")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - AddListView
struct AddListView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var listName = ""
    @State private var enableNotifications = false
    @State private var notificationType: NotificationSettings.NotificationType = .eachItem
    @State private var notificationTime = Date()
    @State private var scheduleType: NotificationSettings.ScheduleType = .daily
    @State private var selectedWeekdays: Set<Int> = Set(1...7) // Default to all days
    
    let onSave: (String, NotificationSettings?) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("List Details")) {
                    TextField("List name", text: $listName)
                }
                
                Section(header: Text("Daily Notifications")) {
                    Toggle("Enable daily reminders", isOn: $enableNotifications)
                    
                    if enableNotifications {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notification Type")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Picker("Notification Type", selection: $notificationType) {
                                    ForEach(NotificationSettings.NotificationType.allCases, id: \.self) { type in
                                        VStack(alignment: .leading) {
                                            Text(type.displayName)
                                                .font(.headline)
                                            Text(type.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Schedule")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Picker("Schedule", selection: $scheduleType) {
                                    Text("Daily").tag(NotificationSettings.ScheduleType.daily)
                                    Text("Custom").tag(NotificationSettings.ScheduleType.weekdays)
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            
                            if scheduleType == .weekdays {
                                WeekdaySelector(selectedWeekdays: $selectedWeekdays)
                                    .padding(.vertical, 4)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Reminder Time")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                DatePicker("Daily reminder time", selection: $notificationTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .animation(.easeInOut(duration: 0.3), value: scheduleType)
                    }
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveList()
                    }
                    .disabled(listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveList() {
        let trimmedName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        let notificationSettings = enableNotifications ? NotificationSettings(
            isEnabled: true,
            notificationType: notificationType,
            dailyTime: notificationTime,
            scheduleType: scheduleType,
            selectedWeekdays: selectedWeekdays
        ) : nil
        
        onSave(trimmedName, notificationSettings)
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - UnifiedEditingRow
struct UnifiedEditingRow: View {
    @Binding var title: String
    @Binding var hasDueDate: Bool
    @Binding var dueDate: Date
    @Binding var isActivelyEditing: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Button(action: {}) {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(true)
                
                if isActivelyEditing || !title.isEmpty {
                    // Show TextField when focused or has content
                    TextField("New Reminder", text: $title)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(onSave)
                        .onAppear {
                            print("🟢 TextField appeared - focused: \(isFocused), title: '\(title)'")
                            // Ensure focus is set when TextField appears
                            if isActivelyEditing && !isFocused {
                                DispatchQueue.main.async {
                                    isFocused = true
                                }
                            }
                        }
                } else {
                    // Show placeholder when not focused and empty
                    HStack {
                        Text("New Reminder")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        print("🎯 New Reminder tapped!")
                        isActivelyEditing = true
                        // Use DispatchQueue to ensure focus is set after view updates
                        DispatchQueue.main.async {
                            isFocused = true
                            print("🎯 Focus set - isFocused: \(isFocused)")
                        }
                    }
                    .onAppear {
                        print("🔴 Placeholder appeared - focused: \(isFocused), title: '\(title)'")
                    }
                }
            }
            
            if isFocused || !title.isEmpty {
                HStack {
                    Button(action: {
                        hasDueDate.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: hasDueDate ? "calendar.badge.minus" : "calendar.badge.plus")
                            Text(hasDueDate ? "Remove due date" : "Add due date")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Save") {
                            onSave()
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            if (isFocused || !title.isEmpty) && hasDueDate {
                DatePicker("Due date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .padding(.leading, 32)
                    .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ReminderDisplayRow
struct ReminderDisplayRow: View {
    let reminder: Reminder
    let onTap: () -> Void
    let onToggleComplete: (Reminder) -> Void
    
    var body: some View {
        HStack {
            Button(action: {
                var updatedReminder = reminder
                updatedReminder.isCompleted.toggle()
                onToggleComplete(updatedReminder)
            }) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(reminder.isCompleted ? .green : .gray)
                    .font(.title2)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .strikethrough(reminder.isCompleted)
                    .foregroundColor(reminder.isCompleted ? .secondary : .primary)
                
                if let dueDate = reminder.dueDate {
                    Text(dueDate, style: .date)
                        .font(.caption)
                        .foregroundColor(isOverdue(dueDate) ? .red : .secondary)
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        return date < Date() && !reminder.isCompleted
    }
}

#Preview {
    ContentView()
}
