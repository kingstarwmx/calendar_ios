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

            // 规则：
            // 1. 事件开始时间必须 < 第二天00:00
            // 2. 事件结束时间必须 > 当天00:00，或者是瞬时事件（开始=结束且在当天）
            //
            // 例子：
            // - 10月8日00:00 - 10月8日00:00（瞬时）：显示在10月8日 ✅
            // - 10月8日00:00 - 10月9日00:00：只显示在10月8日，不显示在10月9日 ✅
            // - 10月8日10:00 - 10月8日12:00：显示在10月8日 ✅

            let isInstantEvent = interval.start == interval.end
            let isEventInDay = interval.start >= dayStart && interval.start < dayEnd

            if isInstantEvent && isEventInDay {
                // 瞬时事件且在当天
                return true
            } else {
                // 普通事件：结束时间必须 > 当天00:00
                return interval.start < dayEnd && interval.end > dayStart
            }
        }


        // 先按时间排序
        var sortedEvents = filteredEvents.sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.endDate < rhs.endDate
            }
            return lhs.startDate < rhs.startDate
        }

        // 判断是否是一周的开始（注意：不一定是周日，系统可以自定义一周开始的是周几）
        let weekday = calendar.component(.weekday, from: dayStart)
        let firstWeekday = calendar.firstWeekday // 系统设置的一周开始日期（1=周日, 2=周一, ...）
        let isWeekStart = (weekday == firstWeekday)

        if isWeekStart {
            // 一周开始的天：连续事件重新排序到前面
            let multiDayEvents = sortedEvents.filter { isMultiDayEvent($0) }
            let singleDayEvents = sortedEvents.filter { !isMultiDayEvent($0) }
            sortedEvents = multiDayEvents + singleDayEvents
        } else {
            // 非一周开始的天：连续事件需要保持前一天的位置
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: dayStart) else {
                return sortedEvents
            }

            // 获取前一天的事件
            let previousDayEvents = events(for: previousDay)

            // 找出当天的连续事件和单天事件
            let currentMultiDayEvents = sortedEvents.filter { isMultiDayEvent($0) }
            let currentSingleDayEvents = sortedEvents.filter { !isMultiDayEvent($0) }

            // 为每个连续事件找到在前一天的位置
            var positionMap: [String: Int] = [:]  // eventId -> previousDayIndex
            for (index, event) in previousDayEvents.enumerated() {
                positionMap[event.id] = index
            }

            // 计算当天需要的最大index（由前一天连续事件位置决定）
            var maxRequiredIndex = -1
            for event in currentMultiDayEvents {
                if let prevIndex = positionMap[event.id] {
                    maxRequiredIndex = max(maxRequiredIndex, prevIndex)
                }
            }

            // 创建足够大的结果数组（初始填充nil）
            let arraySize = max(maxRequiredIndex + 1, currentMultiDayEvents.count + currentSingleDayEvents.count)
            var resultArray: [Event?] = Array(repeating: nil, count: arraySize)

            // 放置连续事件到对应位置
            for event in currentMultiDayEvents {
                if let prevIndex = positionMap[event.id] {
                    // 如果前一天有这个连续事件，保持相同位置
                    resultArray[prevIndex] = event
                } else {
                    // 如果前一天没有，找第一个空位置（连续事件优先放在前面）
                    if let firstNilIndex = resultArray.firstIndex(where: { $0 == nil }) {
                        resultArray[firstNilIndex] = event
                    } else {
                        resultArray.append(event)
                    }
                }
            }

            // 放置单天事件到剩余位置
            for event in currentSingleDayEvents {
                if let firstNilIndex = resultArray.firstIndex(where: { $0 == nil }) {
                    resultArray[firstNilIndex] = event
                } else {
                    resultArray.append(event)
                }
            }

            // 填充空白事件（isBlank = true）
            for i in 0..<resultArray.count {
                if resultArray[i] == nil {
                    // 创建空白事件
                    let blankEvent = Event(
                        id: "blank_\(date.timeIntervalSince1970)_\(i)",
                        title: "",
                        startDate: dayStart,
                        endDate: dayStart,
                        isAllDay: false,
                        location: "",
                        calendarId: "",
                        isBlank: true
                    )
                    resultArray[i] = blankEvent
                }
            }

            // 转换为非可选数组
            sortedEvents = resultArray.compactMap { $0 }
        }

        return sortedEvents
    }

    /// 判断是否为单天事件（开始时间>=当天00:00，结束时间<=第二天00:00）
    private func isSingleDayEvent(_ event: Event) -> Bool {
        let startOfDay = calendar.startOfDay(for: event.startDate)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? event.startDate

        return event.startDate >= startOfDay && event.endDate <= nextDayStart
    }

    /// 判断是否为连续事件（多天事件）
    private func isMultiDayEvent(_ event: Event) -> Bool {
        return !isSingleDayEvent(event)
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
        self.selectedDate = newDate
        // 手动触发一次事件更新，以便调试
        let eventsForDate = events(for: newDate)
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

    // MARK: - Debug Methods

    /// 导出指定月份的事件数据到JSON文件（用于调试）
    /// - Returns: JSON文件的路径，如果导出失败返回nil
    func exportEventsToJSON() -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var result: [String: [[String: Any]]] = [:]

        // 计算实际显示范围（包括前后月份的占位日期）
        let range = actualDisplayRange

        var currentDate = range.lowerBound
        while currentDate <= range.upperBound {
            let dateString = formatter.string(from: currentDate)
            let eventsForDate = events(for: currentDate)

            var eventsArray: [[String: Any]] = []
            for (index, event) in eventsForDate.enumerated() {
                eventsArray.append([
                    "index": index,
                    "id": event.id,
                    "title": event.title,
                    "isBlank": event.isBlank,
                    "isMultiDay": isMultiDayEvent(event),
                    "startDate": formatter.string(from: event.startDate),
                    "endDate": formatter.string(from: event.endDate),
                    "isAllDay": event.isAllDay
                ])
            }

            result[dateString] = eventsArray

            // 移动到下一天
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }

        // 转换为JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)

            // 保存到Documents目录
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent("calendar_events_debug_\(monthTitle).json")

            try jsonData.write(to: fileURL)

            // 同时打印到Console
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("📄 ==================== 事件数据导出 ====================")
                print("📄 文件路径: \(fileURL.path)")
                print("📄 JSON内容:")
                print(jsonString)
                print("📄 ======================================================")
            }

            return fileURL.path
        } catch {
            print("❌ 导出JSON失败: \(error)")
            return nil
        }
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
