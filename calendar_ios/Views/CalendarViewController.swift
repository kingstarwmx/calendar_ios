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

        // 更新工具栏高度以适配安全区
//        inputToolbar.snp.updateConstraints { make in
//            make.height.equalTo(54 + view.safeAreaInsets.bottom)
//        }
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
        calendarView.maxHeight = 520.0
        calendarView.scope = .month
        calendarView.placeholderType = .fillSixRows
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
    }

    private func setupConstraints() {
        // 使用SnapKit设置日历视图约束
        calendarView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.equalToSuperview().offset(8)
            make.trailing.equalToSuperview().offset(-8)
            make.height.equalTo(450)
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
            make.height.equalTo(54 + SafeAreaHelper.getBottomSafeAreaInset())
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
            make.height.equalTo(54 + SafeAreaHelper.getBottomSafeAreaInset())
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
        Task { await viewModel.loadEvents(forceRefresh: true) }
    }

    func calendar(_ calendar: FSCalendar, boundingRectWillChange bounds: CGRect, animated: Bool) {
        // 处理日历大小变化
        view.layoutIfNeeded()
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
