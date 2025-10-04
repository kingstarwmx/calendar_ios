import UIKit
import Combine

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

    /// 当前显示的月份索引（相对于今天）
    private var currentMonthOffset: Int = 0

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
        // print("🔐 请求设备日历访问权限...")

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
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "设置", style: .plain, target: self, action: #selector(settingsTapped))

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
        let today = Date()

        // 创建三个 MonthPageView 和对应的 ViewModel
        for i in 0..<3 {
            // 计算月份（-1, 0, +1）
            let monthOffset = currentMonthOffset + i - 1
            let month = calendar.date(byAdding: .month, value: monthOffset, to: today)!

            // 创建 ViewModel（先不设置事件，等数据加载完成后再设置）
            let viewModel = MonthPageViewModel(month: month, selectedDate: getSelectedDateForMonth(month))

            // 创建 View
            let pageView = MonthPageView()

            // 配置 View 和 ViewModel
            pageView.configure(with: viewModel)

            // 设置回调
            pageView.onDateSelected = { [weak self] date in
                self?.handleDateSelection(date)
            }

            pageView.onEventSelected = { [weak self] event in
                self?.handleEventSelection(event)
            }

            pageView.onCalendarScopeChanged = { [weak self] scope in
                self?.handleCalendarScopeChange(scope)
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

    /// 更新三个月份页面的数据
    private func updateMonthPagesData() {
        let calendar = Calendar.current
        let today = Date()

        // 计算三个月份：前一个月、当前月、后一个月
        let months = [
            calendar.date(byAdding: .month, value: currentMonthOffset - 1, to: today)!,
            calendar.date(byAdding: .month, value: currentMonthOffset, to: today)!,
            calendar.date(byAdding: .month, value: currentMonthOffset + 1, to: today)!
        ]

        // 为每个页面更新 ViewModel
        for (index, pageView) in monthPageViews.enumerated() {
            let month = months[index]

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
        }

        // 更新月份标签
        let currentMonth = months[1]
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
        // print("📆 选中日期: \(date)")

        // 保存用户选中的日期
        saveSelectedDate(date)

        // 更新 viewModel 的选中日期（用于工具栏）
        viewModel.selectedDate = date
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
    private func handleCalendarScopeChange(_ scope: FSCalendarScope) {
        // print("📏 日历范围变化: \(scope)")
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

    /// 获取月份的 key（格式：yyyy-MM）
    /// - Parameter date: 日期
    /// - Returns: 月份 key
    private func getMonthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func bindViewModel() {
        viewModel.$events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // 刷新所有月份页面的数据
                self.updateMonthPagesData()
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
            // 滑到最左边，查看前一个月
            // print("📅 切换到前一个月")
            currentMonthOffset -= 1
            resetScrollViewPosition(direction: .left)
        } else if offsetX >= screenWidth * 2 {
            // 滑到最右边，查看后一个月
            // print("📅 切换到后一个月")
            currentMonthOffset += 1
            resetScrollViewPosition(direction: .right)
        }
    }

    /// 重置 ScrollView 位置和页面数据
    /// - Parameter direction: 滑动方向
    private func resetScrollViewPosition(direction: Direction) {
        isResettingScrollView = true

        let screenWidth = DeviceHelper.screenWidth
        let calendar = Calendar.current
        let today = Date()

        // 根据方向重新排列页面视图
        if direction == .left {
            // 向左滑动：右边视图移到左边（变成前前一个月）
            let rightView = monthPageViews.removeLast()
            monthPageViews.insert(rightView, at: 0)

            // 为新的左边页面创建新的 ViewModel
            let newMonth = calendar.date(byAdding: .month, value: currentMonthOffset - 2, to: today)!
            let newViewModel = MonthPageViewModel(month: newMonth, selectedDate: getSelectedDateForMonth(newMonth))
            rightView.configure(with: newViewModel)

            // 更新回调
            rightView.onDateSelected = { [weak self] date in
                self?.handleDateSelection(date)
            }
            rightView.onEventSelected = { [weak self] event in
                self?.handleEventSelection(event)
            }
            rightView.onCalendarScopeChanged = { [weak self] scope in
                self?.handleCalendarScopeChange(scope)
            }
            rightView.onCalendarHeightChanged = { [weak self] height in
                self?.handleCalendarHeightChange(height)
            }
        } else {
            // 向右滑动：左边视图移到右边（变成后后一个月）
            let leftView = monthPageViews.removeFirst()
            monthPageViews.append(leftView)

            // 为新的右边页面创建新的 ViewModel
            let newMonth = calendar.date(byAdding: .month, value: currentMonthOffset + 2, to: today)!
            let newViewModel = MonthPageViewModel(month: newMonth, selectedDate: getSelectedDateForMonth(newMonth))
            leftView.configure(with: newViewModel)

            // 更新回调
            leftView.onDateSelected = { [weak self] date in
                self?.handleDateSelection(date)
            }
            leftView.onEventSelected = { [weak self] event in
                self?.handleEventSelection(event)
            }
            leftView.onCalendarScopeChanged = { [weak self] scope in
                self?.handleCalendarScopeChange(scope)
            }
            leftView.onCalendarHeightChanged = { [weak self] height in
                self?.handleCalendarHeightChange(height)
            }
        }

        // 重新布局页面位置
        for (index, pageView) in monthPageViews.enumerated() {
            pageView.frame.origin.x = screenWidth * CGFloat(index)
        }

        // 更新月份数据
        updateMonthPagesData()

        // 重置 contentOffset 到中间位置（不带动画）
        monthScrollView.setContentOffset(CGPoint(x: screenWidth, y: 0), animated: false)

        // 计算五个月的日期范围并加载数据（当前月份的前后各两个月）
        guard let startMonth = calendar.date(byAdding: .month, value: currentMonthOffset - 2, to: today),
              let endMonth = calendar.date(byAdding: .month, value: currentMonthOffset + 2, to: today) else {
            isResettingScrollView = false
            return
        }

        let fiveMonthRange = DateInterval(start: startMonth.startOfMonth, end: endMonth.endOfMonth)
        viewModel.loadEvents(forceRefresh: true, dateRange: fiveMonthRange)

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
