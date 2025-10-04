import Foundation
import Combine
import UIKit

/// 单个月份页面的 ViewModel
@MainActor
final class MonthPageViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 当前月份
    @Published var currentMonth: Date

    /// 当前月份的所有事件
    @Published var monthEvents: [Event] = []

    /// 当前选中的日期
    @Published var selectedDate: Date

    /// 选中日期的事件列表
    @Published var selectedDateEvents: [Event] = []

    /// 日历显示范围（用于展示前后月的占位日期）
    @Published var displayDateRange: ClosedRange<Date>?

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private let calendar = Calendar.current

    // MARK: - Computed Properties

    /// 获取指定日期的事件
    func events(for date: Date) -> [Event] {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date

        let filteredEvents = monthEvents.filter { event in
            let interval = event.allDayDisplayRange
            return interval.start < dayEnd && interval.end > dayStart
        }

        // 调试日志
        if !filteredEvents.isEmpty {
            print("🔎 [\(monthTitle)] Found \(filteredEvents.count) events for \(date.formatted())")
            for event in filteredEvents {
                print("    - \(event.title): \(event.startDate.formatted()) - \(event.endDate.formatted())")
            }
        }

        return filteredEvents.sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.endDate < rhs.endDate
            }
            return lhs.startDate < rhs.startDate
        }
    }

    /// 当月的第一天
    var firstDayOfMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
    }

    /// 当月的最后一天
    var lastDayOfMonth: Date {
        if let range = calendar.range(of: .day, in: .month, for: currentMonth),
           let lastDay = calendar.date(byAdding: .day, value: range.count - 1, to: firstDayOfMonth) {
            return lastDay
        }
        return currentMonth
    }

    /// 计算月视图实际显示的日期范围（包括占位日期）
    var actualDisplayRange: ClosedRange<Date> {
        let weekday = calendar.component(.weekday, from: firstDayOfMonth)
        let daysToSubtract = weekday - 1  // 周日是1
        let displayStartDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDayOfMonth) ?? firstDayOfMonth
        let displayEndDate = calendar.date(byAdding: .day, value: 41, to: displayStartDate) ?? lastDayOfMonth
        return displayStartDate...displayEndDate
    }

    // MARK: - Initialization

    init(month: Date, selectedDate: Date? = nil) {
        self.currentMonth = month
        self.selectedDate = selectedDate ?? calendar.startOfDay(for: Date())

        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // 当选中日期改变时，更新选中日期的事件
        $selectedDate
            .combineLatest($monthEvents)
            .receive(on: DispatchQueue.main)  // 确保在主线程
            .map { [weak self] date, _ in
                guard let self = self else { return [] }
                let result = self.events(for: date)
                print("📊 [\(self.monthTitle)] Combine: selectedDate=\(date.formatted()), monthEvents.count=\(self.monthEvents.count), result=\(result.count)")
                return result
            }
            .assign(to: &$selectedDateEvents)

        // 当月份改变时，更新显示范围
        $currentMonth
            .map { [weak self] _ in
                self?.actualDisplayRange
            }
            .compactMap { $0 }
            .map { range in
                range
            }
            .assign(to: &$displayDateRange)
    }

    // MARK: - Public Methods

    /// 更新月份数据
    func configure(month: Date, events: [Event]) {
        // 检查月份是否真的改变了
        let monthChanged = !calendar.isDate(self.currentMonth, equalTo: month, toGranularity: .month)

        // 只保留实际显示范围内的事件
        let range: ClosedRange<Date>
        if monthChanged {
            // 月份改变了，计算新的范围
            let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
            let weekday = calendar.component(.weekday, from: firstDay)
            let daysToSubtract = weekday - 1
            let displayStartDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDay) ?? firstDay
            let displayEndDate = calendar.date(byAdding: .day, value: 41, to: displayStartDate) ?? firstDay
            range = displayStartDate...displayEndDate
        } else {
            // 使用当前范围
            range = actualDisplayRange
        }

        let filteredEvents = events.filter { event in
            let eventStart = calendar.startOfDay(for: event.startDate)
            let eventEnd = calendar.startOfDay(for: event.endDate)
            return eventEnd >= range.lowerBound && eventStart <= range.upperBound
        }

        // 检查事件是否真的改变了（比较 ID 集合）
        let currentEventIds = Set(self.monthEvents.map { $0.id })
        let newEventIds = Set(filteredEvents.map { $0.id })
        let eventsChanged = currentEventIds != newEventIds

        // 只在真正有变化时更新
        if monthChanged {
            self.currentMonth = month
            self.monthEvents = filteredEvents
        } else if eventsChanged {
            self.monthEvents = filteredEvents
        }
    }

    /// 选择日期
    func selectDate(_ date: Date) {
        let newDate = calendar.startOfDay(for: date)
        print("🔍 [\(monthTitle)] selectDate called: \(newDate.formatted()), current events count: \(monthEvents.count)")
        self.selectedDate = newDate
        // 手动触发一次事件更新，以便调试
        let eventsForDate = events(for: newDate)
        print("🔍 [\(monthTitle)] Events for \(newDate.formatted()): \(eventsForDate.count) events")
    }

    /// 检查日期是否在当前月
    func isDateInCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
    }

    /// 检查是否是今天
    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    /// 检查是否是选中日期
    func isSelectedDate(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    /// 获取日期的显示文本
    func dayText(for date: Date) -> String {
        let day = calendar.component(.day, from: date)
        return "\(day)"
    }

    /// 获取月份标题
    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: currentMonth)
    }
}

// MARK: - Event Helpers

extension MonthPageViewModel {

    /// 获取某一天的事件数量
    func eventCount(for date: Date) -> Int {
        events(for: date).count
    }

    /// 检查某一天是否有事件
    func hasEvents(on date: Date) -> Bool {
        !events(for: date).isEmpty
    }

    /// 获取某一天的主要事件颜色（用于日历标记）
    func primaryEventColor(for date: Date) -> UIColor? {
        events(for: date).first?.customColor
    }
}