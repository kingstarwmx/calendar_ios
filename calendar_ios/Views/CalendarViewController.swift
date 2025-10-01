import UIKit
import Combine

@MainActor
final class CalendarViewController: UIViewController {
    private let viewModel: EventViewModel
    private var cancellables: Set<AnyCancellable> = []

    private let calendarView = FSCalendar()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let monthLabel = UILabel()
    private let emptyLabel = UILabel()

    /// 输入工具栏
    private let inputToolbar = InputToolbarView()

    /// scope切换手势
    private var scopeGesture: UIPanGestureRecognizer?

    /// 日历高度约束
    private var calendarHeightConstraint: NSLayoutConstraint?

    /// 标记是否已经初始化过tableView的偏移
    private var hasInitializedTableViewOffset = false

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
        bindViewModel()
        setupKeyboardObservers()
        setupScopeGesture()

        print("🚀 CalendarViewController - 开始加载数据")
        print("📍 当前选中日期: \(viewModel.selectedDate)")

        Task {
            print("🔐 请求设备日历访问权限...")
            await viewModel.requestDeviceCalendarAccess()

            print("📊 开始加载事件...")
            await viewModel.loadEvents(forceRefresh: true)

            print("✅ 数据加载完成")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // 初次布局后，调整日程列表位置
        if !hasInitializedTableViewOffset && calendarView.frame.size.height > 0 {
            hasInitializedTableViewOffset = true
            updateTableViewOffset()
        }
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        navigationItem.titleView = monthLabel
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "设置", style: .plain, target: self, action: #selector(settingsTapped))

        monthLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        monthLabel.textColor = .label

        calendarView.headerHeight = 0
        calendarView.weekdayHeight = 32
        calendarView.scope = .month
        calendarView.placeholderType = .fillSixRows
        calendarView.clipsToBounds = false  // 允许tableView覆盖到日历区域
        calendarView.appearance.weekdayTextColor = .secondaryLabel
        calendarView.appearance.titleFont = UIFont.systemFont(ofSize: 16, weight: .medium)
        calendarView.appearance.subtitleFont = UIFont.systemFont(ofSize: 12)
        calendarView.appearance.selectionColor = .systemBlue
        calendarView.appearance.todayColor = .systemRed
        calendarView.appearance.titleTodayColor = .white
        calendarView.appearance.eventDefaultColor = .systemBlue
        calendarView.appearance.eventSelectionColor = .systemBlue

        // 设置FSCalendar的delegate和dataSource
        calendarView.delegate = self
        calendarView.dataSource = self

        tableView.register(EventListCell.self, forCellReuseIdentifier: EventListCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.tableFooterView = UIView()

        emptyLabel.text = "暂无事件"
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        emptyLabel.isHidden = true

        view.addSubview(calendarView)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        view.addSubview(inputToolbar)

        setupConstraints()
        setupInputToolbar()

        calendarView.select(viewModel.selectedDate)
        calendarView.setCurrentPage(viewModel.selectedDate, animated: false)
        updateMonthLabel(for: viewModel.selectedDate)


        let fullCalendarH = DeviceHelper.screenHeight - DeviceHelper.navigationBarTotalHeight() - DeviceHelper.getBottomSafeAreaInset() - 54.0;  // 设置最大高度，允许展开到更多行
        let numberOfRows = calendarView.numberOfRowsForCurrentMonth()
        if (numberOfRows==5) {
            calendarView.maxHeight = fullCalendarH * 1.2
        }else {
            calendarView.maxHeight = fullCalendarH
        }

    }

    private func setupConstraints() {
        // 使用SnapKit设置日历视图约束
        calendarView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.equalToSuperview().offset(8)
            make.trailing.equalToSuperview().offset(-8)
            // 初始高度设置为month模式高度
            calendarHeightConstraint = make.height.equalTo(350).constraint.layoutConstraints.first
        }

        // 设置表格视图约束
        tableView.snp.makeConstraints { make in
            make.top.equalTo(calendarView.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(inputToolbar.snp.top)
        }

        // 设置空标签约束
        emptyLabel.snp.makeConstraints { make in
            make.center.equalTo(tableView)
        }
    }

    private func layoutViews() {
        // 不再需要手动布局，使用SnapKit约束
    }

    private func bindViewModel() {
        viewModel.$events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.calendarView.reloadData()
                self?.tableView.reloadData()
                self?.emptyLabel.isHidden = !(self?.viewModel.getEvents(for: self?.viewModel.selectedDate ?? Date()).isEmpty ?? true)
            }
            .store(in: &cancellables)

        viewModel.$selectedDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                guard let self else { return }
                self.calendarView.select(date, scrollToDate: true)
                self.updateMonthLabel(for: date)
                self.tableView.reloadData()
                self.emptyLabel.isHidden = !self.viewModel.getEvents(for: date).isEmpty
                // 更新工具栏提示语
                self.inputToolbar.selectedDate = date
            }
            .store(in: &cancellables)

