import Foundation
import EventKit

extension RepeatRule {
    func toEKRecurrenceRule(startDate: Date) -> EKRecurrenceRule? {
        guard frequency != .none else { return nil }

        guard let ekFrequency = frequency.toEKRecurrenceFrequency() else { return nil }

        let end: EKRecurrenceEnd?
        switch endType {
        case .never:
            end = nil
        case .count:
            if let count, count > 0 {
                end = EKRecurrenceEnd(occurrenceCount: count)
            } else {
                end = nil
            }
        case .until:
            if let endDate {
                end = EKRecurrenceEnd(end: endDate)
            } else {
                end = nil
            }
        }

        var daysOfWeek: [EKRecurrenceDayOfWeek]?
        var daysOfMonth: [NSNumber]?
        var monthsOfYear: [NSNumber]?

        switch frequency {
        case .weekly:
            daysOfWeek = weekdays?.compactMap { RepeatRule.makeDayOfWeek($0) }
        case .monthly:
            if monthMode == .byDate, let monthDays, !monthDays.isEmpty {
                daysOfMonth = monthDays.map { NSNumber(value: $0) }
            } else if monthMode == .byWeekday,
                      let ordinal = weekOrdinal,
                      let weekday,
                      let weekNumber = RepeatRule.weekNumber(fromOrdinal: ordinal),
                      let day = RepeatRule.makeDayOfWeek(weekday, weekNumber: weekNumber) {
                daysOfWeek = [day]
            }
        case .yearly:
            if let months, !months.isEmpty {
                monthsOfYear = months.map { NSNumber(value: $0) }
            }
            if yearMode == .byWeekday,
               let ordinal = weekOrdinal,
               let weekday,
               let weekNumber = RepeatRule.weekNumber(fromOrdinal: ordinal),
               let day = RepeatRule.makeDayOfWeek(weekday, weekNumber: weekNumber) {
                daysOfWeek = [day]
            } else if let monthDays, !monthDays.isEmpty {
                daysOfMonth = monthDays.map { NSNumber(value: $0) }
            }
        default:
            break
        }

        return EKRecurrenceRule(
            recurrenceWith: ekFrequency,
            interval: max(1, interval),
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: daysOfMonth,
            monthsOfTheYear: monthsOfYear,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    func toRRule(startDate: Date? = nil) -> String? {
        guard frequency != .none else { return nil }
        var components: [String] = []
        components.append("FREQ=\(frequency.rruleValue)")
        if interval != 1 {
            components.append("INTERVAL=\(interval)")
        }

        switch frequency {
        case .weekly:
            if let weekdays, !weekdays.isEmpty {
                let symbols = weekdays.sorted().compactMap { RepeatRule.weekdaySymbol(for: $0) }
                if !symbols.isEmpty {
                    components.append("BYDAY=\(symbols.joined(separator: ","))")
                }
            }
        case .monthly:
            if monthMode == .byDate, let monthDays, !monthDays.isEmpty {
                let values = monthDays.sorted().map { String($0) }.joined(separator: ",")
                components.append("BYMONTHDAY=\(values)")
            } else if monthMode == .byWeekday,
                      let ordinal = weekOrdinal,
                      let weekday,
                      let prefix = RepeatRule.rrulePrefix(forOrdinal: ordinal),
                      let symbol = RepeatRule.weekdaySymbol(for: weekday) {
                components.append("BYDAY=\(prefix)\(symbol)")
            }
        case .yearly:
            if let months, !months.isEmpty {
                let values = months.sorted().map { String($0) }.joined(separator: ",")
                components.append("BYMONTH=\(values)")
            }
            if yearMode == .byWeekday,
               let ordinal = weekOrdinal,
               let weekday,
               let prefix = RepeatRule.rrulePrefix(forOrdinal: ordinal),
               let symbol = RepeatRule.weekdaySymbol(for: weekday) {
                components.append("BYDAY=\(prefix)\(symbol)")
            } else if let monthDays, !monthDays.isEmpty {
                let values = monthDays.sorted().map { String($0) }.joined(separator: ",")
                components.append("BYMONTHDAY=\(values)")
            }
        default:
            break
        }

        switch endType {
        case .never:
            break
        case .count:
            if let count, count > 0 {
                components.append("COUNT=\(count)")
            }
        case .until:
            if let endDate {
                components.append("UNTIL=\(RepeatRule.icsDateFormatter.string(from: endDate))")
            }
        }

        return components.joined(separator: ";")
    }

    init?(ekRule: EKRecurrenceRule) {
        let frequency: RepeatFrequency
        switch ekRule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default:
            return nil
        }

        self.init(frequency: frequency, interval: max(1, ekRule.interval))

        if let end = ekRule.recurrenceEnd {
            let occurrenceCount = end.occurrenceCount
            if occurrenceCount > 0 {
                endType = .count
                count = occurrenceCount
            } else if let endDate = end.endDate {
                endType = .until
                self.endDate = endDate
            }
        }

        switch frequency {
        case .weekly:
            weekdays = ekRule.daysOfTheWeek?.map { Int($0.dayOfTheWeek.rawValue) }
        case .monthly:
            if let days = ekRule.daysOfTheMonth, !days.isEmpty {
                monthMode = .byDate
                monthDays = days.map { $0.intValue }
            } else if let day = ekRule.daysOfTheWeek?.first {
                monthMode = .byWeekday
                weekday = Int(day.dayOfTheWeek.rawValue)
                weekOrdinal = RepeatRule.ordinal(fromWeekNumber: day.weekNumber)
            }
        case .yearly:
            if let months = ekRule.monthsOfTheYear, !months.isEmpty {
                self.months = months.map { $0.intValue }
            }
            if let day = ekRule.daysOfTheWeek?.first {
                yearMode = .byWeekday
                weekday = Int(day.dayOfTheWeek.rawValue)
                weekOrdinal = RepeatRule.ordinal(fromWeekNumber: day.weekNumber)
            } else if let days = ekRule.daysOfTheMonth, !days.isEmpty {
                yearMode = .byDate
                monthDays = days.map { $0.intValue }
            }
        default:
            break
        }
    }

    private static func makeDayOfWeek(_ value: Int, weekNumber: Int = 0) -> EKRecurrenceDayOfWeek? {
        guard let weekday = EKWeekday(rawValue: value) else { return nil }
        return EKRecurrenceDayOfWeek(weekday, weekNumber: weekNumber)
    }

    private static func weekNumber(fromOrdinal ordinal: Int) -> Int? {
        switch ordinal {
        case 1...5:
            return ordinal
        case 6:
            return -2
        case 7:
            return -1
        default:
            return nil
        }
    }

    private static func ordinal(fromWeekNumber weekNumber: Int) -> Int? {
        switch weekNumber {
        case 1...5:
            return weekNumber
        case -1:
            return 7
        case -2:
            return 6
        default:
            return nil
        }
    }

    private static func rrulePrefix(forOrdinal ordinal: Int) -> String? {
        switch ordinal {
        case 1...5:
            return String(ordinal)
        case 6:
            return "-2"
        case 7:
            return "-1"
        default:
            return nil
        }
    }

    private static func weekdaySymbol(for index: Int) -> String? {
        let symbols = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        guard index >= 1, index <= symbols.count else { return nil }
        return symbols[index - 1]
    }

    private static let icsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

private extension RepeatFrequency {
    func toEKRecurrenceFrequency() -> EKRecurrenceFrequency? {
        switch self {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        case .none: return nil
        }
    }

    var rruleValue: String {
        switch self {
        case .daily: return "DAILY"
        case .weekly: return "WEEKLY"
        case .monthly: return "MONTHLY"
        case .yearly: return "YEARLY"
        case .none: return "NONE"
        }
    }
}
