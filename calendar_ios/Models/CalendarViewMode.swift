import Foundation
import UIKit

enum CalendarViewMode: CaseIterable {
    case collapsed
    case normal
    case expanded

    var rowHeight: CGFloat {
        switch self {
        case .collapsed:
            return 60
        case .normal:
            return 80
        case .expanded:
            return 120
        }
    }

    var maxEventCount: Int {
        switch self {
        case .collapsed, .normal:
            return 4
        case .expanded:
            return Int.max
        }
    }

    var showEventText: Bool {
        switch self {
        case .expanded:
            return true
        default:
            return false
        }
    }

    var scope: FSCalendarScope {
        switch self {
        case .collapsed:
            return .week
        case .normal:
            return .month
        case .expanded:
            return .month
        }
    }

    static func from(scope: FSCalendarScope, currentHeight: CGFloat) -> CalendarViewMode {
        switch scope {
        case .week:
            return .collapsed
        case .month:
            if currentHeight > CalendarViewMode.expanded.rowHeight {
                return .expanded
            }
            return .normal
        @unknown default:
            return .normal
        }
    }
}
