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
    private var suppressScopeCallback = false
    private var calendarHeightConstraint: Constraint?
    private var currentSlotLimit: Int
    private var monthCapacityCache: [String: Int] = [:]

    // MARK: - Callbacks

    /// 日期选择回调
    var onDateSelected: ((Date) -> Void)?

    /// 事件选择回调
    var onEventSelected: ((Event) -> Void)?

    /// 日历范围变化回调
    var onCalendarScopeChanged: ((MonthPageView, FSCalendarScope) -> Void)?

    /// 日历高度变化回调
    var onCalendarHeightChanged: ((CGFloat) -> Void)?

    // MARK: - Initialization

    override init(frame: CGRect) {
        currentSlotLimit = MonthPageView.baselineSlotLimit()
        super.init(frame: frame)
        setupUI()
        setupCalendar()
        setupTableView()
    }

    required init?(coder: NSCoder) {
        currentSlotLimit = MonthPageView.baselineSlotLimit()
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

        let initialMonth = calendarView.currentPage
        let initialHeight = calendarHeight(for: initialMonth)

        // 布局约束
        calendarView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(5)
            make.trailing.equalToSuperview().offset(-5)
            make.top.equalToSuperview()
            calendarHeightConstraint = make.height.equalTo(initialHeight).constraint
        }

        currentSlotLimit = slotLimit(for: initialHeight, month: initialMonth)
        cacheCapacity(for: initialMonth, capacity: currentSlotLimit)

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
        let initialHeight = calendarHeight(for: viewModel.currentMonth)
        calendarHeightConstraint?.update(offset: initialHeight)
        let capacity = slotLimit(for: calendarView.maxHeight, month: viewModel.currentMonth)
        cacheCapacity(for: viewModel.currentMonth, capacity: capacity)
        updateSlotLimit(for: initialHeight, month: viewModel.currentMonth)
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
                guard let self = self else { return }
                self.calendarView.setCurrentPage(month, animated: false)
                let maxCapacity = self.slotLimit(for: self.calendarView.maxHeight, month: month)
                self.cacheCapacity(for: month, capacity: maxCapacity)

                let monthHeight = self.calendarHeight(for: month)
                self.calendarHeightConstraint?.update(offset: monthHeight)
                self.updateSlotLimit(for: monthHeight, month: month)
            }
            .store(in: &cancellables)

        // 监听选中日期变化
        viewModel.$selectedDate
            .receive(on: DispatchQueue.main)
            .dropFirst() // 跳过初始值
            .sink { [weak self] date in
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
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)

        // 初始渲染一次（让用户看到界面）
        calendarView.reloadData()
        tableView.reloadData()
    }

    /// 外部同步 scope
    func applyScope(_ scope: FSCalendarScope, animated: Bool) {
        if calendarView.scope != scope {
            suppressScopeCallback = true
            calendarView.setScope(scope, animated: animated)
            suppressScopeCallback = false
        }
        adjustHeightAndSlots(for: scope)
    }

    /// 更新日历高度
    func updateCalendarHeight(_ height: CGFloat) {
        calendarHeightConstraint?.update(offset: height)
        updateSlotLimit(for: height, month: calendarView.currentPage)
        layoutIfNeeded()
        onCalendarHeightChanged?(height)
    }

    private func rowCount(for month: Date) -> Int {
        if calendarView.scope == .week {
            return 1
        }

        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: month) else {
            return 6
        }

        let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let calendarFirstWeekday = Int(calendarView.firstWeekday)
        let leadingPlaceholders = (firstWeekday - calendarFirstWeekday + 7) % 7
        let totalSlots = range.count + leadingPlaceholders
        let rows = Int(ceil(Double(totalSlots) / 7.0))
        return max(1, rows)
    }

    private static func baselineSlotLimit() -> Int {
        DeviceHelper.isPad || DeviceHelper.isLargeScreen ? 4 : 3
    }

    private func baselineSlotLimit() -> Int {
        MonthPageView.baselineSlotLimit()
    }

    private func rowHeightForMonthMode() -> CGFloat {
        let metrics = CustomCalendarCell.layoutMetrics
        let slots = baselineSlotLimit()
        let slotHeight = CGFloat(slots) * metrics.eventSlotHeight
        let spacing = CGFloat(max(slots, 0)) * metrics.eventSlotSpacing
        return metrics.reservedHeight + slotHeight + spacing
    }

    private func calendarHeight(for month: Date) -> CGFloat {
        CGFloat(rowCount(for: month)) * rowHeightForMonthMode()
    }

    private func slotLimit(for height: CGFloat, month: Date) -> Int {
        let baseline = baselineSlotLimit()
        let rows = max(rowCount(for: month), 1)
        guard height > 0 else { return baseline }

        let rowHeight = height / CGFloat(rows)
        let metrics = CustomCalendarCell.layoutMetrics
        let available = rowHeight - metrics.reservedHeight
        guard available > 0 else { return baseline }

        let slotUnit = metrics.eventSlotHeight + metrics.eventSlotSpacing
        guard slotUnit > 0 else { return baseline }

        let slots = Int(floor((available + metrics.eventSlotSpacing) / slotUnit))
        return max(baseline, slots)
    }

    private func updateSlotLimit(for height: CGFloat, month: Date) {
        let scope = calendarView.scope

        let baselineLimit = baselineSlotLimit()
        let capacity = cachedCapacity(for: month)
        applyCapacityToVisibleCells(capacity)

        let targetLimit: Int
        switch scope {
        case .maxHeight:
            targetLimit = min(capacity, slotLimit(for: height, month: month))
        default:
            targetLimit = min(capacity, baselineLimit)
        }

        guard targetLimit != currentSlotLimit else { return }
        currentSlotLimit = targetLimit
        applySlotLimitToVisibleCells()
    }

    private func cacheCapacity(for month: Date, capacity: Int) {
        guard capacity > 0 else { return }
        monthCapacityCache[monthKey(for: month)] = max(monthCapacityCache[monthKey(for: month)] ?? 0, capacity)
        applyCapacityToVisibleCells(capacity)
    }

    private func cachedCapacity(for month: Date) -> Int {
        monthCapacityCache[monthKey(for: month)] ?? baselineSlotLimit()
    }

    private func applyCapacityToVisibleCells(_ capacity: Int) {
        for case let cell as CustomCalendarCell in calendarView.visibleCells() {
            cell.ensureSlotCapacity(capacity)
        }
    }

    private func monthKey(for month: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: month)
        let year = components.year ?? 0
        let monthValue = components.month ?? 0
        return String(format: "%04d-%02d", year, monthValue)
    }

    private func adjustHeightAndSlots(for scope: FSCalendarScope) {
        let currentMonth = calendarView.currentPage
        let targetHeight: CGFloat

        switch scope {
        case .maxHeight:
            targetHeight = calendarView.maxHeight
            let capacity = slotLimit(for: targetHeight, month: currentMonth)
            cacheCapacity(for: currentMonth, capacity: capacity)
            updateSlotLimit(for: targetHeight, month: currentMonth)
        case .week:
            targetHeight = calendarHeight(for: currentMonth) / CGFloat(max(rowCount(for: currentMonth), 1))
            updateSlotLimit(for: targetHeight, month: currentMonth)
        case .month:
            fallthrough
        default:
            targetHeight = calendarHeight(for: currentMonth)
            updateSlotLimit(for: targetHeight, month: currentMonth)
        }

        calendarHeightConstraint?.update(offset: targetHeight)
        layoutIfNeeded()
        onCalendarHeightChanged?(targetHeight)
    }

    private func applySlotLimitToVisibleCells() {
        for case let cell as CustomCalendarCell in calendarView.visibleCells() {
            cell.updateSlotLimit(currentSlotLimit)
        }
    }
}

