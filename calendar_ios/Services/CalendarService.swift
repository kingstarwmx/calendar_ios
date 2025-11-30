import Foundation
import EventKit
import UIKit

actor CalendarService {
    private let deviceService: DeviceCalendarService

    private var cachedEvents: [Event] = []
    private var cachedRange: DateInterval?

    init(deviceService: DeviceCalendarService = DeviceCalendarService()) {
        self.deviceService = deviceService
    }

    func requestDevicePermission() async -> Bool {
        let granted = await deviceService.requestCalendarPermission()
        if granted {
            await refreshCalendars()
        }
        return granted
    }

    func refreshCalendars() async {
        await deviceService.refreshCalendars()
    }

    func availableDeviceCalendars() -> [EKCalendarSummary] {
        deviceService.editableCalendars.map { EKCalendarSummary(calendar: $0) }
    }

    func devicePermissionStatus() -> DeviceCalendarService.PermissionStatus {
        deviceService.permissionStatus
    }

    /// 加载所有事件（从 EventKit）
    func loadAllEvents(range: DateInterval? = nil) async -> [Event] {
        let effectiveRange = range ?? defaultRange(for: Date())

        // 直接从设备日历获取所有事件
        if let events = try? await deviceService.fetchDeviceEvents(in: effectiveRange) {
            cachedEvents = events
            cachedRange = effectiveRange
            return events
        }

        return []
    }

    /// 获取指定日期的事件
    func events(on date: Date) async -> [Event] {
        let range = DateInterval(start: date.startOfDay, end: date.endOfDay)

        if let events = try? await deviceService.fetchDeviceEvents(in: range) {
            return events.sorted(by: chronologicalSort)
        }

        return []
    }

    /// 刷新事件
    func refresh(range: DateInterval? = nil) async -> [Event] {
        await loadAllEvents(range: range)
    }

    func currentCachedEvents() -> [Event] {
        cachedEvents
    }

    /// 创建新事件（直接保存到 EventKit）
    func createEvent(_ event: Event) async throws -> Event {
        return try await deviceService.createEvent(event)
    }

    /// 更新事件（直接更新到 EventKit）
    func updateEvent(_ event: Event) async throws -> Event {
        return try await deviceService.updateEvent(event)
    }

    /// 删除事件（直接从 EventKit 删除）
    func deleteEvent(id: String) async throws {
        try await deviceService.deleteEvent(eventId: id)
    }

    func createCalendar(title: String, color: UIColor? = nil) async throws -> EKCalendarSummary {
        let calendar = try await deviceService.createCalendar(title: title, color: color)
        return EKCalendarSummary(calendar: calendar)
    }

    /// 打印所有日历信息（调试用）
    func printAllCalendars() async {
        await deviceService.printAllCalendars()
    }

    // MARK: - Helpers

    private func chronologicalSort(_ lhs: Event, _ rhs: Event) -> Bool {
        if lhs.startDate == rhs.startDate {
            return lhs.endDate < rhs.endDate
        }
        return lhs.startDate < rhs.startDate
    }

    private func defaultRange(for date: Date) -> DateInterval {
        let calendar = Calendar.current
        // 默认加载前后各两个月（共5个月）的数据
        let start = calendar.date(byAdding: .month, value: -2, to: date.startOfDay) ?? date.startOfDay
        let end = calendar.date(byAdding: .month, value: 2, to: date.endOfDay) ?? date.endOfDay
        return DateInterval(start: start.startOfMonth, end: end.endOfMonth)
    }
}

struct EKCalendarSummary: Identifiable {
    let id: String
    let title: String
    let color: UIColor?
    let allowsContentModifications: Bool

    init(calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        title = calendar.title
        allowsContentModifications = calendar.allowsContentModifications
        if let cgColor = calendar.cgColor {
            color = UIColor(cgColor: cgColor)
        } else {
            color = nil
        }
    }
}

private extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        let start = startOfDay
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? self
    }

    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }

    var endOfMonth: Date {
        let calendar = Calendar.current
        if let range = calendar.range(of: .day, in: .month, for: self),
           let start = calendar.date(from: calendar.dateComponents([.year, .month], from: self)) {
            return calendar.date(byAdding: DateComponents(day: range.count, second: -1), to: start) ?? self
        }
        return self
    }
}
