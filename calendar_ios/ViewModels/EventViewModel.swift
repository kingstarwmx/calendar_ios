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

    func loadEvents(forceRefresh: Bool = false, dateRange: DateInterval? = nil, completion: (() -> Void)? = nil) {
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
                // 使用传入的 dateRange，如果没有则使用 currentMonth
                let defaultRange: DateInterval
                if let dateRange = dateRange {
                    defaultRange = dateRange
                } else {
                    let month = await self.currentMonth
                    defaultRange = DateInterval(start: month.startOfMonth, end: month.endOfMonth)
                }

                if forceRefresh {
                    _ = await self.calendarService.refresh(range: defaultRange)
                }
                loadedEvents = await self.calendarService.loadAllEvents(range: defaultRange)

                deviceEnabled = await self.calendarService.devicePermissionStatus() == .authorized
                calendars = await self.calendarService.availableDeviceCalendars()

                semaphore.signal()
            }

            semaphore.wait()

            DispatchQueue.main.async {
                self.events = loadedEvents
                self.deviceCalendarEnabled = deviceEnabled
                self.availableCalendars = calendars

                // 打印加载的事件数据
                print("📅 加载事件数量: \(self.events.count)")
                for event in self.events {
//                    print("  - 事件: \(event.title), 日期: \(event.startDate), 全天: \(event.isAllDay), 日历: \(event.calendarName ?? "")")
                }

                print("📱 设备日历权限: \(self.deviceCalendarEnabled)")
                print("📚 可用日历数量: \(self.availableCalendars.count)")

                self.isLoading = false
                completion?()
            }
        }
    }

    func requestDeviceCalendarAccessWithRange(dateRange: DateInterval? = nil, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            var calendars: [EKCalendarSummary] = []

            Task {
                granted = await self.calendarService.requestDevicePermission()

                if granted {
                    await self.calendarService.refreshCalendars()
                    calendars = await self.calendarService.availableDeviceCalendars()

                    // 调试：打印所有日历信息
//                    await self.calendarService.printAllCalendars()
                }

                semaphore.signal()
            }

            semaphore.wait()

            DispatchQueue.main.async {
                self.deviceCalendarEnabled = granted
                self.availableCalendars = calendars

                if granted {
                    // 使用传入的 dateRange 加载事件
                    self.loadEvents(forceRefresh: true, dateRange: dateRange, completion: completion)
                } else {
                    completion?()
                }
            }
        }
    }

    // 保留原方法以兼容其他调用
    func requestDeviceCalendarAccess(completion: (() -> Void)? = nil) {
        requestDeviceCalendarAccessWithRange(dateRange: nil, completion: completion)
    }

    func refreshEvents() async {
        loadEvents(forceRefresh: true)
    }

    func addEvent(_ event: Event) async {
        print("➕ 准备添加事件: \(event.title)")
        print("   日期: \(event.startDate)")

        do {
            let savedEvent = try await calendarService.createEvent(event)
            print("✅ 事件添加成功")

            // 刷新所有数据，特别是对于重复事件需要加载所有实例
            loadEvents(forceRefresh: true)
        } catch {
            print("❌ 添加事件失败: \(error)")
            assertionFailure("Failed to add event: \(error)")
        }
    }

    func updateEvent(_ event: Event) async {
        do {
            let updatedEvent = try await calendarService.updateEvent(event)
            print("✅ 事件更新成功")

            // 刷新所有数据，特别是对于重复事件需要重新加载所有实例
            loadEvents(forceRefresh: true)
        } catch {
            print("❌ 更新事件失败: \(error)")
            assertionFailure("Failed to update event: \(error)")
        }
    }

    func deleteEvent(id: String) async {
        do {
            try await calendarService.deleteEvent(id: id)
            print("✅ 事件删除成功")

            // 刷新所有数据，特别是对于重复事件需要重新加载
            loadEvents(forceRefresh: true)
        } catch {
            print("❌ 删除事件失败: \(error)")
            assertionFailure("Failed to delete event: \(error)")
        }
    }

    func getEvents(for date: Date) -> [Event] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date

        // 获取所有事件（包括来自设备日历的节假日）
        let allEvents = events.filter { event in
            let interval = event.allDayDisplayRange
            return interval.start < dayEnd && interval.end > dayStart
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