// MARK: - FSCalendarDataSource

extension MonthPageView: FSCalendarDataSource {

    func calendar(_ calendar: FSCalendar, cellFor date: Date, at position: FSCalendarMonthPosition) -> FSCalendarCell {
        let cell = calendar.dequeueReusableCell(withIdentifier: "CustomCell", for: date, at: position) as! CustomCalendarCell

        let events = viewModel?.events(for: date) ?? []
        let capacity = cachedCapacity(for: calendar.currentPage)
        cell.ensureSlotCapacity(capacity)
        cell.updateSlotLimit(currentSlotLimit, refresh: false)
        cell.configure(with: date, events: events)

        // 检查是否有连续事件的开始位置，如果有，提升该 cell 的层级
        for event in events {
            if isMultiDayEventStart(event: event, date: date) {
                // 这个 cell 包含连续事件的开始，提升其层级
                if date.formatted() == "10/26/2025, 00:00" {
//                    print("date.formatted():\(date.formatted())")
                }
                cell.layer.zPosition = 100
                // 确保 cell 的内容可以超出边界
                cell.clipsToBounds = false
                cell.contentView.clipsToBounds = false
                break
            }
        }

        return cell
    }

    /// 判断是否是多天事件的开始
    private func isMultiDayEventStart(event: Event, date: Date) -> Bool {
        let calendar = Calendar.current
        let eventStart = calendar.startOfDay(for: event.startDate)
        let eventEnd = calendar.startOfDay(for: event.endDate)
        let currentDate = calendar.startOfDay(for: date)

        // 是事件的开始日期且跨越多天
        let isStart = calendar.isDate(eventStart, inSameDayAs: currentDate)
        let isMultiDay = !calendar.isDate(eventStart, inSameDayAs: eventEnd)

        // 或者是每周的开始（周日）且事件仍在继续
        let weekday = calendar.component(.weekday, from: date)
        let isWeekStart = weekday == 1 // 周日
        let isInEventRange = currentDate >= eventStart && currentDate < eventEnd

        return (isStart && isMultiDay) || (isWeekStart && isInEventRange && !calendar.isDate(currentDate, inSameDayAs: eventEnd))
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

//        if animated {
//            UIView.animate(withDuration: 0.3) {
//                self.layoutIfNeeded()
//            }
//        }

        // 通知外部
        if suppressScopeCallback {
            return
        }
        onCalendarScopeChanged?(self, calendar.scope)
    }

    func calendar(_ calendar: FSCalendar, shouldSelect date: Date, at monthPosition: FSCalendarMonthPosition) -> Bool {
        // 可以添加日期选择的业务逻辑
        return true
    }

    func calendar(_ calendar: FSCalendar, willDisplay cell: FSCalendarCell, for date: Date, at position: FSCalendarMonthPosition) {
        // 在 cell 即将显示时再次调整层级
        if let customCell = cell as? CustomCalendarCell {
            let events = viewModel?.events(for: date) ?? []
            for event in events {
                if isMultiDayEventStart(event: event, date: date) {
                    // 提升包含连续事件开始的 cell
                    cell.layer.zPosition = 100
                    cell.superview?.bringSubviewToFront(cell)

                    // 确保内容不被裁剪
                    cell.clipsToBounds = false
                    cell.contentView.clipsToBounds = false

                    // 调用 cell 自己的 layoutSubviews 来处理内部层级
                    cell.setNeedsLayout()
                    break
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension MonthPageView: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = viewModel?.selectedDateEvents.count ?? 0
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
