import UIKit
import SnapKit
import Combine

/// 月份页面视图（MVVM 架构）
/// 包含 FSCalendar 和事件列表 UITableView
class MonthPageView: UIView {

    // MARK: - UI Components

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
        calendar.appearance.todayColor = .systemRed
        calendar.appearance.selectionColor = .systemCyan
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
        table.showsVerticalScrollIndicator = false
        return table
    }()

    // MARK: - Properties

    /// ViewModel
    var viewModel: MonthPageViewModel?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Callbacks

    /// 日期选择回调
    var onDateSelected: ((Date) -> Void)?

    /// 事件选择回调
    var onEventSelected: ((Event) -> Void)?

    /// 日历范围变化回调
    var onCalendarScopeChanged: ((FSCalendarScope) -> Void)?

    /// 日历高度变化回调
    var onCalendarHeightChanged: ((CGFloat) -> Void)?

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupCalendar()
        setupTableView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupCalendar()
        setupTableView()
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .systemBackground

        addSubview(calendarView)
        addSubview(tableView)

        // 布局约束
        calendarView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(5)
            make.trailing.equalToSuperview().offset(-5)
            make.top.equalToSuperview()
            make.height.equalTo(450)  // 默认高度，会动态调整
        }

        tableView.snp.makeConstraints { make in
            make.top.equalTo(calendarView.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func setupCalendar() {
        calendarView.delegate = self
        calendarView.dataSource = self
        calendarView.register(CustomCalendarCell.self, forCellReuseIdentifier: "CustomCell")
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EventListCell.self, forCellReuseIdentifier: EventListCell.reuseIdentifier)
    }

    /// 配置 ViewModel
    func configure(with viewModel: MonthPageViewModel) {
        // 如果是同一个 ViewModel，不需要重新设置
        if self.viewModel === viewModel {
            return
        }

        self.viewModel = viewModel
        setupBindings()

        // 初始设置 - 不立即 reloadData，让 Combine 绑定来触发
        calendarView.setCurrentPage(viewModel.currentMonth, animated: false)
        calendarView.select(viewModel.selectedDate, scrollToDate: false)
    }

    private func setupBindings() {
        guard let viewModel = viewModel else { return }

        // 清除旧的订阅
        cancellables.removeAll()

        // 监听月份变化
        viewModel.$currentMonth
            .receive(on: DispatchQueue.main)
            .dropFirst() // 跳过初始值
            .sink { [weak self] month in
                print("📅 [\(viewModel.monthTitle)] currentMonth changed, setCurrentPage")
                self?.calendarView.setCurrentPage(month, animated: false)
            }
            .store(in: &cancellables)

        // 监听选中日期变化
        viewModel.$selectedDate
            .receive(on: DispatchQueue.main)
            .dropFirst() // 跳过初始值
            .sink { [weak self] date in
                print("📅 [\(viewModel.monthTitle)] selectedDate changed to \(date.formatted()), select and reload tableView")
                self?.calendarView.select(date, scrollToDate: false)
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)

        // 监听事件列表变化 - 跳过初始的空数组
        viewModel.$monthEvents
            .receive(on: DispatchQueue.main)
            .dropFirst() // 跳过初始值（空数组）
            .removeDuplicates { oldEvents, newEvents in
                // 比较 ID 集合，避免重复刷新
                return Set(oldEvents.map { $0.id }) == Set(newEvents.map { $0.id })
            }
            .sink { [weak self] events in
                print("📅 [\(viewModel.monthTitle)] monthEvents changed (count: \(events.count)), reloadData")
                self?.calendarView.reloadData()
            }
            .store(in: &cancellables)

        // 监听选中日期的事件变化 - 使用 removeDuplicates 避免重复刷新
        viewModel.$selectedDateEvents
            .receive(on: DispatchQueue.main)
            .removeDuplicates { oldEvents, newEvents in
                // 比较 ID 集合，避免重复刷新
                return Set(oldEvents.map { $0.id }) == Set(newEvents.map { $0.id })
            }
            .sink { [weak self] events in
                print("📅 [\(viewModel.monthTitle)] selectedDateEvents changed (count: \(events.count)), reload tableView")
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)

        // 初始渲染一次（让用户看到界面）
        print("📅 [\(viewModel.monthTitle)] Initial render")
        calendarView.reloadData()
        tableView.reloadData()
    }

    /// 更新日历高度
    func updateCalendarHeight(_ height: CGFloat) {
        calendarView.snp.updateConstraints { make in
            make.height.equalTo(height)
        }
        layoutIfNeeded()
        onCalendarHeightChanged?(height)
    }
}

// MARK: - FSCalendarDataSource

extension MonthPageView: FSCalendarDataSource {

    func calendar(_ calendar: FSCalendar, cellFor date: Date, at position: FSCalendarMonthPosition) -> FSCalendarCell {
        let cell = calendar.dequeueReusableCell(withIdentifier: "CustomCell", for: date, at: position) as! CustomCalendarCell

        // 从 ViewModel 获取事件
        let events = viewModel?.events(for: date) ?? []
        cell.configure(with: date, events: events)
//         print("日期:\(date.formatted()),事件数:\(events.count)")
        return cell
    }

    func calendar(_ calendar: FSCalendar, numberOfEventsFor date: Date) -> Int {
        // 返回 0，因为我们使用自定义 cell 来显示事件
        return 0
    }
}

// MARK: - FSCalendarDelegate

extension MonthPageView: FSCalendarDelegate {

    func calendar(_ calendar: FSCalendar, didSelect date: Date, at monthPosition: FSCalendarMonthPosition) {
        // 更新 ViewModel
        viewModel?.selectDate(date)

        // 通知外部
        onDateSelected?(date)
    }

    func calendar(_ calendar: FSCalendar, boundingRectWillChange bounds: CGRect, animated: Bool) {
        updateCalendarHeight(bounds.height)

        if animated {
            UIView.animate(withDuration: 0.3) {
                self.layoutIfNeeded()
            }
        }

        // 通知外部
        onCalendarScopeChanged?(calendar.scope)
    }

    func calendar(_ calendar: FSCalendar, shouldSelect date: Date, at monthPosition: FSCalendarMonthPosition) -> Bool {
        // 可以添加日期选择的业务逻辑
        return true
    }
}

// MARK: - UITableViewDataSource

extension MonthPageView: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = viewModel?.selectedDateEvents.count ?? 0
        print("📱 [\(viewModel?.monthTitle ?? "?")] TableView numberOfRows: \(count), selectedDate: \(viewModel?.selectedDate.formatted() ?? "?")")
        return count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: EventListCell.reuseIdentifier, for: indexPath) as? EventListCell,
              let viewModel = viewModel,
              indexPath.row < viewModel.selectedDateEvents.count else {
            return UITableViewCell()
        }

        let event = viewModel.selectedDateEvents[indexPath.row]
        cell.configure(with: event)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension MonthPageView: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if let viewModel = viewModel,
           indexPath.row < viewModel.selectedDateEvents.count {
            let event = viewModel.selectedDateEvents[indexPath.row]
            onEventSelected?(event)
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
}
