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

    func loadEvents(forceRefresh: Bool = false, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            self.isLoading = true
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let semaphore = DispatchSemaphore(value: 0)
            var loadedEvents: [Event] = []
            var deviceEnabled = false
            var calendars: [EKCalendarSummary] = []

            Task {
                let range = DateInterval(start: await self.currentMonth.startOfMonth, end: await self.currentMonth.endOfMonth)
                if forceRefresh {
                    _ = await self.calendarService.refresh(range: range)
                }
                loadedEvents = await self.calendarService.loadAllEvents(range: range)

                deviceEnabled = await self.calendarService.devicePermissionStatus() == .authorized
                calendars = await self.calendarService.availableDeviceCalendars()

                semaphore.signal()
            }

            semaphore.wait()

            DispatchQueue.main.async {
                // 如果没有事件，添加一些测试数据
                if loadedEvents.isEmpty {
                    print("⚠️ 没有找到事件，创建测试数据...")
                    self.createTestEvents { [weak self] in
                        self?.loadEvents(forceRefresh: false, completion: completion)
                    }
                    return
                }

                self.events = loadedEvents
                self.deviceCalendarEnabled = deviceEnabled
                self.availableCalendars = calendars

                // 打印加载的事件数据
                print("📅 加载事件数量: \(self.events.count)")
                for event in self.events {
                    print("  - 事件: \(event.title), 日期: \(event.startDate), 全天: \(event.isAllDay)")
                }

                print("📱 设备日历权限: \(self.deviceCalendarEnabled)")
                print("📚 可用日历数量: \(self.availableCalendars.count)")

                self.isLoading = false
                completion?()
            }
        }
    }

    /// 创建测试事件数据
    private func createTestEvents(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let calendar = Calendar.current
            let today = Date()
            let defaultCalendarId = "default-calendar"

            // 创建几个测试事件
            let testEvents = [
                Event(
                    id: UUID().uuidString,
                    title: "团队会议",
                    startDate: calendar.date(byAdding: .hour, value: 10, to: today)!,
                    endDate: calendar.date(byAdding: .hour, value: 11, to: today)!,
                    isAllDay: false,
                    location: "会议室A",
                    calendarId: defaultCalendarId,
                    description: "讨论项目进度",
                    customColor: UIColor.systemBlue
                ),
                Event(
                    id: UUID().uuidString,
                    title: "午餐约会",
                    startDate: calendar.date(byAdding: .hour, value: 12, to: today)!,
                    endDate: calendar.date(byAdding: .hour, value: 13, to: today)!,
                    isAllDay: false,
                    location: "餐厅",
                    calendarId: defaultCalendarId,
                    description: nil,
                    customColor: UIColor.systemGreen
                ),
                Event(
                    id: UUID().uuidString,
                    title: "生日聚会",
                    startDate: calendar.date(byAdding: .day, value: 2, to: today)!,
                    endDate: calendar.date(byAdding: .day, value: 2, to: today)!,
                    isAllDay: true,
                    location: "家",
                    calendarId: defaultCalendarId,
                    description: "记得买礼物",
                    customColor: UIColor.systemPink
                ),
                Event(
                    id: UUID().uuidString,
                    title: "项目截止日",
                    startDate: calendar.date(byAdding: .day, value: 5, to: today)!,
                    endDate: calendar.date(byAdding: .day, value: 5, to: today)!,
                    isAllDay: true,
                    location: "",
                    calendarId: defaultCalendarId,
                    description: "重要！",
                    customColor: UIColor.systemRed
                )
            ]

            let semaphore = DispatchSemaphore(value: 0)
            var remaining = testEvents.count

            for event in testEvents {
                Task {
                    await self.addEvent(event, syncToDevice: false)
                    remaining -= 1
                    if remaining == 0 {
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()

            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    func requestDeviceCalendarAccess(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            var calendars: [EKCalendarSummary] = []

            Task {
                granted = await self.calendarService.requestDevicePermission()
                await self.calendarService.configureDeviceSync(enabled: granted)

                if granted {
                    await self.calendarService.refreshCalendars()
                    calendars = await self.calendarService.availableDeviceCalendars()
                }

                semaphore.signal()
            }

            semaphore.wait()

            DispatchQueue.main.async {
                self.deviceCalendarEnabled = granted
                self.availableCalendars = calendars

                if granted {
                    self.loadEvents(forceRefresh: true, completion: completion)
                } else {
                    completion?()
                }
            }
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
        print("➕ 准备添加事件: \(event.title)")
        print("   日期: \(event.startDate)")
        print("   同步到设备: \(syncToDevice)")

        do {
            try await calendarService.saveLocalEvent(event)
            var finalEvent = event
            if syncToDevice {
                finalEvent = try await calendarService.syncToDeviceCalendar(event)
            }
            events.append(finalEvent)
            events.sort(by: chronologicalSort)
            print("✅ 事件添加成功")
        } catch {
            print("❌ 添加事件失败: \(error)")
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

        // 获取普通事件
        var allEvents = events.filter { event in
            let interval = event.allDayDisplayRange
            return interval.start < dayEnd && interval.end > dayStart
        }

        // 添加节假日事件
        if let holidayName = HolidayService.shared.getHoliday(for: date) {
            let holidayEvent = Event(
                id: "holiday-\(date.timeIntervalSince1970)",
                title: holidayName,
                startDate: dayStart,
                endDate: dayEnd,
                isAllDay: true,
                location: "",
                calendarId: "holiday-calendar",
                description: "法定节假日",
                customColor: .systemRed
            )
            allEvents.append(holidayEvent)
        }

        return allEvents.sorted(by: chronologicalSort)
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
