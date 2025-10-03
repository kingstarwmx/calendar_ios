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
        print("🔐 请求设备日历访问权限...")

        viewModel.requestDeviceCalendarAccess {
            print("✅ 数据加载完成")
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

        // 创建三个 MonthPageView
        for i in 0..<3 {
            let pageView = MonthPageView()
            pageView.calendarView.delegate = self
            pageView.calendarView.dataSource = self
            pageView.tableView.delegate = self
            pageView.tableView.dataSource = self
            pageView.tableView.register(EventListCell.self, forCellReuseIdentifier: EventListCell.reuseIdentifier)

            // 注册自定义 cell
            pageView.calendarView.register(CustomCalendarCell.self, forCellReuseIdentifier: "CustomCell")

            // 设置 maxHeight
            

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

        // 配置初始月份数据
        updateMonthPagesData()
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

        for (index, pageView) in monthPageViews.enumerated() {
            let month = months[index]
            let events = viewModel.events.filter { event in
                calendar.isDate(event.startDate, equalTo: month, toGranularity: .month)
            }
            pageView.configure(month: month, events: events)
        }

        // 更新月份标签
        updateMonthLabel(for: months[1])
    }

    private func bindViewModel() {
        viewModel.$events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // 刷新所有月份页面的数据
                self.updateMonthPagesData()
                print("🔄 日历数据已刷新")
            }
            .store(in: &cancellables)

        viewModel.$selectedDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                guard let self = self else { return }

                // 选中所有日历中的对应日期
                for pageView in self.monthPageViews {
                    pageView.calendarView.select(date, scrollToDate: false)
                }

                self.updateMonthLabel(for: date)

                // 更新工具栏提示语
                self.inputToolbar.selectedDate = date

                // 刷新 tableView
                self.getCurrentMonthPageView()?.tableView.reloadData()
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
            Task { await self.viewModel.addEvent(event, syncToDevice: self.viewModel.deviceCalendarEnabled) }
        }
        let nav = UINavigationController(rootViewController: controller)
        present(nav, animated: true)
    }

    @objc private func settingsTapped() {
        let alert = UIAlertController(title: "设备日历", message: "是否同步设备日历事件?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "不同步", style: .default, handler: { [weak self] _ in
            Task { await self?.viewModel.setDeviceSync(enabled: false) }
        }))
        alert.addAction(UIAlertAction(title: "同步", style: .default, handler: { [weak self] _ in
            Task { await self?.viewModel.requestDeviceCalendarAccess() }
        }))
        present(alert, animated: true)
    }
}

@MainActor
extension CalendarViewController: FSCalendarDataSource, FSCalendarDelegate, FSCalendarDelegateAppearance {
    func calendar(_ calendar: FSCalendar, cellFor date: Date, at position: FSCalendarMonthPosition) -> FSCalendarCell {
        let cell = calendar.dequeueReusableCell(withIdentifier: "CustomCell", for: date, at: position) as! CustomCalendarCell

        let events = viewModel.getEvents(for: date)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate)
        let isToday = Calendar.current.isDateInToday(date)
        let isPlaceholder = position != .current

        cell.configure(with: date, events: events, isSelected: isSelected, isToday: isToday, isPlaceholder: isPlaceholder)

        return cell
    }

    func calendar(_ calendar: FSCalendar, numberOfEventsFor date: Date) -> Int {
        // 返回 0，因为我们使用自定义 cell 来显示事件
        return 0
    }

    func calendar(_ calendar: FSCalendar, didSelect date: Date, at monthPosition: FSCalendarMonthPosition) {
        print("📆 选中日期: \(date)")

        viewModel.selectedDate = date

        // 刷新所有日历以更新选中状态
        for pageView in monthPageViews {
            pageView.calendarView.reloadData()
        }

        // 获取并打印选中日期的事件
        let events = viewModel.getEvents(for: date)
        print("   当天事件数: \(events.count)")
        for event in events {
            print("   - \(event.title) (\(event.isAllDay ? "全天" : "定时"))")
        }
    }

    func calendar(_ calendar: FSCalendar, boundingRectWillChange bounds: CGRect, animated: Bool) {
        // 找到对应的 pageView 并更新其日历高度
        if let pageView = monthPageViews.first(where: { $0.calendarView == calendar }) {
            pageView.updateCalendarHeight(bounds.height)

            if animated {
                UIView.animate(withDuration: 0.3) {
                    pageView.layoutIfNeeded()
                }
            }
        }
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
            print("📅 切换到前一个月")
            currentMonthOffset -= 1
            resetScrollViewPosition(direction: .left)
        } else if offsetX >= screenWidth * 2 {
            // 滑到最右边，查看后一个月
            print("📅 切换到后一个月")
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
        } else {
            // 向右滑动：左边视图移到右边（变成后后一个月）
            let leftView = monthPageViews.removeFirst()
            monthPageViews.append(leftView)
        }

        // 重新布局页面位置
        for (index, pageView) in monthPageViews.enumerated() {
            pageView.frame.origin.x = screenWidth * CGFloat(index)
        }

        // 更新月份数据
        updateMonthPagesData()

        // 重置 contentOffset 到中间位置（不带动画）
        monthScrollView.setContentOffset(CGPoint(x: screenWidth, y: 0), animated: false)

        // 加载新月份的数据
        viewModel.loadEvents(forceRefresh: true)

        isResettingScrollView = false
    }

    /// 滑动方向
    private enum Direction {
        case left   // 向左滑动（查看前一个月）
        case right  // 向右滑动（查看后一个月）
    }
}

extension CalendarViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.getEvents(for: viewModel.selectedDate).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: EventListCell.reuseIdentifier, for: indexPath) as? EventListCell else {
            return UITableViewCell()
        }
        let events = viewModel.getEvents(for: viewModel.selectedDate)
        cell.configure(with: events[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Array Safe Index Extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
