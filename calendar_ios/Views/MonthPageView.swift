import UIKit
import SnapKit

/// 月份页面视图
/// 包含 FSCalendar 和事件列表 UITableView
class MonthPageView: UIView {

    /// 日历视图
    let calendarView: FSCalendar = {
        let calendar = FSCalendar()
        calendar.scrollEnabled = false  // 禁用左右滚动
        calendar.scope = .month
        calendar.firstWeekday = 1  // 周日开始
        calendar.placeholderType = .fillHeadTail
        calendar.scrollDirection = .horizontal
        let maxHeight = DeviceHelper.screenHeight - DeviceHelper.navigationBarTotalHeight() - DeviceHelper.getBottomSafeAreaInset() - 54.0 - 30.0  // 30 是 weekdayLabel 高度
        calendar.maxHeight = maxHeight

        // 隐藏自带的星期标签
        calendar.weekdayHeight = 0
        calendar.headerHeight = 0

        // 样式配置
        calendar.appearance.headerMinimumDissolvedAlpha = 0.0
        calendar.appearance.todayColor = .systemBlue
        calendar.appearance.selectionColor = .systemBlue
        calendar.appearance.titleDefaultColor = .label
        calendar.appearance.titleTodayColor = .systemBlue
        calendar.appearance.headerTitleColor = .label
        calendar.appearance.weekdayTextColor = .secondaryLabel

        return calendar
    }()

    /// 事件列表
    let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .systemBackground
        table.separatorStyle = .singleLine
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 60
        table.showsVerticalScrollIndicator = true
        return table
    }()

    /// 当前显示的月份
    var currentMonth: Date = Date() {
        didSet {
            calendarView.setCurrentPage(currentMonth, animated: false)
        }
    }

    /// 事件数据
    var events: [Event] = [] {
        didSet {
            tableView.reloadData()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = .systemBackground

        addSubview(calendarView)
        addSubview(tableView)

        // 布局约束（初始约束，后续会根据模式调整）
        calendarView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(500)  // 默认高度，后续会动态调整
        }

        tableView.snp.makeConstraints { make in
            make.top.equalTo(calendarView.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    /// 配置月份页面
    /// - Parameters:
    ///   - month: 要显示的月份
    ///   - events: 事件数据
    func configure(month: Date, events: [Event]) {
        self.currentMonth = month
        self.events = events
        calendarView.reloadData()
    }

    /// 更新日历高度
    /// - Parameter height: 新的高度
    func updateCalendarHeight(_ height: CGFloat) {
        calendarView.snp.updateConstraints { make in
            make.height.equalTo(height)
        }
        layoutIfNeeded()
    }
}
