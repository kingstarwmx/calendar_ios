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

    init(viewModel: EventViewModel? = nil) {
        self.viewModel = viewModel ?? EventViewModel()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        bindViewModel()
        Task {
            await viewModel.requestDeviceCalendarAccess()
            await viewModel.loadEvents(forceRefresh: true)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
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
        
        layoutViews()

        calendarView.select(viewModel.selectedDate)
        calendarView.setCurrentPage(viewModel.selectedDate, animated: false)
        updateMonthLabel(for: viewModel.selectedDate)
        
        
    }

    private func layoutViews() {
        let safeArea = view.safeAreaLayoutGuide.layoutFrame
        let margin: CGFloat = 16

        // Calendar view
        let calendarHeight: CGFloat = 600
        calendarView.frame = CGRect(
            x: margin,
            y: safeArea.minY + 8,
            width: view.frame.width - margin * 2,
            height: calendarHeight
        )

        // Table view
        tableView.frame = CGRect(
            x: 0,
            y: calendarView.frame.maxY + 8,
            width: view.frame.width,
            height: safeArea.maxY - (calendarView.frame.maxY + 8)
        )

        // Empty label
        emptyLabel.sizeToFit()
        emptyLabel.center = tableView.center
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

//extension CalendarViewController: FSCalendarDataSource, FSCalendarDelegate, FSCalendarDelegateAppearance {
//    func calendar(_ calendar: FSCalendar, numberOfEventsFor date: Date) -> Int {
//        let count = viewModel.getEvents(for: date).count
//        if viewModel.viewMode == .expanded {
//            return min(count, 3)
//        }
//        return min(count, 1)
//    }
//
//    func calendar(_ calendar: FSCalendar, didSelect date: Date, at monthPosition: FSCalendarMonthPosition) {
//        viewModel.selectedDate = date
//    }
//
//    func calendarCurrentPageDidChange(_ calendar: FSCalendar) {
//        viewModel.setCurrentMonth(calendar.currentPage)
//        updateMonthLabel(for: calendar.currentPage)
//        Task { await viewModel.loadEvents(forceRefresh: true) }
//    }
//
//    func calendar(_ calendar: FSCalendar, boundingRectWillChange bounds: CGRect, animated: Bool) {
//        calendarHeightConstraint?.update(offset: bounds.height)
//        view.layoutIfNeeded()
//    }
//}

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