        viewModel.$viewMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.apply(viewMode: mode)
            }
            .store(in: &cancellables)
    }

    private func updateMonthLabel(for date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月"
        monthLabel.text = formatter.string(from: date)

        // 更新日程列表位置以覆盖空白行
        updateTableViewOffset()
    }

    /// 根据当月实际行数调整日程列表位置
    /// 当月只有4-5行时，向上移动日程列表以覆盖空白的第6行
    private func updateTableViewOffset() {
        let numberOfRows = calendarView.numberOfRowsForCurrentMonth()

        // 计算单行高度：(屏幕宽度 - 左右边距) / 7
        let calendarWidth = DeviceHelper.screenWidth - 16  // 左右各8pt边距
        let rowHeight = calendarWidth / 7.0

        // 计算需要向上偏移的距离：(6 - 实际行数) * 单行高度
        let emptyRows = 6 - numberOfRows
        let offsetDistance = CGFloat(emptyRows) * rowHeight

        // 更新tableView的top约束，向上偏移以覆盖空白行
        // offset从8变为 8 - offsetDistance
        tableView.snp.updateConstraints { make in
            make.top.equalTo(calendarView.snp.bottom).offset(8 - offsetDistance)
        }

        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }

        print("📏 当月行数: \(numberOfRows), 向上偏移: \(offsetDistance)pt")
    }

    private func apply(viewMode: CalendarViewMode) {
        // View mode functionality removed
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

    /// 设置scope切换手势
    private func setupScopeGesture() {
        let panGesture = UIPanGestureRecognizer(target: calendarView, action: #selector(calendarView.handleScopeGesture(_:)))
        panGesture.delegate = self
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 2
        view.addGestureRecognizer(panGesture)
        self.scopeGesture = panGesture

        // tableView的滑动手势需要等待scope手势失败
        tableView.panGestureRecognizer.require(toFail: panGesture)
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
    func calendar(_ calendar: FSCalendar, numberOfEventsFor date: Date) -> Int {
        let count = viewModel.getEvents(for: date).count
        // 最多显示3个点
        return min(count, 3)
    }

    func calendar(_ calendar: FSCalendar, didSelect date: Date, at monthPosition: FSCalendarMonthPosition) {
        print("📆 选中日期: \(date)")

        viewModel.selectedDate = date

        // 获取并打印选中日期的事件
        let events = viewModel.getEvents(for: date)
        print("   当天事件数: \(events.count)")
        for event in events {
            print("   - \(event.title) (\(event.isAllDay ? "全天" : "定时"))")
        }
    }

    func calendarCurrentPageDidChange(_ calendar: FSCalendar) {
        viewModel.setCurrentMonth(calendar.currentPage)
        updateMonthLabel(for: calendar.currentPage)
        print("📅 切换到月份: \(calendar.currentPage)")

        Task {
            await viewModel.loadEvents(forceRefresh: true)
        }
    }

    func calendar(_ calendar: FSCalendar, boundingRectWillChange bounds: CGRect, animated: Bool) {
        // 日历大小改变时更新约束
        calendarHeightConstraint?.constant = bounds.height
        view.layoutIfNeeded()
    }
}

// MARK: - UIGestureRecognizerDelegate
extension CalendarViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 判断是否应该开始scope手势
        guard let scopeGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }

        // tableView在顶部时才允许开始手势
        let shouldBegin = tableView.contentOffset.y <= -tableView.contentInset.top

        if shouldBegin {
            let velocity = scopeGesture.velocity(in: view)
            switch calendarView.scope {
            case .month:
                // month模式下
                if velocity.y < 0 {
                    // 向上滑动，切换到week模式
                    return true
                }
                if velocity.y > 0 {
                    // 向下滑动，检查是否已达到最大高度
                    let currentHeight = calendarView.bounds.height
                    return calendarView.maxHeight > currentHeight + 1.0
                }
                return false

            case .week:
                // week模式下，只允许向下滑动切换到month模式
                return velocity.y > 0

            case .maxHeight:
                // maxHeight模式下，只允许向上滑动
                return velocity.y < 0

            @unknown default:
                return false
            }
        }

        return shouldBegin
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 允许和tableView的手势同时识别
        return gestureRecognizer == scopeGesture && otherGestureRecognizer == tableView.panGestureRecognizer
    }
}

extension CalendarViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = viewModel.getEvents(for: viewModel.selectedDate).count
        emptyLabel.isHidden = count != 0
        return count
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
