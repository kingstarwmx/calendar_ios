import Foundation
import UIKit

/// 对应 Flutter 端的 Event 数据模型
/// 使用引用类型以便在视图模型中基于标识符进行更新
final class Event: Identifiable, Hashable, Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startDate
        case endDate
        case isAllDay
        case location
        case calendarId
        case description
        case customColorHex
        case recurrenceRule
        case reminders
        case url
        case calendarName
        case isFromDeviceCalendar
        case deviceEventId
    }

    let id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var location: String
    var calendarId: String
    var description: String?
    var customColor: UIColor?
    var recurrenceRule: String?
    var reminders: [Date]
    var url: String?
    var calendarName: String?
    var isFromDeviceCalendar: Bool
    var deviceEventId: String?

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String = "",
        calendarId: String,
        description: String? = nil,
        customColor: UIColor? = nil,
        recurrenceRule: String? = nil,
        reminders: [Date] = [],
        url: String? = nil,
        calendarName: String? = nil,
        isFromDeviceCalendar: Bool = false,
        deviceEventId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.calendarId = calendarId
        self.description = description
        self.customColor = customColor
        self.recurrenceRule = recurrenceRule
        self.reminders = reminders.sorted()
        self.url = url
        self.calendarName = calendarName
        self.isFromDeviceCalendar = isFromDeviceCalendar
        self.deviceEventId = deviceEventId
    }

    /// 复制当前事件并覆盖部分字段
    func copy(
        id: String? = nil,
        title: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isAllDay: Bool? = nil,
        location: String? = nil,
        calendarId: String? = nil,
        description: String? = nil,
        customColor: UIColor? = nil,
        recurrenceRule: String? = nil,
        reminders: [Date]? = nil,
        url: String? = nil,
        calendarName: String? = nil,
        isFromDeviceCalendar: Bool? = nil,
        deviceEventId: String? = nil
    ) -> Event {
        Event(
            id: id ?? self.id,
            title: title ?? self.title,
            startDate: startDate ?? self.startDate,
            endDate: endDate ?? self.endDate,
            isAllDay: isAllDay ?? self.isAllDay,
            location: location ?? self.location,
            calendarId: calendarId ?? self.calendarId,
            description: description ?? self.description,
            customColor: customColor ?? self.customColor,
            recurrenceRule: recurrenceRule ?? self.recurrenceRule,
            reminders: reminders ?? self.reminders,
            url: url ?? self.url,
            calendarName: calendarName ?? self.calendarName,
            isFromDeviceCalendar: isFromDeviceCalendar ?? self.isFromDeviceCalendar,
            deviceEventId: deviceEventId ?? self.deviceEventId
        )
    }

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    var allDayDisplayRange: DateInterval {
        let calendar = Calendar.current
        if isAllDay {
            let start = calendar.startOfDay(for: startDate)
            // 对于全天事件，结束日期应该是endDate的第二天开始
            let end = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate)
            return DateInterval(start: start, end: end)
        }
        return DateInterval(start: startDate, end: endDate)
    }

    // MARK: - Codable

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let startDate = try container.decode(Date.self, forKey: .startDate)
        let endDate = try container.decode(Date.self, forKey: .endDate)
        let isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        let location = try container.decode(String.self, forKey: .location)
        let calendarId = try container.decode(String.self, forKey: .calendarId)
        let description = try container.decodeIfPresent(String.self, forKey: .description)
        let customColorHex = try container.decodeIfPresent(String.self, forKey: .customColorHex)
        let recurrenceRule = try container.decodeIfPresent(String.self, forKey: .recurrenceRule)
        let reminders = try container.decodeIfPresent([Date].self, forKey: .reminders) ?? []
        let url = try container.decodeIfPresent(String.self, forKey: .url)
        let calendarName = try container.decodeIfPresent(String.self, forKey: .calendarName)
        let isFromDeviceCalendar = try container.decodeIfPresent(Bool.self, forKey: .isFromDeviceCalendar) ?? false
        let deviceEventId = try container.decodeIfPresent(String.self, forKey: .deviceEventId)

        self.init(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: location,
            calendarId: calendarId,
            description: description,
            customColor: customColorHex.flatMap { UIColor(hexString: $0) },
            recurrenceRule: recurrenceRule,
            reminders: reminders,
            url: url,
            calendarName: calendarName,
            isFromDeviceCalendar: isFromDeviceCalendar,
            deviceEventId: deviceEventId
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(isAllDay, forKey: .isAllDay)
        try container.encode(location, forKey: .location)
        try container.encode(calendarId, forKey: .calendarId)
        try container.encode(description, forKey: .description)
        try container.encode(customColor?.toHexString(includeAlpha: true), forKey: .customColorHex)
        try container.encode(recurrenceRule, forKey: .recurrenceRule)
        try container.encode(reminders, forKey: .reminders)
        try container.encode(url, forKey: .url)
        try container.encode(calendarName, forKey: .calendarName)
        try container.encode(isFromDeviceCalendar, forKey: .isFromDeviceCalendar)
        try container.encode(deviceEventId, forKey: .deviceEventId)
    }

    // MARK: - Hashable

    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.id == rhs.id && lhs.startDate == rhs.startDate && lhs.endDate == rhs.endDate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
