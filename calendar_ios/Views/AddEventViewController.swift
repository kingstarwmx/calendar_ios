import UIKit
import SnapKit
let iconSize: CGFloat = 23
/// 新建事件页面，参考 Flutter 端 `add_event_screen.dart` 的布局和交互
final class AddEventViewController: UIViewController {
    var onSave: ((Event) -> Void)?

    private enum ActivePicker {
        case none
        case start
        case end
    }

    private struct ReminderOption: Equatable {
        let title: String
        let offset: TimeInterval?
    }

    private static func buildReminderOptions(_ locale: Locale) -> [ReminderOption] {
        [
            ReminderOption(title: "不提醒", offset: nil),
            ReminderOption(title: "开始时", offset: 0),
            ReminderOption(title: "5分钟前", offset: 5 * 60),
            ReminderOption(title: "10分钟前", offset: 10 * 60),
            ReminderOption(title: "15分钟前", offset: 15 * 60),
            ReminderOption(title: "30分钟前", offset: 30 * 60),
            ReminderOption(title: "1小时前", offset: 60 * 60),
            ReminderOption(title: "2小时前", offset: 2 * 60 * 60),
            ReminderOption(title: "1天前", offset: 24 * 60 * 60)
        ]
    }

    // MARK: - UI Components

    private let scrollView = FormScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let formStack = UIStackView()

    private let titleField = UITextField()

    private let timeSection = UIView()
    private let timeRow = UIStackView()
    private let clockIconView = UIImageView(image: UIImage(systemName: "clock"))
    private let startDateButton = DateSelectionButton()
    private let endDateButton = DateSelectionButton()
    private let arrowView = UIImageView(image: UIImage(systemName: "arrow.forward"))
    private let allDayButton = UIButton(type: .system)

    private let pickerStack = UIStackView()
    private let startPickerContainer = UIView()
    private let endPickerContainer = UIView()
    private var startPickerHeightConstraint: Constraint?
    private var endPickerHeightConstraint: Constraint?
    private let pickerHeight: CGFloat = 216
    private let timeRowHeight: CGFloat = 84
    private var timeRowHeightConstraint: Constraint?
    private let startDatePicker = UIDatePicker()
    private let endDatePicker = UIDatePicker()

    private let repeatRow = OptionRowView(iconName: "repeat", placeholder: "无重复")
    private let reminderRow = OptionRowView(iconName: "bell", placeholder: "30分钟前")
    private let locationRow = IconTextFieldRow(iconName: "mappin.and.ellipse", placeholder: "位置")
    private let urlRow = IconTextFieldRow(iconName: "link", placeholder: "URL")
    private let notesRow = NotesInputRow(iconName: "text.alignleft", placeholder: "备注")

    // MARK: - State

    private var activePicker: ActivePicker = .none
    private var startDate = Date()
    private var endDate = Date().addingTimeInterval(3600)
    private var isAllDay = false
    private var cachedTimedStartDate: Date?
    private var cachedTimedEndDate: Date?
    private var selectedRepeatRule = RepeatRule.none()
    private var selectedReminder = ReminderOption(title: "", offset: 30 * 60)

    private let baseLanguageIdentifier: String = Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier

    private lazy var displayLocale: Locale = Locale(identifier: baseLanguageIdentifier)

