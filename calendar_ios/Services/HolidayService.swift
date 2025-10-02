import Foundation

/// 节假日服务
/// 提供中国法定节假日和农历日期查询
final class HolidayService {
    static let shared = HolidayService()

    private let chineseCalendar: Calendar
    private let gregorianCalendar: Calendar

    // 中国法定节假日（2025年）
    private let holidays: [String: String] = [
        "2025-01-01": "元旦",
        "2025-01-28": "除夕",
        "2025-01-29": "春节",
        "2025-01-30": "春节",
        "2025-01-31": "春节",
        "2025-02-01": "春节",
        "2025-02-02": "春节",
        "2025-04-04": "清明节",
        "2025-04-05": "清明节",
        "2025-04-06": "清明节",
        "2025-05-01": "劳动节",
        "2025-05-02": "劳动节",
        "2025-05-03": "劳动节",
        "2025-05-31": "端午节",
        "2025-06-01": "端午节",
        "2025-06-02": "端午节",
        "2025-10-01": "国庆节",
        "2025-10-02": "国庆节",
        "2025-10-03": "国庆节",
        "2025-10-04": "国庆节",
        "2025-10-05": "国庆节",
        "2025-10-06": "中秋节",
        "2025-10-07": "中秋节",
        "2025-10-08": "中秋节"
    ]

    // 农历重要节日
    private let lunarFestivals: [String: String] = [
        "1-1": "春节",
        "1-15": "元宵节",
        "5-5": "端午节",
        "7-7": "七夕节",
        "8-15": "中秋节",
        "9-9": "重阳节",
        "12-8": "腊八节"
    ]

    private init() {
        var chinese = Calendar(identifier: .chinese)
        chinese.locale = Locale(identifier: "zh_CN")
        self.chineseCalendar = chinese

        self.gregorianCalendar = Calendar.current
    }

    /// 获取指定日期的节假日名称
    func getHoliday(for date: Date) -> String? {
        let dateString = formatDate(date)
        return holidays[dateString]
    }

    /// 获取指定日期的农历信息
    func getLunarDate(for date: Date) -> String {
        let components = chineseCalendar.dateComponents([.year, .month, .day], from: date)

        guard let month = components.month, let day = components.day else {
            return ""
        }

        // 检查是否是农历节日
        let lunarKey = "\(month)-\(day)"
        if let festival = lunarFestivals[lunarKey] {
            return festival
        }

        // 返回农历日期
        let monthStr = lunarMonthString(month)
        let dayStr = lunarDayString(day)

        if day == 1 {
            return monthStr
        } else {
            return dayStr
        }
    }

    /// 获取副标题（优先显示节假日，其次农历）
    func getSubtitle(for date: Date) -> String? {
        // 优先显示节假日
        if let holiday = getHoliday(for: date) {
            return holiday
        }

        // 显示农历
        let lunar = getLunarDate(for: date)
        return lunar.isEmpty ? nil : lunar
    }

    // MARK: - Private Methods

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func lunarMonthString(_ month: Int) -> String {
        let months = ["正月", "二月", "三月", "四月", "五月", "六月",
                     "七月", "八月", "九月", "十月", "冬月", "腊月"]
        guard month >= 1 && month <= 12 else { return "" }
        return months[month - 1]
    }

    private func lunarDayString(_ day: Int) -> String {
        let days = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                   "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                   "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
        guard day >= 1 && day <= 30 else { return "" }
        return days[day - 1]
    }
}
