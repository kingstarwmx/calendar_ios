import Foundation
import EventKit
import UIKit

final class DeviceCalendarService {
    enum PermissionStatus {
        case notDetermined
        case denied
        case authorized

        init(authorizationStatus: EKAuthorizationStatus) {
            switch authorizationStatus {
            case .authorized, .fullAccess:
                self = .authorized
            case .restricted, .denied:
                self = .denied
            case .notDetermined:
                self = .notDetermined
            @unknown default:
                self = .denied
            }
        }
    }

    private let eventStore = EKEventStore()
    private let calendarQueue = DispatchQueue(label: "DeviceCalendarServiceQueue", qos: .userInitiated)

    private(set) var availableCalendars: [EKCalendar] = []
    private(set) var permissionStatus: PermissionStatus

    // 应用专属日历标识符
    private let appCalendarTitle = "我的日历"
    private let appCalendarIdentifierKey = "AppCalendarIdentifier"

    init() {
        permissionStatus = PermissionStatus(authorizationStatus: EKEventStore.authorizationStatus(for: .event))
    }

    func requestCalendarPermission() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            permissionStatus = .authorized
            await refreshCalendars()
            return true
        case .denied, .restricted:
            permissionStatus = .denied
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    self.permissionStatus = granted ? .authorized : .denied
                    Task { await self.refreshCalendars() }
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            permissionStatus = .denied
            return false
        }
    }

    func fetchDeviceEvents(in range: DateInterval, calendars: [EKCalendar]? = nil) async throws -> [Event] {
        guard permissionStatus == .authorized else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            calendarQueue.async {
                let targetCalendars = calendars ?? self.availableCalendars

                // 调试：打印使用的日历
                // print("📅 获取事件，使用 \(targetCalendars.count) 个日历:")
                // for calendar in targetCalendars {
                //     print("   - \(calendar.title) (\(calendar.allowsContentModifications ? "可编辑" : "只读"))")
                // }

                let predicate = self.eventStore.predicateForEvents(
                    withStart: range.start,
                    end: range.end,
                    calendars: targetCalendars
                )
                let ekEvents = self.eventStore.events(matching: predicate)
                // print("   ✅ 一次性获取到 \(ekEvents.count) 个事件")

                let events = ekEvents.map { self.makeEvent(from: $0) }
                continuation.resume(returning: events)
            }
        }
    }

    /// 创建新事件到应用日历
    func createEvent(_ event: Event) async throws -> Event {
        guard permissionStatus == .authorized else {
            throw NSError(domain: "DeviceCalendarService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Calendar permission not granted"])
        }

        // 先获取或创建应用日历
        let appCalendar = try await getOrCreateAppCalendar()

        return try await withCheckedThrowingContinuation { continuation in
            calendarQueue.async {
                let ekEvent = EKEvent(eventStore: self.eventStore)
                ekEvent.calendar = appCalendar
                ekEvent.title = event.title
                ekEvent.startDate = event.startDate
                ekEvent.endDate = event.endDate
                ekEvent.location = event.location.isEmpty ? nil : event.location
                ekEvent.isAllDay = event.isAllDay
                ekEvent.notes = event.description
                ekEvent.url = event.url.flatMap(URL.init(string:))
                ekEvent.alarms = event.reminders.map { EKAlarm(absoluteDate: $0) }

                do {
                    try self.eventStore.save(ekEvent, span: .thisEvent, commit: true)

                    // 返回更新后的 Event，包含设备事件 ID
                    let savedEvent = self.makeEvent(from: ekEvent)
                    continuation.resume(returning: savedEvent)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 更新现有事件
    func updateEvent(_ event: Event) async throws -> Event {
        guard permissionStatus == .authorized else {
            throw NSError(domain: "DeviceCalendarService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Calendar permission not granted"])
        }

        guard let eventId = event.deviceEventId ?? event.id as String?,
              let ekEvent = eventStore.event(withIdentifier: eventId) else {
            // 如果找不到事件，创建新的
            return try await createEvent(event)
        }

        return try await withCheckedThrowingContinuation { continuation in
            calendarQueue.async {
                ekEvent.title = event.title
                ekEvent.startDate = event.startDate
                ekEvent.endDate = event.endDate
                ekEvent.location = event.location.isEmpty ? nil : event.location
                ekEvent.isAllDay = event.isAllDay
                ekEvent.notes = event.description
                ekEvent.url = event.url.flatMap(URL.init(string:))
                ekEvent.alarms = event.reminders.map { EKAlarm(absoluteDate: $0) }

                do {
                    try self.eventStore.save(ekEvent, span: .thisEvent, commit: true)
                    let savedEvent = self.makeEvent(from: ekEvent)
                    continuation.resume(returning: savedEvent)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 删除事件
    func deleteEvent(eventId: String) async throws {
        guard permissionStatus == .authorized else {
            throw NSError(domain: "DeviceCalendarService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Calendar permission not granted"])
        }

        guard let ekEvent = eventStore.event(withIdentifier: eventId) else {
            return  // 事件不存在，视为成功
        }

        try await withCheckedThrowingContinuation { continuation in
            calendarQueue.async {
                do {
                    try self.eventStore.remove(ekEvent, span: .thisEvent, commit: true)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @MainActor
    func refreshCalendars() async {
        guard permissionStatus == .authorized else {
            availableCalendars = []
            return
        }
        // 获取所有日历，包括只读的订阅日历（如节假日日历）
        availableCalendars = eventStore.calendars(for: .event)
    }

    /// 获取可编辑的日历（用于创建新事件）
    var editableCalendars: [EKCalendar] {
        availableCalendars.filter { $0.allowsContentModifications }
    }

    /// 获取订阅的日历（只读，如节假日日历）
    var subscribedCalendars: [EKCalendar] {
        availableCalendars.filter { !$0.allowsContentModifications }
    }

    /// 检查是否有节假日日历
    var hasHolidayCalendar: Bool {
        subscribedCalendars.contains { calendar in
            let title = calendar.title.lowercased()
            return title.contains("节假日") || title.contains("holiday") ||
                   title.contains("假期") || title.contains("holidays")
        }
    }

    /// 获取或创建应用专属日历
    func getOrCreateAppCalendar() async throws -> EKCalendar {
        // 先尝试从 UserDefaults 获取已保存的日历标识符
        if let savedIdentifier = UserDefaults.standard.string(forKey: appCalendarIdentifierKey),
           let existingCalendar = eventStore.calendar(withIdentifier: savedIdentifier),
           existingCalendar.allowsContentModifications {
            return existingCalendar
        }

        // 查找现有的应用日历
        if let existingCalendar = editableCalendars.first(where: { $0.title == appCalendarTitle }) {
            // 保存标识符
            UserDefaults.standard.set(existingCalendar.calendarIdentifier, forKey: appCalendarIdentifierKey)
            return existingCalendar
        }

        // 创建新的应用日历
        let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
        newCalendar.title = appCalendarTitle
        newCalendar.cgColor = UIColor.systemBlue.cgColor

        // 设置日历源（优先使用 iCloud，其次本地）
        if let iCloudSource = eventStore.sources.first(where: { $0.sourceType == .calDAV || $0.title.lowercased().contains("icloud") }) {
            newCalendar.source = iCloudSource
        } else if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            newCalendar.source = localSource
        } else {
            newCalendar.source = eventStore.defaultCalendarForNewEvents?.source ?? eventStore.sources.first!
        }

        // 保存日历
        try eventStore.saveCalendar(newCalendar, commit: true)

        // 保存标识符到 UserDefaults
        UserDefaults.standard.set(newCalendar.calendarIdentifier, forKey: appCalendarIdentifierKey)

        return newCalendar
    }

    /// 调试：打印所有日历信息
    func printAllCalendars() {
        print("📅 所有日历信息:")
        print("==================")

        for calendar in availableCalendars {
            print("📚 日历: \(calendar.title)")
            print("   - ID: \(calendar.calendarIdentifier)")
            print("   - 类型: \(calendar.type.rawValue)")
            print("   - 来源: \(calendar.source.title)")
            print("   - 可编辑: \(calendar.allowsContentModifications)")
            print("   - 订阅: \(calendar.isSubscribed)")
            print("   - 颜色: \(calendar.cgColor != nil ? "有" : "无")")
            print("")
        }

        print("📝 可编辑日历数: \(editableCalendars.count)")
        print("🔒 只读日历数: \(subscribedCalendars.count)")
        print("🎉 包含节假日日历: \(hasHolidayCalendar)")
        print("==================")
    }

    // MARK: - Helpers

    private func makeEvent(from ekEvent: EKEvent) -> Event {
        let reminders = ekEvent.alarms?
            .compactMap { $0.absoluteDate }
            .sorted() ?? []

        let color: UIColor?
        if let cgColor = ekEvent.calendar.cgColor {
            color = UIColor(cgColor: cgColor)
        } else {
            color = nil
        }

        return Event(
            id: ekEvent.eventIdentifier,
            title: ekEvent.title ?? "",
            startDate: ekEvent.startDate,
            endDate: ekEvent.endDate,
            isAllDay: ekEvent.isAllDay,
            location: ekEvent.location ?? "",
            calendarId: ekEvent.calendar.calendarIdentifier,
            description: ekEvent.notes,
            customColor: color,
            recurrenceRule: nil,
            reminders: reminders,
            url: ekEvent.url?.absoluteString,
            calendarName: ekEvent.calendar.title,
            isFromDeviceCalendar: true,
            deviceEventId: ekEvent.eventIdentifier
        )
    }
}
