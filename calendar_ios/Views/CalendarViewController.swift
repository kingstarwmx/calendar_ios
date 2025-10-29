import UIKit
import Combine
import EventKit

@MainActor
final class CalendarViewController: UIViewController {
    private let viewModel: EventViewModel
    private var cancellables: Set<AnyCancellable> = []

    /// 自定义星期标签
    private let weekdayLabel = CustomWeekdayLabel()

    /// 月份横向滚动容器
    private let monthScrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.isPagingEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.bounces = false
        return scroll
    }()

    /// 三个月份页面视图（复用）
    private var monthPageViews: [MonthPageView] = []

    /// 当前月视图中心页对应的月份（取月初）
    private var currentMonthAnchor: Date = Date()
    /// 当前周视图中心页对应的周起始日
    private var currentWeekAnchor: Date = Date()

    /// 月份标签
    private let monthLabel = UILabel()

    /// 输入工具栏
    private let inputToolbar = InputToolbarView()

    /// 是否正在重置 scrollView 位置（避免递归调用）
    private var isResettingScrollView = false

    /// 手势方向判断阈值（垂直速度必须 > 横向速度 * 此值才认为是垂直滑动）
    /// 值越小越灵敏，但容易误触；值越大越准确，但灵敏度降低
    /// 建议范围：1.1 ~ 1.5
    private let gestureDirectionThreshold: CGFloat = 1.1

    /// 记录每个月份用户选中的日期（key: "yyyy-MM", value: 选中的日期）
    private var selectedDatesPerMonth: [String: Date] = [:]
    /// 记录周模式下已经加载过事件的月份 key（yyyy-MM）
    private var loadedMonthsForWeekScope: Set<String> = []
    /// 记录每周用户选中的日期（key: 周起始日"yyyy-MM-dd"，value: 选中的日期）
    private var selectedDatesPerWeek: [String: Date] = [:]
    private var unifiedCalendarScope: FSCalendarScope = .month

    init(viewModel: EventViewModel? = nil) {
        self.viewModel = viewModel ?? EventViewModel()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.viewModel = EventViewModel()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureUI()
        setupMonthPages()
        setupKeyboardObservers()

        // 延迟到下一个 runloop，确保视图已添加到层级中
        DispatchQueue.main.async { [weak self] in
            self?.bindViewModel()

            // 加载数据
            self?.loadInitialData()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // 更新所有 pageView 的高度以匹配 scrollView
        let scrollHeight = monthScrollView.bounds.height
        if scrollHeight > 0 {
            for pageView in monthPageViews {
                pageView.frame.size.height = scrollHeight
            }
        }
    }

    private func loadInitialData() {

        // 计算五个月的日期范围（前两个月到后两个月）
        let calendar = Calendar.current
        let today = Date()

        guard let startOfTwoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: today)?.startOfMonth,
              let endOfTwoMonthsLater = calendar.date(byAdding: .month, value: 2, to: today)?.endOfMonth else {
            return
        }

        let fiveMonthRange = DateInterval(start: startOfTwoMonthsAgo, end: endOfTwoMonthsLater)

        // 只调用一次，requestDeviceCalendarAccess 内部会自动加载事件
        // 但需要修改 requestDeviceCalendarAccess 来支持传入 dateRange
        viewModel.requestDeviceCalendarAccessWithRange(dateRange: fiveMonthRange) {
            // print("✅ 数据加载完成")
        }
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        navigationItem.titleView = monthLabel

        // 右侧按钮组：添加事件按钮 + 调试按钮
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        let debugButton = UIBarButtonItem(title: "🐛", style: .plain, target: self, action: #selector(debugExportTapped))
        navigationItem.rightBarButtonItems = [addButton, debugButton]

        // 左侧按钮组：设置 + 测试按钮
        let settingsButton = UIBarButtonItem(title: "设置", style: .plain, target: self, action: #selector(settingsTapped))
        let testButton = UIBarButtonItem(title: "📅", style: .plain, target: self, action: #selector(testDateTapped))
        navigationItem.leftBarButtonItems = [settingsButton, testButton]

        monthLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        monthLabel.textColor = .label

        view.addSubview(weekdayLabel)
        view.addSubview(monthScrollView)
        view.addSubview(inputToolbar)

        setupConstraints()
        setupInputToolbar()

        updateMonthLabel(for: viewModel.selectedDate)
    }

    private func setupConstraints() {
        // 星期标签约束
        weekdayLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.equalToSuperview().offset(8)
            make.trailing.equalToSuperview().offset(-8)
            make.height.equalTo(30)
        }

        // 月份滚动视图约束
        monthScrollView.snp.makeConstraints { make in
            make.top.equalTo(weekdayLabel.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(inputToolbar.snp.top)
        }
    }

    /// 设置三个月份页面视图
    private func setupMonthPages() {
        let screenWidth = DeviceHelper.screenWidth
        let calendar = Calendar.current
        let selected = viewModel.selectedDate
        currentMonthAnchor = selected.startOfMonth
        currentWeekAnchor = startOfWeek(for: selected)

        // 创建三个 MonthPageView 和对应的 ViewModel
        for i in 0..<3 {
            let month = calendar.date(byAdding: .month, value: i - 1, to: currentMonthAnchor)!

            // 创建 ViewModel（先不设置事件，等数据加载完成后再设置）
            let viewModel = MonthPageViewModel(month: month, selectedDate: getSelectedDateForMonth(month))

            // 创建 View
            let pageView = MonthPageView()

            // 配置 View 和 ViewModel
            pageView.configure(with: viewModel)
            pageView.applyScope(unifiedCalendarScope, animated: false)

            // 设置回调
            pageView.onDateSelected = { [weak self] date in
                self?.handleDateSelection(date)
            }

            pageView.onEventSelected = { [weak self] event in
                self?.handleEventSelection(event)
            }

            pageView.onCalendarScopeChanged = { [weak self] page, scope in
                self?.handleCalendarScopeChange(from: page, to: scope)
            }

            pageView.onCalendarHeightChanged = { [weak self] height in
                self?.handleCalendarHeightChange(height)
            }

            // 设置手势处理
            setupPageViewGesture(for: pageView)

            monthScrollView.addSubview(pageView)
            monthPageViews.append(pageView)

            // 设置位置和大小（height 使用 scrollView 的高度，会在 layoutSubviews 中更新）
            pageView.frame = CGRect(x: screenWidth * CGFloat(i), y: 0, width: screenWidth, height: 500)
        }

        // 设置 scrollView 的 contentSize（height 会自动适配）
        monthScrollView.contentSize = CGSize(width: screenWidth * 3, height: 0)
        monthScrollView.delegate = self

        // 初始显示中间页（当前月）
        monthScrollView.contentOffset = CGPoint(x: screenWidth, y: 0)

        // 不立即更新数据，等待数据加载完成
    }

    /// 为每个 pageView 设置手势处理
    private func setupPageViewGesture(for pageView: MonthPageView) {
        let panGesture = UIPanGestureRecognizer(target: pageView.calendarView, action: #selector(pageView.calendarView.handleScopeGesture(_:)))
        panGesture.delegate = self
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 2
        pageView.addGestureRecognizer(panGesture)

        // tableView 的滑动手势需要等待 scope 手势失败
        pageView.tableView.panGestureRecognizer.require(toFail: panGesture)
    }
    private func updateWeekPagesData() {
        guard monthPageViews.count == 3 else { return }

        let calendar = Calendar.current

        // 以当前选中日期定位中心周的起始日
        let anchorDate = viewModel.selectedDate
        let anchorWeekStart = startOfWeek(for: anchorDate)
        currentWeekAnchor = anchorWeekStart
        currentMonthAnchor = anchorDate.startOfMonth
        saveSelectedDateForWeek(anchorDate)

        // 计算前一周、当前周、后一周的起始日
        let weekStarts: [Date] = [
            calendar.date(byAdding: .weekOfYear, value: -1, to: anchorWeekStart) ?? anchorWeekStart,
            anchorWeekStart,
            calendar.date(byAdding: .weekOfYear, value: 1, to: anchorWeekStart) ?? anchorWeekStart
        ]

        for (index, pageView) in monthPageViews.enumerated() {
            guard let weekStart = weekStarts[safe: index] else { continue }
            let weekStartDay = calendar.startOfDay(for: weekStart)
            let weekEndDay = calendar.date(byAdding: .day, value: 6, to: weekStartDay) ?? weekStartDay
            let representativeMonth: Date
            if index == 1 {
                representativeMonth = viewModel.selectedDate.startOfMonth
            } else {
                representativeMonth = monthForWeek(startingAt: weekStartDay)
            }

            let events = viewModel.events.filter { event in
                let eventStart = calendar.startOfDay(for: event.startDate)
                let eventEnd = calendar.startOfDay(for: event.endDate)
                return eventEnd >= weekStartDay && eventStart <= weekEndDay
            }

            var selectedDateForPage = getSelectedDateForWeek(startingAt: weekStartDay)
            if selectedDateForPage < weekStartDay || selectedDateForPage > weekEndDay {
                selectedDateForPage = weekStartDay
                saveSelectedDateForWeek(selectedDateForPage)
            }
            if index == 1 {
                let normalizedSelected = calendar.startOfDay(for: viewModel.selectedDate)
                if calendar.isDate(normalizedSelected, equalTo: weekStartDay, toGranularity: .weekOfYear) {
                    selectedDateForPage = normalizedSelected
                } else {
                    selectedDateForPage = weekStartDay
                }
                saveSelectedDateForWeek(selectedDateForPage)
                currentMonthAnchor = representativeMonth
                if !calendar.isDate(viewModel.selectedDate, inSameDayAs: selectedDateForPage) {
                    viewModel.selectedDate = selectedDateForPage
                }
            }

            if let existingViewModel = pageView.viewModel {
                existingViewModel.configure(month: representativeMonth, events: events)
                print("representativeMonth:\(representativeMonth) selectedDateForPage:\(selectedDateForPage)")
                if !calendar.isDate(existingViewModel.selectedDate, inSameDayAs: selectedDateForPage) {
                    existingViewModel.selectDate(selectedDateForPage)
                    
                }
            } else {
                let newViewModel = MonthPageViewModel(month: representativeMonth, selectedDate: selectedDateForPage)
                newViewModel.configure(month: representativeMonth, events: events)
                pageView.configure(with: newViewModel)
            }

            pageView.applyScope(.week, animated: false)

            if let currentSelected = pageView.calendarView.selectedDate {
                if !calendar.isDate(currentSelected, inSameDayAs: selectedDateForPage) {
                    pageView.calendarView.select(selectedDateForPage, scrollToDate: false)
                }
            } else {
                pageView.calendarView.select(selectedDateForPage, scrollToDate: false)
            }

            if !calendar.isDate(pageView.calendarView.currentPage, inSameDayAs: weekStartDay) {
                pageView.calendarView.setCurrentPage(weekStartDay, animated: false)
            }
            pageView.calendarView.reloadData()
            pageView.calendarView.layoutIfNeeded()
        }

        updateMonthLabel(for: viewModel.selectedDate)
        debugLogWeekPages(reason: "updateWeekPagesData", weekStarts: weekStarts)
    }

    private func startOfWeek(for date: Date) -> Date {
        let calendar = Calendar.current
        let normalized = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: normalized)
        let firstWeekday = calendar.firstWeekday
        var diff = weekday - firstWeekday
        if diff < 0 { diff += 7 }
        return calendar.date(byAdding: .day, value: -diff, to: normalized) ?? normalized
    }

    private func monthForWeek(startingAt weekStart: Date) -> Date {
        // 使用周起始日所在月份
        return weekStart.startOfMonth
    }

    private func debugLogWeekPages(reason: String, weekStarts: [Date]) {
#if DEBUG
        guard unifiedCalendarScope == .week else { return }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (index, start) in weekStarts.enumerated() {
                let days = (0..<7).compactMap { offset -> String? in
                    guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                    return formatter.string(from: date)
                }.joined(separator: ",")
                let selected = formatter.string(from: self.getSelectedDateForWeek(startingAt: start))
                print("[WeekDebug][\(reason)] index=\(index) days=[\(days)] selected=\(selected)")
            }
        }
#endif
    }

    /// 更新三个月份页面的数据
    private func updateMonthPagesData() {
        let calendar = Calendar.current
        let centerMonth = currentMonthAnchor.startOfMonth

        // 计算三个月份：前一个月、当前月、后一个月
        let months = [
            calendar.date(byAdding: .month, value: -1, to: centerMonth)!,
            centerMonth,
            calendar.date(byAdding: .month, value: 1, to: centerMonth)!
        ]

        // 为每个页面更新 ViewModel
        for (index, pageView) in monthPageViews.enumerated() {
            let month = months[index].startOfMonth

            // 获取该月份视图实际显示的日期范围（包括前后月的占位日期）
            let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
            let weekday = calendar.component(.weekday, from: firstDayOfMonth)

            // 计算实际显示的起始日期（可能是上个月的日期）
            let daysToSubtract = weekday - 1  // 因为周日是1
            let displayStartDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDayOfMonth)!

            // 计算实际显示的结束日期（6周 * 7天 = 42天）
            let displayEndDate = calendar.date(byAdding: .day, value: 41, to: displayStartDate)!

            // 获取这个显示范围内的所有事件
            let events = viewModel.events.filter { event in
                let eventStart = calendar.startOfDay(for: event.startDate)
                let eventEnd = calendar.startOfDay(for: event.endDate)
                return eventEnd >= displayStartDate && eventStart <= displayEndDate
            }

            // 获取或创建 ViewModel
            if let existingViewModel = pageView.viewModel {
                // 更新现有 ViewModel（configure 方法内部会检查是否真的需要更新）
                existingViewModel.configure(month: month, events: events)

                // 只在日期真的改变时更新选中日期
                let selectedDate = getSelectedDateForMonth(month)
                if !calendar.isDate(existingViewModel.selectedDate, inSameDayAs: selectedDate) {
                    existingViewModel.selectDate(selectedDate)
                }
            } else {
                // 创建新的 ViewModel（用于页面回收后）
                let selectedDate = getSelectedDateForMonth(month)
                let newViewModel = MonthPageViewModel(month: month, selectedDate: selectedDate)
                newViewModel.configure(month: month, events: events)
                pageView.configure(with: newViewModel)
            }

            pageView.applyScope(unifiedCalendarScope, animated: false)
        }

        // 更新月份标签
        let currentMonth = centerMonth
        updateMonthLabel(for: currentMonth)

        // 获取当前月应该选中的日期
        let currentSelectedDate = getSelectedDateForMonth(currentMonth)

        // 只在日期真的改变时更新
        if !calendar.isDate(viewModel.selectedDate, inSameDayAs: currentSelectedDate) {
            viewModel.selectedDate = currentSelectedDate
        }
    }

    // MARK: - MonthPageView Callbacks

    /// 处理日期选择
    private func handleDateSelection(_ date: Date) {
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)

        if unifiedCalendarScope == .week {
            currentWeekAnchor = startOfWeek(for: normalizedDate)
            currentMonthAnchor = normalizedDate.startOfMonth
            saveSelectedDate(normalizedDate)
            saveSelectedDateForWeek(normalizedDate)

            updateMonthLabel(for: normalizedDate)
            viewModel.selectedDate = normalizedDate
        } else {
            let month = normalizedDate.startOfMonth
            currentMonthAnchor = month
            currentWeekAnchor = startOfWeek(for: normalizedDate)
            saveSelectedDate(normalizedDate)
            updateMonthLabel(for: normalizedDate)
            viewModel.selectedDate = normalizedDate
        }
    }

    /// 处理事件选择
    private func handleEventSelection(_ event: Event) {
        // print("📝 选中事件: \(event.title)")

        // TODO: 显示事件详情或编辑页面
        let alert = UIAlertController(title: event.title, message: event.description ?? "无描述", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    /// 处理日历范围变化
    private func handleCalendarScopeChange(from source: MonthPageView, to scope: FSCalendarScope) {
        guard unifiedCalendarScope != scope else { return }
        unifiedCalendarScope = scope

        switch scope {
        case .week:
            let anchor = startOfWeek(for: viewModel.selectedDate)
            currentWeekAnchor = anchor
            currentMonthAnchor = viewModel.selectedDate.startOfMonth
            saveSelectedDate(viewModel.selectedDate)
            saveSelectedDateForWeek(viewModel.selectedDate)
            loadedMonthsForWeekScope.insert(getMonthKey(for: currentWeekAnchor))
            updateWeekPagesData()
        case .month, .maxHeight:
            currentMonthAnchor = viewModel.selectedDate.startOfMonth
            loadedMonthsForWeekScope.removeAll()
            updateMonthPagesData()
        @unknown default:
            break
        }

        for page in monthPageViews where page !== source {
            page.applyScope(scope, animated: false)
        }
    }

    /// 处理日历高度变化
    private func handleCalendarHeightChange(_ height: CGFloat) {
        // 高度变化已在 MonthPageView 内部处理
    }

    /// 获取指定月份应该选中的日期
    /// - Parameter month: 月份
    /// - Returns: 该月份应该选中的日期
    private func getSelectedDateForMonth(_ month: Date) -> Date {
        let monthKey = getMonthKey(for: month)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 如果有记录，返回记录的日期
        if let savedDate = selectedDatesPerMonth[monthKey] {
            return savedDate
        }

        // 如果是当前月，返回今天
        if calendar.isDate(month, equalTo: today, toGranularity: .month) {
            selectedDatesPerMonth[monthKey] = today
            return today
        }

        // 否则返回该月的1号
        let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        selectedDatesPerMonth[monthKey] = firstDayOfMonth
        return firstDayOfMonth
    }

    /// 保存用户在某月选中的日期
    /// - Parameter date: 用户选中的日期
    private func saveSelectedDate(_ date: Date) {
        let monthKey = getMonthKey(for: date)
        selectedDatesPerMonth[monthKey] = date
    }

    /// 获取指定周应该选中的日期（默认返回周首日）
    private func getSelectedDateForWeek(startingAt weekStart: Date) -> Date {
        let key = getWeekKey(for: weekStart)
        return selectedDatesPerWeek[key] ?? weekStart
    }

    /// 保存用户在某周选中的日期
    private func saveSelectedDateForWeek(_ date: Date) {
        let weekStart = startOfWeek(for: date)
        let key = getWeekKey(for: weekStart)
        selectedDatesPerWeek[key] = date
    }

    /// 获取月份的 key（格式：yyyy-MM）
    /// - Parameter date: 日期
    /// - Returns: 月份 key
    private func getMonthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    /// 获取周的 key（格式：yyyy-MM-dd，对应周起始日）
    private func getWeekKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: startOfWeek(for: date))
    }

    private func bindViewModel() {
        viewModel.$events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // 刷新所有月份页面的数据
                if self.unifiedCalendarScope == .week {
                    self.updateWeekPagesData()
                }else {
                    self.updateMonthPagesData()
                }
                
                // print("🔄 日历数据已刷新")
            }
            .store(in: &cancellables)

        viewModel.$selectedDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                guard let self = self else { return }

                // 更新工具栏提示语
                self.inputToolbar.selectedDate = date
            }
            .store(in: &cancellables)
    }

    /// 获取当前显示的月份页面视图
    private func getCurrentMonthPageView() -> MonthPageView? {
        return monthPageViews[safe: 1]
    }

    private func updateMonthLabel(for date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月"
        monthLabel.text = formatter.string(from: date)
    }

    /// 显示提示框
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    /// 设置输入工具栏
    private func setupInputToolbar() {
        // 设置选中日期
        inputToolbar.selectedDate = viewModel.selectedDate

        // 使用SnapKit设置约束
        inputToolbar.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            // 高度 = 54pt内容区 + 底部安全区高度
            make.height.equalTo(54 + DeviceHelper.getBottomSafeAreaInset())
        }
    }

    /// 设置键盘监听
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    /// 键盘显示时
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else {
            return
        }

        // 计算键盘顶部相对于屏幕的位置
        let keyboardTop = view.frame.height - keyboardFrame.height

        // 键盘弹起时，工具栏紧贴键盘，高度只需要54pt
        inputToolbar.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(keyboardTop - 54)
            make.bottom.equalToSuperview().offset(-keyboardFrame.height)
        }

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    /// 键盘隐藏时
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else {
            return
        }

        // 键盘收起时，恢复工具栏位置和高度（包含安全区）
        inputToolbar.snp.remakeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(54 + DeviceHelper.getBottomSafeAreaInset())
        }

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func addTapped() {
        let controller = AddEventViewController()
        controller.onSave = { [weak self] event in
            guard let self else { return }
            Task { await self.viewModel.addEvent(event) }
        }
        let nav = UINavigationController(rootViewController: controller)
        present(nav, animated: true)
    }

    @objc private func debugExportTapped() {
        // 获取当前中间页面的 ViewModel
        let centerIndex = 1  // 中间页面总是 index 1
        guard centerIndex < monthPageViews.count,
              let viewModel = monthPageViews[centerIndex].viewModel else {
            showAlert(title: "错误", message: "无法获取当前月份的数据")
            return
        }

        // 导出JSON
        if let filePath = viewModel.exportEventsToJSON() {
            showAlert(
                title: "✅ 导出成功",
                message: "事件数据已导出到：\n\(filePath)\n\n同时已打印到Console，可以复制使用。\n\n通过Xcode → Window → Devices and Simulators 下载App容器来获取文件。"
            )
        } else {
            showAlert(title: "❌ 导出失败", message: "无法导出事件数据，请查看Console日志")
        }
    }

    @objc private func testDateTapped() {
        // 创建10月9号的日期范围
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 10
        components.day = 11
        components.hour = 0
        components.minute = 0
        components.second = 0

        guard let startDate = calendar.date(from: components),
              let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            showAlert(title: "错误", message: "无法创建日期")
            return
        }

        // 使用系统原生方法获取EKEvent
        Task {
            do {
                let eventStore = EKEventStore()

                // 获取所有日历
                let calendars = eventStore.calendars(for: .event)

                // 创建predicate获取事件
                let predicate = eventStore.predicateForEvents(
                    withStart: startDate,
                    end: endDate,
                    calendars: calendars
                )

                let ekEvents = eventStore.events(matching: predicate)

                // 构建显示内容
                var message = "日期：\(startDate.formatted())\n"
                message += "星期：\(calendar.component(.weekday, from: startDate))\n"
                message += "原始EKEvent数量：\(ekEvents.count)\n\n"

                for (index, ekEvent) in ekEvents.enumerated() {
                    message += "[\(index)] \(ekEvent.title ?? "无标题")\n"
                    message += "    ID: \(ekEvent.eventIdentifier ?? "无ID")\n"
                    message += "    isAllDay: \(ekEvent.isAllDay)\n"
                    message += "    开始: \(ekEvent.startDate?.formatted() ?? "无")\n"
                    message += "    结束: \(ekEvent.endDate?.formatted() ?? "无")\n"
                    message += "    日历: \(ekEvent.calendar?.title ?? "无")\n\n"
                }

                // 显示在弹窗中
                let alert = UIAlertController(title: "10月9号原始EKEvent数据", message: message, preferredStyle: .alert)

                // 添加复制按钮
                alert.addAction(UIAlertAction(title: "复制", style: .default, handler: { _ in
                    UIPasteboard.general.string = message
                    self.showAlert(title: "✅", message: "已复制到剪贴板")
                }))

                alert.addAction(UIAlertAction(title: "关闭", style: .cancel))

                await MainActor.run {
                    self.present(alert, animated: true)
                }
            } catch {
                await MainActor.run {
                    self.showAlert(title: "错误", message: "获取事件失败: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func settingsTapped() {
        let alert = UIAlertController(title: "日历设置", message: "选择一个选项", preferredStyle: .actionSheet)

        // 设备日历同步选项
        alert.addAction(UIAlertAction(title: "设备日历同步", style: .default, handler: { [weak self] _ in
            self?.showDeviceSyncOptions()
        }))

        // 订阅节假日日历
        alert.addAction(UIAlertAction(title: "订阅节假日日历", style: .default, handler: { [weak self] _ in
            self?.showHolidayCalendarGuide()
        }))

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func showDeviceSyncOptions() {
        let alert = UIAlertController(title: "日历权限", message: "应用需要访问系统日历来保存和显示事件", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "授权", style: .default, handler: { [weak self] _ in
            Task { await self?.viewModel.requestDeviceCalendarAccess() }
        }))
        present(alert, animated: true)
    }

    private func showHolidayCalendarGuide() {
        let message = """
        订阅节假日日历步骤：

        1. 打开系统「设置」应用
        2. 选择「日历」→「账户」
        3. 点击「添加账户」→「其他」
        4. 选择「添加已订阅的日历」
        5. 输入节假日日历地址

        推荐日历：
        • 中国节假日（包含调休信息）
        • Apple 官方节假日日历

        订阅后，节假日将自动显示在本应用中。
        """

        let alert = UIAlertController(title: "订阅节假日日历", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UIGestureRecognizerDelegate
extension CalendarViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }

        // 找到对应的 pageView（scope 手势）
        guard let pageView = monthPageViews.first(where: { $0.gestureRecognizers?.contains(gestureRecognizer) == true }) else {
            return true
        }

        let calendar = pageView.calendarView
        let tableView = pageView.tableView

        // 获取滑动方向
        let velocity = panGesture.velocity(in: view)

        // 判断是否为垂直滑动：使用阈值常量
        let isVerticalGesture = abs(velocity.y) > abs(velocity.x) * gestureDirectionThreshold

        // 如果不是明确的垂直滑动，不允许开始 scope 手势
        if !isVerticalGesture {
            return false
        }

        // tableView 在顶部时才允许开始手势
        let shouldBegin = tableView.contentOffset.y <= -tableView.contentInset.top

        if shouldBegin {
            switch calendar.scope {
            case .month:
                // month 模式下
                if velocity.y < 0 {
                    // 向上滑动，切换到 week 模式
                    return true
                }
                if velocity.y > 0 {
                    // 向下滑动，检查是否已达到最大高度
                    let currentHeight = calendar.bounds.height
                    return calendar.maxHeight > currentHeight + 1.0
                }
                return false

            case .week:
                // week 模式下，只允许向下滑动切换到 month 模式
                return velocity.y > 0

            case .maxHeight:
                // maxHeight 模式下，只允许向上滑动
                return velocity.y < 0

            @unknown default:
                return false
            }
        }

        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 如果是 scope 手势和 scrollView 手势，根据方向决定是否同时识别
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
           monthPageViews.first(where: { $0.gestureRecognizers?.contains(gestureRecognizer) == true }) != nil,
           otherGestureRecognizer == monthScrollView.panGestureRecognizer {

            let velocity = panGesture.velocity(in: view)
            // 如果是垂直滑动，不允许同时识别（阻止 scrollView）
            // 使用阈值常量
            return abs(velocity.y) <= abs(velocity.x) * gestureDirectionThreshold
        }

        // 允许 scope 手势和 tableView 的手势同时识别
        guard let pageView = monthPageViews.first(where: { $0.gestureRecognizers?.contains(gestureRecognizer) == true }) else {
            return false
        }
        return otherGestureRecognizer == pageView.tableView.panGestureRecognizer
    }
}

// MARK: - UIScrollViewDelegate
extension CalendarViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView == monthScrollView, !isResettingScrollView else { return }

        let screenWidth = DeviceHelper.screenWidth
        let offsetX = scrollView.contentOffset.x

        if offsetX <= 0 {
            resetScrollViewPosition(direction: .left)
        } else if offsetX >= screenWidth * 2 {
            resetScrollViewPosition(direction: .right)
        }
    }

    /// 重置 ScrollView 位置和页面数据
    /// - Parameter direction: 滑动方向
    private func resetScrollViewPosition(direction: Direction) {
        isResettingScrollView = true

        let screenWidth = DeviceHelper.screenWidth
        let calendar = Calendar.current

        // 根据方向重新排列页面视图
        if direction == .left {
            // 向左滑动：右边视图移到左边（变成前前一个月）
            let rightView = monthPageViews.removeLast()
            monthPageViews.insert(rightView, at: 0)
        } else {
            // 向右滑动：左边视图移到右边（变成后后一个月）
            let leftView = monthPageViews.removeFirst()
            monthPageViews.append(leftView)
        }

        // 重新布局页面位置
        for (index, pageView) in monthPageViews.enumerated() {
            pageView.frame.origin.x = screenWidth * CGFloat(index)
        }

        // 根据当前模式更新数据
        if unifiedCalendarScope == .week {
            let delta = direction == .left ? -1 : 1
            currentWeekAnchor = calendar.date(byAdding: .weekOfYear, value: delta, to: currentWeekAnchor) ?? currentWeekAnchor
            currentMonthAnchor = currentWeekAnchor.startOfMonth
            let storedSelection = getSelectedDateForWeek(startingAt: currentWeekAnchor)
            saveSelectedDate(storedSelection)
            saveSelectedDateForWeek(storedSelection)
            viewModel.selectedDate = storedSelection
            updateWeekPagesData()
        } else {
            let delta = direction == .left ? -1 : 1
            currentMonthAnchor = calendar.date(byAdding: .month, value: delta, to: currentMonthAnchor) ?? currentMonthAnchor
            let centerSelectedDate = getSelectedDateForMonth(currentMonthAnchor)
            viewModel.selectedDate = centerSelectedDate
            saveSelectedDate(centerSelectedDate)
            updateMonthPagesData()
        }

        // 重置 contentOffset 到中间位置（不带动画）
        monthScrollView.setContentOffset(CGPoint(x: screenWidth, y: 0), animated: false)

        // 计算五个月的日期范围并加载数据（当前月份的前后各两个月）
        if unifiedCalendarScope == .week {
            let currentMonthKey = getMonthKey(for: currentWeekAnchor)
            if !loadedMonthsForWeekScope.contains(currentMonthKey) {
                guard let startMonth = calendar.date(byAdding: .month, value: -2, to: currentWeekAnchor),
                      let endMonth = calendar.date(byAdding: .month, value: 2, to: currentWeekAnchor) else {
                    isResettingScrollView = false
                    return
                }

                let range = DateInterval(start: startMonth.startOfMonth, end: endMonth.endOfMonth)
                viewModel.loadEvents(forceRefresh: true, dateRange: range)
                loadedMonthsForWeekScope.insert(currentMonthKey)
            }
        } else {
            let centerMonth = currentMonthAnchor.startOfMonth
            guard let startMonth = calendar.date(byAdding: .month, value: -2, to: centerMonth),
                  let endMonth = calendar.date(byAdding: .month, value: 2, to: centerMonth) else {
                isResettingScrollView = false
                return
            }

            let fiveMonthRange = DateInterval(start: startMonth.startOfMonth, end: endMonth.endOfMonth)
            viewModel.loadEvents(forceRefresh: true, dateRange: fiveMonthRange)
        }

        isResettingScrollView = false
    }

    /// 滑动方向
    private enum Direction {
        case left   // 向左滑动（查看前一个月）
        case right  // 向右滑动（查看后一个月）
    }
}

// MARK: - Array Safe Index Extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Date Extension
private extension Date {
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }

    var endOfMonth: Date {
        let calendar = Calendar.current
        if let range = calendar.range(of: .day, in: .month, for: self),
           let start = calendar.date(from: calendar.dateComponents([.year, .month], from: self)) {
            return calendar.date(byAdding: DateComponents(day: range.count, second: -1), to: start) ?? self
        }
        return self
    }
}