    private lazy var pickerLocale: Locale = {
        if #available(iOS 16, *) {
            var components = Locale.Components(locale: displayLocale)
            let autoComponents = Locale.Components(locale: Locale.autoupdatingCurrent)
            components.hourCycle = autoComponents.hourCycle
            components.calendar = autoComponents.calendar
            if components.region == nil {
                components.region = autoComponents.region
            }
            return Locale(components: components)
        } else {
            return Locale.autoupdatingCurrent
        }
    }()

    private let timeLocale: Locale = Locale.autoupdatingCurrent
    private let timeCalendar: Calendar = .autoupdatingCurrent
    private lazy var monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        let format = DateFormatter.dateFormat(fromTemplate: "MMM d", options: 0, locale: displayLocale) ?? "MMM d"
        formatter.dateFormat = format
        return formatter
    }()

    private lazy var weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        let format = DateFormatter.dateFormat(fromTemplate: "EEE", options: 0, locale: displayLocale) ?? "EEE"
        formatter.dateFormat = format
        return formatter
    }()

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = pickerLocale
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: pickerLocale) ?? ""
        if pattern.contains("a") {
            formatter.setLocalizedDateFormatFromTemplate("jm")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("Hm")
        }
        return formatter
    }()

    private lazy var reminderOptions: [ReminderOption] = {
        Self.buildReminderOptions(displayLocale)
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureViewHierarchy()
        configurePickers()
        configureActions()
        if let defaultReminder = reminderOptions.first(where: { $0.offset == 30 * 60 }) {
            selectedReminder = defaultReminder
        } else if let first = reminderOptions.first {
            selectedReminder = first
        }
        updateAllDayState(animated: false)
        updateDateDisplays()
        updateRepeatDisplay()
        updateReminderDisplay()
    }

    // MARK: - Setup

    private func configureNavigation() {
        title = "新建日程"
        view.backgroundColor = .systemGroupedBackground

        let cancelItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelTapped))
        let saveItem = UIBarButtonItem(title: "保存", style: .done, target: self, action: #selector(saveTapped))
        navigationItem.leftBarButtonItem = cancelItem
        navigationItem.rightBarButtonItem = saveItem
    }

    private func configureViewHierarchy() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive

        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 24, left: 0, bottom: 40, right: 0)

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)

        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.snp.width)
        }

        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        configureTitleField()
        configureFormStack()
        configureTimeSection()
        configureOptionRows()
    }

    private func configureTitleField() {
        titleField.placeholder = "标题"
        titleField.font = UIFont.systemFont(ofSize: 28, weight: .semibold)
        titleField.textColor = UIColor.label
        titleField.borderStyle = .none
        titleField.clearButtonMode = .whileEditing
        titleField.returnKeyType = .done
        titleField.delegate = self

        let titleContainer = UIView()
        titleContainer.addSubview(titleField)
        titleField.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20))
        }

        stackView.addArrangedSubview(titleContainer)

        let divider = UIView()
        divider.backgroundColor = UIColor.separator
        divider.snp.makeConstraints { make in
            make.height.equalTo(1.0 / UIScreen.main.scale)
        }
        stackView.addArrangedSubview(divider)
    }

    private func configureFormStack() {
        formStack.axis = .vertical
        formStack.spacing = 0
        formStack.distribution = .fill
        formStack.alignment = .fill
        formStack.isLayoutMarginsRelativeArrangement = false
        stackView.addArrangedSubview(formStack)
    }

    private func configureTimeSection() {
        startDateButton.addTarget(self, action: #selector(startButtonTapped), for: .touchUpInside)
        endDateButton.addTarget(self, action: #selector(endButtonTapped), for: .touchUpInside)

        clockIconView.tintColor = .gray
        clockIconView.contentMode = .scaleAspectFit

        arrowView.tintColor = .gray
        arrowView.contentMode = .scaleAspectFit

        allDayButton.setTitle("全天", for: .normal)
        allDayButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        allDayButton.layer.cornerRadius = 16
        allDayButton.layer.borderWidth = 1
        allDayButton.layer.borderColor = UIColor.separator.cgColor
        allDayButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)

        timeRow.axis = .horizontal
        timeRow.alignment = .center
        timeRow.spacing = 12

        timeRow.addArrangedSubview(clockIconView)
        clockIconView.snp.makeConstraints { make in
            make.width.height.equalTo(iconSize)
        }

        timeRow.addArrangedSubview(startDateButton)
        timeRow.addArrangedSubview(arrowView)
        arrowView.snp.makeConstraints { make in
            make.width.height.equalTo(iconSize)
        }
        timeRow.addArrangedSubview(endDateButton)
        timeRow.addArrangedSubview(allDayButton)

        startDateButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        endDateButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        startDateButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        endDateButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        startDateButton.snp.makeConstraints { make in
            make.width.equalTo(endDateButton.snp.width)
        }

        allDayButton.addTarget(self, action: #selector(allDayTapped), for: .touchUpInside)

        timeSection.addSubview(timeRow)
        timeRow.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            timeRowHeightConstraint = make.height.equalTo(timeRowHeight).constraint
        }

        pickerStack.axis = .vertical
        pickerStack.spacing = 12
        pickerStack.alignment = .fill
        pickerStack.distribution = .fill
        pickerStack.isHidden = true
        pickerStack.alpha = 0
        timeSection.addSubview(pickerStack)
        pickerStack.snp.makeConstraints { make in
            make.top.equalTo(timeRow.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview()
        }

        configurePickerContainer(container: startPickerContainer, picker: startDatePicker)
        configurePickerContainer(container: endPickerContainer, picker: endDatePicker)

        addFormRow(timeSection)
    }

    private func configurePickerContainer(container: UIView, picker: UIDatePicker) {
        container.backgroundColor = UIColor.secondarySystemBackground
        container.layer.cornerRadius = 12
        container.layer.masksToBounds = true
        container.alpha = 0
        container.isHidden = true

        picker.locale = pickerLocale
        picker.calendar = timeCalendar
        picker.minuteInterval = 1
        picker.preferredDatePickerStyle = .wheels
        picker.addTarget(self, action: #selector(datePickerChanged(_:)), for: .valueChanged)

        container.addSubview(picker)
        picker.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        picker.setContentCompressionResistancePriority(.required, for: .vertical)

        pickerStack.addArrangedSubview(container)
        if container === startPickerContainer {
            container.snp.makeConstraints { make in
                startPickerHeightConstraint = make.height.equalTo(0).constraint
            }
        } else if container === endPickerContainer {
            container.snp.makeConstraints { make in
                endPickerHeightConstraint = make.height.equalTo(0).constraint
            }
        }
    }

    private func configureOptionRows() {
        if #available(iOS 14.0, *) {
            repeatRow.menuProvider = { [weak self] in
                self?.makeRepeatMenu() ?? UIMenu(title: "", children: [])
            }
        } else {
            repeatRow.menuProvider = nil
        }
        repeatRow.addTarget(self, action: #selector(repeatTapped), for: .touchUpInside)
//        reminderRow.addTarget(self, action: #selector(reminderTapped), for: .touchUpInside)
        

        repeatRow.accessoryImage = UIImage(systemName: "chevron.up.chevron.down")

        addFormRow(repeatRow, horizontalInset: 0)
        addFormRow(reminderRow, horizontalInset: 0)

        addFormRow(locationRow)
        addFormRow(urlRow)
        addFormRow(notesRow, includeBottomSeparator: true)

        let rowHeight: CGFloat = 60
        repeatRow.snp.makeConstraints { make in
            make.height.equalTo(rowHeight)
        }

        reminderRow.snp.makeConstraints { make in
            make.height.equalTo(rowHeight)
        }

        locationRow.snp.makeConstraints { make in
            make.height.equalTo(rowHeight)
        }

        urlRow.snp.makeConstraints { make in
            make.height.equalTo(rowHeight)
        }

        notesRow.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(120)
        }

        locationRow.textField.delegate = self
        urlRow.textField.delegate = self
        notesRow.textView.delegate = self
    }

    private func addFormRow(
        _ row: UIView,
        includeTopSeparator: Bool = false,
        includeBottomSeparator: Bool = true,
        horizontalInset: CGFloat = 20
    ) {
        let container = FormRowContainer(
            content: row,
            showTopSeparator: includeTopSeparator,
            showBottomSeparator: includeBottomSeparator,
            horizontalInset: horizontalInset
        )
        formStack.addArrangedSubview(container)
    }

    private func configurePickers() {
        startDatePicker.datePickerMode = .dateAndTime
        endDatePicker.datePickerMode = .dateAndTime
        startDatePicker.date = startDate
        endDatePicker.date = endDate
    }

    private func configureActions() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        view.endEditing(true)

        guard let titleText = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !titleText.isEmpty else {
            showAlert(message: "请输入事件标题")
            return
        }

        adjustDatesIfNeeded()

        let calendar = Calendar.current
        if isAllDay {
            startDate = calendar.startOfDay(for: startDate)
            endDate = calendar.startOfDay(for: endDate)
        }

        let reminders = selectedReminder.offset.flatMap { offset -> [Date] in
            let reminderDate = startDate.addingTimeInterval(-offset)
            return [reminderDate]
        } ?? []

        let locationText = locationRow.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let urlText = urlRow.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionText = notesRow.textView.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let event = Event(
            id: UUID().uuidString,
            title: titleText,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: locationText,
            calendarId: "local",
            description: descriptionText.isEmpty ? nil : descriptionText,
            customColor: UIColor.systemBlue,
            recurrenceRule: recurrenceString(for: selectedRepeatRule),
            reminders: reminders,
            url: urlText?.isEmpty == false ? urlText : nil,
            calendarName: "本地日历",
            isFromDeviceCalendar: false,
            deviceEventId: nil
        )

        onSave?(event)
        dismiss(animated: true)
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
//        view.endEditing(true)
//        dismissPickers()
    }

    @objc private func startButtonTapped() {
        togglePicker(.start)
    }

    @objc private func endButtonTapped() {
        togglePicker(.end)
    }

    @objc private func allDayTapped() {
        isAllDay.toggle()
        updateAllDayState(animated: true)
    }

    @objc private func repeatTapped() {
        view.endEditing(true)
        dismissPickers()
        if #available(iOS 14.0, *) {
            repeatRow.showMenu()
        } else {
            presentLegacyRepeatSheet()
        }
    }

    @objc private func reminderTapped() {
        view.endEditing(true)
        dismissPickers()

        let alert = UIAlertController(title: "提醒", message: nil, preferredStyle: .actionSheet)

        reminderOptions.forEach { option in
            var title = option.title
            if option == selectedReminder {
                title = "✓ " + title
            }
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self else { return }
                self.selectedReminder = option
                self.updateReminderDisplay()
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = reminderRow
            popover.sourceRect = reminderRow.bounds
        }

        present(alert, animated: true)
    }

    @available(iOS 14.0, *)
    private func makeRepeatMenu() -> UIMenu {
        let options: [(String, RepeatRule)] = [
            ("不重复", .none()),
            ("每天", RepeatRule(frequency: .daily)),
            ("每周", RepeatRule(frequency: .weekly)),
            ("每两周", RepeatRule(frequency: .weekly, interval: 2)),
            ("每月", RepeatRule(frequency: .monthly)),
            ("每年", RepeatRule(frequency: .yearly))
        ]

        let actions = options.map { option -> UIAction in
            let title = option.0
            let rule = option.1
            let action = UIAction(title: title, image: nil, identifier: nil) { [weak self] _ in
                guard let self else { return }
                self.selectedRepeatRule = rule
                self.updateRepeatDisplay()
            }
            if #available(iOS 15.0, *) {
                action.state = rule == selectedRepeatRule ? .on : .off
            }
            return action
        }

        let customAction = UIAction(title: "自定义…", image: nil, identifier: nil) { [weak self] _ in
            self?.presentCustomRepeatPlaceholder()
        }

        var children: [UIMenuElement] = actions
        children.append(UIMenu(options: .displayInline, children: [customAction]))
        return UIMenu(title: "", children: children)
    }

    private func presentLegacyRepeatSheet() {
        let options: [(String, RepeatRule)] = [
            ("不重复", .none()),
            ("每天", RepeatRule(frequency: .daily)),
            ("每周", RepeatRule(frequency: .weekly)),
            ("每两周", RepeatRule(frequency: .weekly, interval: 2)),
            ("每月", RepeatRule(frequency: .monthly)),
            ("每年", RepeatRule(frequency: .yearly))
        ]

        let alert = UIAlertController(title: "重复", message: nil, preferredStyle: .actionSheet)
        options.forEach { option in
            var title = option.0
            if option.1 == selectedRepeatRule {
                title = "✓ " + title
            }
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self else { return }
                self.selectedRepeatRule = option.1
                self.updateRepeatDisplay()
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "自定义…", style: .default) { [weak self] _ in
            self?.presentCustomRepeatPlaceholder()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = repeatRow
            popover.sourceRect = repeatRow.bounds
        }

        present(alert, animated: true)
    }

    @objc private func datePickerChanged(_ picker: UIDatePicker) {
        if picker === startDatePicker {
            handleStartDateChange(picker.date)
        } else {
            handleEndDateChange(picker.date)
        }
    }

    // MARK: - State Helpers

    private func handleStartDateChange(_ newDate: Date) {
        if isAllDay {
            let calendar = Calendar.current
            startDate = calendar.startOfDay(for: newDate)
            if endDate <= startDate {
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(24 * 60 * 60)
                endDatePicker.date = endDate
            }
        } else {
            startDate = newDate
            cachedTimedStartDate = startDate
            if endDate <= startDate {
                endDate = startDate.addingTimeInterval(3600)
                cachedTimedEndDate = endDate
                endDatePicker.date = endDate
            }
        }
        updateDateDisplays()
    }

    private func handleEndDateChange(_ newDate: Date) {
        if isAllDay {
            let calendar = Calendar.current
            endDate = calendar.startOfDay(for: newDate)
            if endDate <= startDate {
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(24 * 60 * 60)
                endDatePicker.date = endDate
            }
        } else {
            endDate = newDate
            cachedTimedEndDate = endDate
            if endDate <= startDate {
                startDate = endDate.addingTimeInterval(-3600)
                cachedTimedStartDate = startDate
                startDatePicker.date = startDate
            }
        }
        updateDateDisplays()
    }

    private func togglePicker(_ target: ActivePicker) {
        view.endEditing(true)
        let previous = activePicker
        activePicker = (activePicker == target) ? .none : target
        updatePickerVisibility(from: previous, animated: true)
    }

    private func dismissPickers() {
        guard activePicker != .none else { return }
        let previous = activePicker
        activePicker = .none
        updatePickerVisibility(from: previous, animated: true)
    }

    private func updatePickerVisibility(from previous: ActivePicker, animated: Bool) {
        let startActive = activePicker == .start
        let endActive = activePicker == .end
        let shouldShow = startActive || endActive

        [pickerStack, startPickerContainer, endPickerContainer].forEach { $0.layer.removeAllAnimations() }

        startDateButton.isHighlightedState = startActive
        endDateButton.isHighlightedState = endActive

        let duration: TimeInterval = animated ? 0.25 : 0

        view.layoutIfNeeded()

        if shouldShow {
            if pickerStack.isHidden {
                pickerStack.alpha = 0
                pickerStack.isHidden = false
            }

            let comingFromHidden = previous == .none
            let targetStartAlpha: CGFloat = startActive ? 1 : 0
            let targetEndAlpha: CGFloat = endActive ? 1 : 0

            if comingFromHidden {
                if startActive {
                    startPickerHeightConstraint?.update(offset: pickerHeight)
                    endPickerHeightConstraint?.update(offset: 0)
                    startPickerContainer.alpha = 0
                    startPickerContainer.isHidden = false
                    endPickerContainer.isHidden = true
                } else if endActive {
                    endPickerHeightConstraint?.update(offset: pickerHeight)
                    startPickerHeightConstraint?.update(offset: 0)
                    endPickerContainer.alpha = 0
                    endPickerContainer.isHidden = false
                    startPickerContainer.isHidden = true
                }

                let animations = {
                    self.pickerStack.alpha = 1
                    self.startPickerContainer.alpha = targetStartAlpha
                    self.endPickerContainer.alpha = targetEndAlpha
                    self.view.layoutIfNeeded()
                }

                if duration > 0 {
                    UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut], animations: animations)
                } else {
                    animations()
                }
            } else {
                pickerStack.alpha = 1
                startPickerHeightConstraint?.update(offset: startActive ? pickerHeight : 0)
                endPickerHeightConstraint?.update(offset: endActive ? pickerHeight : 0)
                startPickerContainer.alpha = targetStartAlpha
                endPickerContainer.alpha = targetEndAlpha
                startPickerContainer.isHidden = !startActive
                endPickerContainer.isHidden = !endActive
            }
        } else {
            pickerStack.alpha = 0
            startPickerContainer.alpha = 0
            endPickerContainer.alpha = 0

            startPickerHeightConstraint?.update(offset: 0)
            endPickerHeightConstraint?.update(offset: 0)

            pickerStack.isHidden = true
            startPickerContainer.isHidden = true
            endPickerContainer.isHidden = true

            if duration > 0 {
                UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut]) {
                    self.view.layoutIfNeeded()
                }
            } else {
                view.layoutIfNeeded()
            }
        }
    }

    private func updateAllDayState(animated: Bool) {
        let calendar = Calendar.current

        if isAllDay {
            cachedTimedStartDate = cachedTimedStartDate ?? startDate
            cachedTimedEndDate = cachedTimedEndDate ?? endDate

            startDate = calendar.startOfDay(for: startDate)
            endDate = calendar.startOfDay(for: endDate)
            if endDate <= startDate {
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(24 * 60 * 60)
            }
        } else {
            if let cachedStart = cachedTimedStartDate {
                startDate = cachedStart
            }
            if let cachedEnd = cachedTimedEndDate, cachedEnd > startDate {
                endDate = cachedEnd
            } else {
                endDate = startDate.addingTimeInterval(3600)
            }
        }

        startDatePicker.datePickerMode = isAllDay ? .date : .dateAndTime
        endDatePicker.datePickerMode = isAllDay ? .date : .dateAndTime
        startDatePicker.date = startDate
        endDatePicker.date = endDate

        let updateBlock = {
            self.allDayButton.backgroundColor = self.isAllDay ? UIColor.systemBlue : UIColor.clear
            self.allDayButton.layer.borderColor = (self.isAllDay ? UIColor.systemBlue : UIColor.separator).cgColor
            self.allDayButton.setTitleColor(self.isAllDay ? UIColor.white : UIColor.label, for: .normal)
            self.startDateButton.showsTime = !self.isAllDay
            self.endDateButton.showsTime = !self.isAllDay
            self.updateDateDisplays()
        }

        if animated {
            UIView.animate(withDuration: 0.2, animations: updateBlock)
        } else {
            updateBlock()
        }

        dismissPickers()
    }

    private func updateDateDisplays() {
        let startDateText = formattedDateString(from: startDate)
        let endDateText = formattedDateString(from: endDate)
        let startTimeText = timeFormatter.string(from: startDate)
        let endTimeText = timeFormatter.string(from: endDate)

        startDateButton.update(date: startDateText, time: startTimeText)
        endDateButton.update(date: endDateText, time: endTimeText)
        startDateButton.showsTime = !isAllDay
        endDateButton.showsTime = !isAllDay
    }

    private func formattedDateString(from date: Date) -> String {
        let monthDay = monthDayFormatter.string(from: date)
        let weekday = weekdayFormatter.string(from: date)

        if let languageCode = displayLocale.language.languageCode?.identifier, languageCode.hasPrefix("zh") {
            return "\(monthDay) \(weekday)"
        } else {
            return "\(weekday), \(monthDay)"
        }
    }

    private func adjustDatesIfNeeded() {
        if isAllDay {
            let calendar = Calendar.current
            startDate = calendar.startOfDay(for: startDate)
            endDate = calendar.startOfDay(for: endDate)
            if endDate <= startDate {
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(24 * 60 * 60)
            }
        } else {
            if endDate <= startDate {
                endDate = startDate.addingTimeInterval(3600)
            }
        }
    }

    private func updateRepeatDisplay() {
        repeatRow.value = shortDescription(for: selectedRepeatRule)
        repeatRow.refreshMenu()
    }

    private func updateReminderDisplay() {
        reminderRow.value = selectedReminder.title
    }

    private func recurrenceString(for rule: RepeatRule) -> String? {
        guard !rule.isNone else { return nil }

        switch rule.frequency {
        case .daily:
            return "FREQ=DAILY;INTERVAL=\(rule.interval)"
        case .weekly:
            var components = ["FREQ=WEEKLY", "INTERVAL=\(rule.interval)"]
            if let weekdays = rule.weekdays, !weekdays.isEmpty {
                let symbols = weekdays.compactMap { weekdaySymbol(for: $0) }
                if !symbols.isEmpty {
                    components.append("BYDAY=\(symbols.joined(separator: ","))")
                }
            }
            return components.joined(separator: ";")
        case .monthly:
            return "FREQ=MONTHLY;INTERVAL=\(rule.interval)"
        case .yearly:
            return "FREQ=YEARLY;INTERVAL=\(rule.interval)"
        case .none:
            return nil
        }
    }

    private func weekdaySymbol(for index: Int) -> String? {
        // 1 = Sunday ... 7 = Saturday (matching RepeatRule expectations)
        let symbols = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        guard index >= 1, index <= symbols.count else { return nil }
        return symbols[index - 1]
    }

    private func shortDescription(for rule: RepeatRule) -> String {
        if rule.isNone { return "不重复" }
        switch rule.frequency {
        case .daily:
            return rule.interval == 1 ? "每天" : "每\(rule.interval)天"
        case .weekly:
            if rule.interval == 2 {
                return "每两周"
            }
            if let weekdays = rule.weekdays, !weekdays.isEmpty {
                let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
                let mapped = weekdays.compactMap { idx -> String? in
                    guard idx >= 1, idx <= names.count else { return nil }
                    return names[idx - 1]
                }
                if !mapped.isEmpty {
                    return "每周的" + mapped.joined(separator: "、")
                }
            }
            return rule.interval == 1 ? "每周" : "每\(rule.interval)周"
        case .monthly:
            return rule.interval == 1 ? "每月" : "每\(rule.interval)月"
        case .yearly:
            return rule.interval == 1 ? "每年" : "每\(rule.interval)年"
        case .none:
            return "不重复"
        }
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func presentCustomRepeatPlaceholder() {
        let alert = UIAlertController(
            title: "自定义重复",
            message: "自定义重复设置开发中，暂未提供详细界面。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITextFieldDelegate & UITextViewDelegate

extension AddEventViewController: UITextFieldDelegate, UITextViewDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        dismissPickers()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        dismissPickers()
    }

    func textViewDidChange(_ textView: UITextView) {
        guard let placeholderTextView = textView as? PlaceholderTextView else { return }
        placeholderTextView.updatePlaceholderVisibility()
    }
}


// MARK: - Custom UI Components

private final class DateSelectionButton: UIControl {
    private let container = UIStackView()
    private let dateLabel = UILabel()
    private let timeLabel = UILabel()

    var showsTime: Bool = true {
        didSet { timeLabel.isHidden = !showsTime }
    }

    var isHighlightedState: Bool = false {
        didSet { updateAppearance() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.clear.cgColor

        container.axis = .vertical
        container.alignment = .center
        container.spacing = 4
        container.isUserInteractionEnabled = false

        dateLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        dateLabel.textColor = UIColor.label

        timeLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        timeLabel.textColor = UIColor.label

        addSubview(container)
        container.addArrangedSubview(dateLabel)
        container.addArrangedSubview(timeLabel)

        container.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))
        }

        updateAppearance()
    }

    func update(date: String, time: String) {
        dateLabel.text = date
        timeLabel.text = time
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1.0 }
    }

    private func updateAppearance() {
        backgroundColor = isHighlightedState ? UIColor.systemGray5 : UIColor.clear
        layer.borderColor = isHighlightedState ? UIColor.systemGray4.cgColor : UIColor.clear.cgColor
    }
}

