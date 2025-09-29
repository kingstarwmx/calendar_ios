import Foundation
import EventKit
import UIKit

@MainActor
final class EventViewModel: ObservableObject {
    @Published private(set) var events: [Event] = []
    @Published var selectedDate: Date = Date()
    @Published var currentMonth: Date = Date()
    @Published var viewMode: CalendarViewMode = .normal
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var deviceCalendarEnabled: Bool = false
    @Published private(set) var availableCalendars: [EKCalendarSummary] = []

    private let calendarService: CalendarService

    init(calendarService: CalendarService = CalendarService()) {
        self.calendarService = calendarService
    }

    func loadEvents(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        let range = DateInterval(start: currentMonth.startOfMonth, end: currentMonth.endOfMonth)
        if forceRefresh {
            _ = await calendarService.refresh(range: range)
        }
        events = await calendarService.loadAllEvents(range: range)
        deviceCalendarEnabled = await calendarService.devicePermissionStatus() == .authorized
        availableCalendars = await calendarService.availableDeviceCalendars()
    }

    func requestDeviceCalendarAccess() async {
        let granted = await calendarService.requestDevicePermission()
        deviceCalendarEnabled = granted
        await calendarService.configureDeviceSync(enabled: granted)
        if granted {
            await calendarService.refreshCalendars()
            availableCalendars = await calendarService.availableDeviceCalendars()
            await loadEvents(forceRefresh: true)
        }
    }

    func setDeviceSync(enabled: Bool) async {
        await calendarService.configureDeviceSync(enabled: enabled)
        deviceCalendarEnabled = enabled
        if enabled {
            await loadEvents(forceRefresh: true)
        }
    }

    func addEvent(_ event: Event, syncToDevice: Bool = false) async {
        do {
            try await calendarService.saveLocalEvent(event)
            var finalEvent = event
            if syncToDevice {
                finalEvent = try await calendarService.syncToDeviceCalendar(event)
            }
            events.append(finalEvent)
            events.sort(by: chronologicalSort)
        } catch {
            assertionFailure("Failed to add event: \(error)")
        }
    }

    func updateEvent(_ event: Event, syncToDevice: Bool = false) async {
        do {
            try await calendarService.updateLocalEvent(event)
            var updated = event
            if syncToDevice {
                updated = try await calendarService.syncToDeviceCalendar(event)
            }
            if let index = events.firstIndex(where: { $0.id == event.id }) {
                events[index] = updated
            }
        } catch {
            assertionFailure("Failed to update event: \(error)")
        }
    }

    func deleteEvent(id: String, removeFromDevice: Bool = false) async {
        do {
            if removeFromDevice, let event = events.first(where: { $0.id == id }) {
                await calendarService.removeFromDeviceCalendar(event: event)
            }
            try await calendarService.deleteLocalEvent(id: id)
            events.removeAll { $0.id == id }
        } catch {
            assertionFailure("Failed to delete event: \(error)")
        }
    }

    func getEvents(for date: Date) -> [Event] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
        return events.filter { event in
            let interval = event.allDayDisplayRange
            return interval.start < dayEnd && interval.end > dayStart
        }.sorted(by: chronologicalSort)
    }

    func goToToday() {
        selectedDate = Date()
        currentMonth = Date()
    }

    func setCurrentMonth(_ month: Date) {
        currentMonth = month
    }

    func setViewMode(_ mode: CalendarViewMode) {
        viewMode = mode
    }

    func toggleExpanded() {
        switch viewMode {
        case .collapsed:
            viewMode = .normal
        case .normal:
            viewMode = .expanded
        case .expanded:
            viewMode = .collapsed
        }
    }

    private func chronologicalSort(_ lhs: Event, _ rhs: Event) -> Bool {
        if lhs.startDate == rhs.startDate {
            return lhs.endDate < rhs.endDate
        }
        return lhs.startDate < rhs.startDate
    }
}

private extension Date {
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
