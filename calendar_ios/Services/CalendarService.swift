import Foundation
import EventKit
import UIKit

actor CalendarService {
    private let database: DatabaseHelper
    private let deviceService: DeviceCalendarService

    private var cachedEvents: [Event] = []
    private var cachedRange: DateInterval?
    private var includeDeviceEvents = false

    init(database: DatabaseHelper = .shared, deviceService: DeviceCalendarService = DeviceCalendarService()) {
        self.database = database
        self.deviceService = deviceService
    }

    func configureDeviceSync(enabled: Bool) {
        includeDeviceEvents = enabled
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
        deviceService.availableCalendars.map { EKCalendarSummary(calendar: $0) }
    }

    func devicePermissionStatus() -> DeviceCalendarService.PermissionStatus {
        deviceService.permissionStatus
    }

    func loadAllEvents(range: DateInterval? = nil) async -> [Event] {
        let events = await database.fetchAllEvents()
        var merged = events

        if includeDeviceEvents {
            let deviceRange = range ?? defaultRange(for: Date())
            if let deviceEvents = try? await deviceService.fetchDeviceEvents(in: deviceRange) {
                merged = merge(events: events, deviceEvents: deviceEvents)
            }
        }

        cachedEvents = merged
        cachedRange = range
        return merged
    }

    func events(on date: Date) async -> [Event] {
        let localEvents = await database.fetchEvents(for: date)
        var combined = localEvents

        if includeDeviceEvents {
            let range = DateInterval(start: date.startOfDay, end: date.endOfDay)
            if let deviceEvents = try? await deviceService.fetchDeviceEvents(in: range) {
                combined = merge(events: localEvents, deviceEvents: deviceEvents)
            }
        }

        return combined.sorted(by: chronologicalSort)
    }

    func refresh(range: DateInterval? = nil) async -> [Event] {
        await loadAllEvents(range: range)
    }

    func currentCachedEvents() -> [Event] {
        cachedEvents
    }

    func saveLocalEvent(_ event: Event) async throws {
        try await database.saveEvent(event)
    }

    func updateLocalEvent(_ event: Event) async throws {
        try await database.updateEvent(event)
    }

    func deleteLocalEvent(id: String) async throws {
        try await database.deleteEvent(id: id)
    }

    func syncToDeviceCalendar(_ event: Event) async throws -> Event {
        let identifier = try await deviceService.syncToDeviceCalendar(event)
        return event.copy(isFromDeviceCalendar: true, deviceEventId: identifier)
    }

    func removeFromDeviceCalendar(event: Event) async {
        guard let id = event.deviceEventId else { return }
        _ = try? await deviceService.removeFromDeviceCalendar(eventId: id)
    }

    // MARK: - Helpers

    private func merge(events: [Event], deviceEvents: [Event]) -> [Event] {
        var combined: [String: Event] = [:]
        for event in events { combined[event.id] = event }
        for deviceEvent in deviceEvents { combined[deviceEvent.id] = deviceEvent }
        return combined.values.sorted(by: chronologicalSort)
    }

    private func chronologicalSort(_ lhs: Event, _ rhs: Event) -> Bool {
        if lhs.startDate == rhs.startDate {
            return lhs.endDate < rhs.endDate
        }
        return lhs.startDate < rhs.startDate
    }

    private func defaultRange(for date: Date) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -30, to: date.startOfDay) ?? date.startOfDay
        let end = calendar.date(byAdding: .day, value: 90, to: date.endOfDay) ?? date.endOfDay
        return DateInterval(start: start, end: end)
    }
}

struct EKCalendarSummary: Identifiable {
    let id: String
    let title: String
    let color: UIColor?

    init(calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        title = calendar.title
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
}