private final class OptionRowView: UIControl {
    private let iconView = UIImageView()
    private let valueLabel = UILabel()
    private let spacer = UIView()
    private let accessoryImageView = UIImageView()
    private let menuButton: UIButton
    private var storedMenuProvider: (() -> UIMenu)?

    var value: String {
        get { valueLabel.text ?? "" }
        set { valueLabel.text = newValue }
    }

    var accessoryImage: UIImage? {
        didSet {
            accessoryImageView.image = accessoryImage
            accessoryImageView.isHidden = accessoryImage == nil
        }
    }

    var menuProvider: (() -> UIMenu)? {
        didSet {
            storedMenuProvider = menuProvider
            configureMenu()
        }
    }

    init(iconName: String, placeholder: String) {
        if #available(iOS 14.0, *) {
            menuButton = MenuAnchorButton(type: .system)
        } else {
            menuButton = UIButton(type: .system)
        }
        super.init(frame: .zero)

        iconView.image = UIImage(systemName: iconName)
        iconView.tintColor = .secondaryLabel

        valueLabel.text = placeholder
        valueLabel.font = UIFont.systemFont(ofSize: 16)
        valueLabel.textColor = UIColor.label

        accessoryImageView.tintColor = .gray
        accessoryImageView.isHidden = true
        accessoryImageView.contentMode = .scaleAspectFit
        accessoryImageView.isUserInteractionEnabled = false
        
        
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [iconView, valueLabel, spacer, accessoryImageView])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 16
        stack.isUserInteractionEnabled = false

        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20))
        }

        iconView.snp.makeConstraints { make in
            make.width.height.equalTo(iconSize)
        }

        accessoryImageView.snp.makeConstraints { make in
            make.width.equalTo(21)
            make.height.equalTo(21)
        }

        menuButton.setTitle(nil, for: .normal)
        menuButton.tintColor = .clear
        menuButton.backgroundColor = .clear
        menuButton.isHidden = true
        menuButton.isUserInteractionEnabled = true
        addSubview(menuButton)
        menuButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        if #available(iOS 14.0, *), let anchorButton = menuButton as? MenuAnchorButton {
            anchorButton.anchorPointProvider = { [weak self] in
                guard let self else { return CGPoint.zero }
                let localCenter = CGPoint(x: self.accessoryImageView.bounds.midX, y: self.accessoryImageView.bounds.midY)
                return self.accessoryImageView.convert(localCenter, to: anchorButton)
            }
        }

        menuButton.addTarget(self, action: #selector(forwardTouchDown), for: .touchDown)
        menuButton.addTarget(self, action: #selector(forwardTouchUpInside), for: .touchUpInside)
        menuButton.addTarget(self, action: #selector(forwardTouchCancel), for: [.touchCancel, .touchDragExit, .touchUpOutside])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? UIColor.systemGray5 : UIColor.clear }
    }

    func showMenu() {
        guard #available(iOS 14.0, *) else { return }
        configureMenu()
        menuButton.sendActions(for: .touchDown)
        menuButton.sendActions(for: .touchUpInside)
    }

    func refreshMenu() {
        configureMenu()
    }

    private func configureMenu() {
        guard let provider = storedMenuProvider else {
            menuButton.menu = nil
            menuButton.isHidden = true
            return
        }

        guard #available(iOS 14.0, *) else {
            menuButton.menu = nil
            menuButton.isHidden = true
            return
        }

        menuButton.isHidden = false
        menuButton.menu = provider()
        menuButton.showsMenuAsPrimaryAction = true
    }

    @objc private func forwardTouchDown() {
        isHighlighted = true
        sendActions(for: .touchDown)
    }

    @objc private func forwardTouchUpInside() {
        isHighlighted = false
        sendActions(for: .touchUpInside)
    }

    @objc private func forwardTouchCancel() {
        isHighlighted = false
        sendActions(for: .touchCancel)
    }

}

