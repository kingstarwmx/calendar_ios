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
                let predicate = self.eventStore.predicateForEvents(
                    withStart: range.start,
                    end: range.end,
                    calendars: calendars ?? self.availableCalendars
                )
                let ekEvents = self.eventStore.events(matching: predicate)
                let events = ekEvents.map { self.makeEvent(from: $0) }
                continuation.resume(returning: events)
            }
        }
    }

    func syncToDeviceCalendar(_ event: Event, targetCalendar: EKCalendar? = nil) async throws -> String {
        guard permissionStatus == .authorized else {
            throw NSError(domain: "DeviceCalendarService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Calendar permission not granted"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            calendarQueue.async {
                let ekEvent: EKEvent
                if let identifier = event.deviceEventId,
                   let existingEvent = self.eventStore.event(withIdentifier: identifier) {
                    ekEvent = existingEvent
                } else {
                    ekEvent = EKEvent(eventStore: self.eventStore)
                }

                ekEvent.calendar = targetCalendar ?? self.eventStore.defaultCalendarForNewEvents ?? self.availableCalendars.first
                ekEvent.title = event.title
                ekEvent.startDate = event.startDate
                ekEvent.endDate = event.endDate
                ekEvent.location = event.location.isEmpty ? nil : event.location
                ekEvent.isAllDay = event.isAllDay
                ekEvent.notes = event.description
                ekEvent.url = event.url.flatMap(URL.init(string:))
                ekEvent.alarms = event.reminders.map { EKAlarm(absoluteDate: $0) }

                do {
                    try self.eventStore.save(ekEvent, span: .futureEvents, commit: true)
                    continuation.resume(returning: ekEvent.eventIdentifier)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func removeFromDeviceCalendar(eventId: String) async throws {
        guard permissionStatus == .authorized else { return }
        try await withCheckedThrowingContinuation { continuation in
            calendarQueue.async {
                guard let event = self.eventStore.event(withIdentifier: eventId) else {
                    continuation.resume(returning: ())
                    return
                }

                do {
                    try self.eventStore.remove(event, span: .futureEvents, commit: true)
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
        availableCalendars = eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
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
