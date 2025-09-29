import Foundation

enum RepeatFrequency: String, Codable, CaseIterable {
    case none
    case daily
    case weekly
    case monthly
    case yearly
}

struct RepeatRule: Codable, Equatable {
    var frequency: RepeatFrequency
    var interval: Int
    var endType: EndType
    var count: Int?
    var endDate: Date?
    var weekdays: [Int]?
    var monthDays: [Int]?
    var monthMode: MonthMode?
    var weekOrdinal: Int?
    var weekday: Int?
    var months: [Int]?
    var yearMode: YearMode?

    enum EndType: String, Codable {
        case never
        case count
        case until
    }

    enum MonthMode: String, Codable {
        case byDate
        case byWeekday
    }

    enum YearMode: String, Codable {
        case byDate
        case byWeekday
    }

    init(
        frequency: RepeatFrequency,
        interval: Int = 1,
        endType: EndType = .never,
        count: Int? = nil,
        endDate: Date? = nil,
        weekdays: [Int]? = nil,
        monthDays: [Int]? = nil,
        monthMode: MonthMode? = nil,
        weekOrdinal: Int? = nil,
        weekday: Int? = nil,
        months: [Int]? = nil,
        yearMode: YearMode? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.endType = endType
        self.count = count
        self.endDate = endDate
        self.weekdays = weekdays
        self.monthDays = monthDays
        self.monthMode = monthMode
        self.weekOrdinal = weekOrdinal
        self.weekday = weekday
        self.months = months
        self.yearMode = yearMode
    }

    static func none() -> RepeatRule {
        RepeatRule(frequency: .none)
    }

    var isNone: Bool { frequency == .none }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "frequency": frequency.rawValue,
            "interval": interval,
            "endType": endType.rawValue
        ]
        if let count { dict["count"] = count }
        if let endDate { dict["endDate"] = ISO8601DateFormatter().string(from: endDate) }
        if let weekdays { dict["weekdays"] = weekdays }
        if let monthDays { dict["monthDays"] = monthDays }
        if let monthMode { dict["monthMode"] = monthMode.rawValue }
        if let weekOrdinal { dict["weekOrdinal"] = weekOrdinal }
        if let weekday { dict["weekday"] = weekday }
        if let months { dict["months"] = months }
        if let yearMode { dict["yearMode"] = yearMode.rawValue }
        return dict
    }

    func humanReadableDescription() -> String {
        var base = "日程将"
        if interval > 1 {
            base += "每\\(interval)"
        } else {
            base += "每"
        }

        switch frequency {
        case .none:
            return "不重复"
        case .daily:
            base += "天"
        case .weekly:
            base += "周"
            if let weekdays, !weekdays.isEmpty {
                let names = ["日", "一", "二", "三", "四", "五", "六"]
                let selected = weekdays.map { index -> String in
                    let clamped = max(0, min(index, names.count - 1))
                    return "周" + names[clamped]
                }.joined(separator: "、")
                base += "的\\(selected)"
            }
        case .monthly:
            base += "月"
            if monthMode == .byDate, let monthDays, !monthDays.isEmpty {
                let values = monthDays.map { "\($0)号" }.joined(separator: "、")
                base += "的\(values)"
            } else if monthMode == .byWeekday, let weekOrdinal, let weekday {
                let ordinals = [0: "", 1: "第一个", 2: "第二个", 3: "第三个", 4: "第四个", 5: "最后一个"]
                let weekdays = [1: "星期日", 2: "星期一", 3: "星期二", 4: "星期三", 5: "星期四", 6: "星期五", 7: "星期六"]
                base += "的\(ordinals[weekOrdinal] ?? "")\(weekdays[weekday] ?? "")"
            }
        case .yearly:
            base += "年"
            if let months, !months.isEmpty {
                let values = months.map { "\($0)月" }.joined(separator: "、")
                base += "的\(values)"
            }
        }

        switch endType {
        case .never:
            base += "重复。"
        case .count:
            if let count {
                base += "重复\\(count)次。"
            } else {
                base += "重复若干次。"
            }
        case .until:
            if let endDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                base += "直至\\(formatter.string(from: endDate))。"
            } else {
                base += "直到指定日期。"
            }
        }

        return base
    }
}