private final class FormScrollView: UIScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        delaysContentTouches = false
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        if view is UIControl {
            return true
        }
        return super.touchesShouldCancel(in: view)
    }
}



@available(iOS 14.0, *)
private final class MenuAnchorButton: UIButton {
    var anchorPointProvider: (() -> CGPoint)?

    override func menuAttachmentPoint(for configuration: UIContextMenuConfiguration) -> CGPoint {
        anchorPointProvider?() ?? super.menuAttachmentPoint(for: configuration)
    }
}

private final class FormRowContainer: UIView {
    private let topSeparator = UIView()
    private let bottomSeparator = UIView()

    init(content: UIView, showTopSeparator: Bool, showBottomSeparator: Bool, horizontalInset: CGFloat) {
        super.init(frame: .zero)
        topSeparator.backgroundColor = UIColor.separator
        bottomSeparator.backgroundColor = UIColor.separator

        addSubview(topSeparator)
        addSubview(bottomSeparator)
        addSubview(content)

        let scale = UIScreen.main.scale

        topSeparator.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalToSuperview()
            make.height.equalTo(showTopSeparator ? 1.0 / scale : 0)
        }

        bottomSeparator.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview()
            make.height.equalTo(showBottomSeparator ? 1.0 / scale : 0)
        }

        content.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(horizontalInset)
            make.top.equalTo(topSeparator.snp.bottom)
            make.bottom.equalTo(bottomSeparator.snp.top)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class IconTextFieldRow: UIView {
    let textField = UITextField()

    init(iconName: String, placeholder: String) {
        super.init(frame: .zero)

        let iconView = UIImageView(image: UIImage(systemName: iconName))
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit

        textField.placeholder = placeholder
        textField.borderStyle = .none
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.clearButtonMode = .whileEditing

        let stack = UIStackView(arrangedSubviews: [iconView, textField])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 16

        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconView.snp.makeConstraints { make in
            make.width.height.equalTo(iconSize)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class NotesInputRow: UIView {
    let textView: PlaceholderTextView

    init(iconName: String, placeholder: String) {
        textView = PlaceholderTextView()
        super.init(frame: .zero)

        let iconView = UIImageView(image: UIImage(systemName: iconName))
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.snp.makeConstraints { make in
            make.width.height.equalTo(20)
        }

        textView.placeholderText = placeholder
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0

        let stack = UIStackView(arrangedSubviews: [iconView, textView])
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = 16

        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class PlaceholderTextView: UITextView {
    private let placeholderLabel = UILabel()
    var placeholderText: String = "" {
        didSet { placeholderLabel.text = placeholderText }
    }

    override var text: String! {
        didSet { updatePlaceholderVisibility() }
    }

    override var font: UIFont? {
        didSet { placeholderLabel.font = font }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        placeholderLabel.textColor = UIColor.placeholderText
        placeholderLabel.font = font ?? UIFont.systemFont(ofSize: 16)
        placeholderLabel.numberOfLines = 0
        addSubview(placeholderLabel)
        placeholderLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }
        updatePlaceholderVisibility()
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
