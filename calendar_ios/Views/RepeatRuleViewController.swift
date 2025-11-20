import UIKit
import SnapKit

final class RepeatRuleViewController: UIViewController {
    var onRuleChange: ((RepeatRule) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let summaryLabel = UILabel()
    private let intervalPicker = UIPickerView()
    private let dailyInfoLabel = UILabel()
    private let weeklySection = UIView()
    private let weeklyTitleLabel = UILabel()
    private let weekdaySelector = WeekdaySelectorView()
    private let monthlySection = UIView()
    private let monthlyContentStack = UIStackView()
    private let monthlyTitleLabel = UILabel()
    private let monthlyModeControl = UISegmentedControl(items: ["按日期", "按星期"])
    private let monthDayGrid = SelectionGridView(items: RepeatRuleViewController.dayItems, columns: 7)
    private let monthlyWeekPicker = OrdinalWeekdayPickerView()
    private let yearlySection = UIView()
    private let yearlyContentStack = UIStackView()
    private let yearlyTitleLabel = UILabel()
    private let monthGrid = SelectionGridView(items: RepeatRuleViewController.monthItems, columns: 4)
    private let yearWeekSwitch = UISwitch()
    private let yearWeekSwitchLabel = UILabel()
    private let yearWeekStack = UIStackView()
    private let yearWeekPicker = OrdinalWeekdayPickerView()

    private let frequencyOptions: [RepeatFrequency] = [.daily, .weekly, .monthly, .yearly]
    private let intervalValues: [Int] = Array(1...99)
    private let calendar: Calendar = .autoupdatingCurrent

    private let baseDate: Date
    private let baseWeekday: Int
    private let baseDay: Int
    private let baseMonth: Int
    private let baseOrdinal: Int

    private var selectedFrequency: RepeatFrequency
    private var selectedInterval: Int
    private var weeklySelectedWeekdays: Set<Int>
    private var monthlyMode: RepeatRule.MonthMode
    private var monthlySelectedDays: Set<Int>
    private var monthlyOrdinalValue: Int
    private var monthlyWeekdayValue: Int
    private var yearlySelectedMonths: Set<Int>
    private var yearlyUseWeekdayRule: Bool
    private var yearlyOrdinalValue: Int
    private var yearlyWeekdayValue: Int
    private var lastEmittedRule: RepeatRule?

    private static let dayItems: [SelectionGridView.Item] = (1...31).map { .init(id: $0, title: "\($0)") }
    private static let monthItems: [SelectionGridView.Item] = (1...12).map { .init(id: $0, title: "\($0)月") }

    init(initialRule: RepeatRule, baseDate: Date) {
        let cal = Calendar.autoupdatingCurrent
        self.baseDate = baseDate
        self.baseWeekday = cal.component(.weekday, from: baseDate)
        self.baseDay = cal.component(.day, from: baseDate)
        self.baseMonth = cal.component(.month, from: baseDate)
        self.baseOrdinal = RepeatRuleViewController.computeOrdinalValue(for: baseDate, calendar: cal)

        let sanitizedRule = RepeatRuleViewController.sanitizedRule(from: initialRule)
        self.selectedFrequency = sanitizedRule.frequency
        self.selectedInterval = max(1, min(99, sanitizedRule.interval))

        self.weeklySelectedWeekdays = RepeatRuleViewController.sanitizeWeekdays(sanitizedRule.weekdays, fallback: self.baseWeekday)

        self.monthlyMode = sanitizedRule.monthMode ?? .byDate
        self.monthlySelectedDays = RepeatRuleViewController.sanitizeMonthDays(sanitizedRule.monthDays, fallback: self.baseDay)
        self.monthlyOrdinalValue = sanitizedRule.frequency == .monthly
            ? RepeatRuleViewController.normalizeOrdinal(sanitizedRule.weekOrdinal, fallback: self.baseOrdinal)
            : self.baseOrdinal
        self.monthlyWeekdayValue = sanitizedRule.frequency == .monthly
            ? RepeatRuleViewController.normalizeWeekday(sanitizedRule.weekday, fallback: self.baseWeekday)
            : self.baseWeekday

        self.yearlySelectedMonths = RepeatRuleViewController.sanitizeMonths(sanitizedRule.months, fallback: self.baseMonth)
        self.yearlyUseWeekdayRule = sanitizedRule.frequency == .yearly ? (sanitizedRule.yearMode == .byWeekday) : false
        self.yearlyOrdinalValue = sanitizedRule.frequency == .yearly
            ? RepeatRuleViewController.normalizeOrdinal(sanitizedRule.weekOrdinal, fallback: self.baseOrdinal)
            : self.baseOrdinal
        self.yearlyWeekdayValue = sanitizedRule.frequency == .yearly
            ? RepeatRuleViewController.normalizeWeekday(sanitizedRule.weekday, fallback: self.baseWeekday)
            : self.baseWeekday

        super.init(nibName: nil, bundle: nil)

        if sanitizedRule.isNone {
            selectedFrequency = .daily
            selectedInterval = 1
            lastEmittedRule = RepeatRule.none()
        } else {
            lastEmittedRule = buildRepeatRule()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureLayout()
        configureActions()
        configurePickers()
        applyInitialSelections()
        refreshSummary(shouldNotify: false)
    }

    private func configureNavigation() {
        title = "自定义重复"
        view.backgroundColor = .systemGroupedBackground
    }

    private func configureLayout() {
        scrollView.alwaysBounceVertical = true

        stackView.axis = .vertical
        stackView.spacing = 24
        stackView.layoutMargins = UIEdgeInsets(top: 24, left: 16, bottom: 40, right: 16)
        stackView.isLayoutMarginsRelativeArrangement = true

        summaryLabel.numberOfLines = 0
        summaryLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)

        intervalPicker.setContentCompressionResistancePriority(.required, for: .vertical)

        dailyInfoLabel.text = "将按照所选天数重复"
        dailyInfoLabel.textColor = .secondaryLabel
        dailyInfoLabel.font = UIFont.systemFont(ofSize: 15)

        weeklyTitleLabel.text = "选择重复的星期"
        weeklyTitleLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)

        monthlyTitleLabel.text = "每月重复选项"
        monthlyTitleLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)

        yearlyTitleLabel.text = "每年重复月份"
        yearlyTitleLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)

        yearWeekStack.axis = .horizontal
        yearWeekStack.alignment = .center
        yearWeekStack.spacing = 12
        yearWeekStack.distribution = .fill
        yearWeekSwitchLabel.text = "按星期"
        yearWeekSwitchLabel.font = UIFont.systemFont(ofSize: 15)

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

        stackView.addArrangedSubview(summaryLabel)
        stackView.addArrangedSubview(intervalPicker)
        intervalPicker.snp.makeConstraints { make in
            make.height.equalTo(180)
        }
        stackView.addArrangedSubview(dailyInfoLabel)

        weeklySection.addSubview(weeklyTitleLabel)
        weeklySection.addSubview(weekdaySelector)
        weeklyTitleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        weekdaySelector.snp.makeConstraints { make in
            make.top.equalTo(weeklyTitleLabel.snp.bottom).offset(12)
            make.leading.trailing.bottom.equalToSuperview()
        }
        stackView.addArrangedSubview(weeklySection)

        monthlyContentStack.axis = .vertical
        monthlyContentStack.spacing = 12
        monthlyContentStack.addArrangedSubview(monthlyTitleLabel)
        monthlyContentStack.addArrangedSubview(monthlyModeControl)
        monthlyContentStack.addArrangedSubview(monthDayGrid)
        monthlyContentStack.addArrangedSubview(monthlyWeekPicker)
        monthlyContentStack.setCustomSpacing(16, after: monthlyModeControl)
        monthlySection.addSubview(monthlyContentStack)
        monthlyContentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        stackView.addArrangedSubview(monthlySection)

        yearlyContentStack.axis = .vertical
        yearlyContentStack.spacing = 12
        yearWeekStack.addArrangedSubview(yearWeekSwitchLabel)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        yearWeekStack.addArrangedSubview(spacer)
        yearWeekStack.addArrangedSubview(yearWeekSwitch)
        yearlyContentStack.addArrangedSubview(yearlyTitleLabel)
        yearlyContentStack.addArrangedSubview(monthGrid)
        yearlyContentStack.addArrangedSubview(yearWeekStack)
        yearlyContentStack.addArrangedSubview(yearWeekPicker)
        yearlyContentStack.setCustomSpacing(16, after: monthGrid)
        yearlySection.addSubview(yearlyContentStack)
        yearlyContentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        stackView.addArrangedSubview(yearlySection)
    }

    private func configureActions() {
        monthlyModeControl.addTarget(self, action: #selector(monthlyModeChanged), for: .valueChanged)
        yearWeekSwitch.addTarget(self, action: #selector(yearWeekSwitchChanged), for: .valueChanged)

        weekdaySelector.onSelectionChanged = { [weak self] newSelection in
            guard let self else { return }
            self.weeklySelectedWeekdays = newSelection
            self.refreshSummary()
        }

        monthDayGrid.onSelectionChanged = { [weak self] newSelection in
            guard let self else { return }
            self.monthlySelectedDays = newSelection
            self.refreshSummary()
        }

        monthGrid.onSelectionChanged = { [weak self] newSelection in
            guard let self else { return }
            self.yearlySelectedMonths = newSelection
            self.refreshSummary()
        }

        monthlyWeekPicker.onSelectionChanged = { [weak self] ordinal, weekday in
            guard let self else { return }
            self.monthlyOrdinalValue = ordinal
            self.monthlyWeekdayValue = weekday
            self.refreshSummary()
        }

        yearWeekPicker.onSelectionChanged = { [weak self] ordinal, weekday in
            guard let self else { return }
            self.yearlyOrdinalValue = ordinal
            self.yearlyWeekdayValue = weekday
            self.refreshSummary()
        }
    }

    private func configurePickers() {
        intervalPicker.dataSource = self
        intervalPicker.delegate = self
    }

    private func applyInitialSelections() {
        let intervalRow = max(0, min(selectedInterval - 1, intervalValues.count - 1))
        intervalPicker.selectRow(intervalRow, inComponent: 0, animated: false)
        if let freqIndex = frequencyOptions.firstIndex(of: selectedFrequency) {
            intervalPicker.selectRow(freqIndex, inComponent: 1, animated: false)
        }

        weekdaySelector.updateSelection(weeklySelectedWeekdays)
        monthlyModeControl.selectedSegmentIndex = monthlyMode == .byDate ? 0 : 1
        monthDayGrid.updateSelection(monthlySelectedDays)
        monthlyWeekPicker.updateSelection(ordinal: monthlyOrdinalValue, weekday: monthlyWeekdayValue)
        monthGrid.updateSelection(yearlySelectedMonths)
        yearWeekSwitch.isOn = yearlyUseWeekdayRule
        yearWeekPicker.updateSelection(ordinal: yearlyOrdinalValue, weekday: yearlyWeekdayValue)
        updateFrequencySections()
        updateMonthlyModeVisibility()
        yearWeekPicker.isHidden = !yearlyUseWeekdayRule
    }

    @objc private func monthlyModeChanged() {
        monthlyMode = monthlyModeControl.selectedSegmentIndex == 0 ? .byDate : .byWeekday
        updateMonthlyModeVisibility()
        refreshSummary()
    }

    @objc private func yearWeekSwitchChanged() {
        yearlyUseWeekdayRule = yearWeekSwitch.isOn
        yearWeekPicker.isHidden = !yearlyUseWeekdayRule
        refreshSummary()
    }

    private func updateFrequencySections() {
        dailyInfoLabel.isHidden = selectedFrequency != .daily
        weeklySection.isHidden = selectedFrequency != .weekly
        monthlySection.isHidden = selectedFrequency != .monthly
        yearlySection.isHidden = selectedFrequency != .yearly
    }

    private func updateMonthlyModeVisibility() {
        let byDate = monthlyMode == .byDate
        monthDayGrid.isHidden = !byDate
        monthlyWeekPicker.isHidden = byDate
    }

    private func refreshSummary(shouldNotify: Bool = true) {
        let rule = buildRepeatRule()
        summaryLabel.text = rule.humanReadableDescription()
        guard shouldNotify else { return }
        if let lastRule = lastEmittedRule, lastRule == rule {
            return
        }
        lastEmittedRule = rule
        onRuleChange?(rule)
    }

    private func buildRepeatRule() -> RepeatRule {
        switch selectedFrequency {
        case .daily:
            return RepeatRule(frequency: .daily, interval: selectedInterval)
        case .weekly:
            let weekdays = weeklySelectedWeekdays.isEmpty ? [baseWeekday] : Array(weeklySelectedWeekdays)
            return RepeatRule(frequency: .weekly, interval: selectedInterval, weekdays: weekdays.sorted())
        case .monthly:
            if monthlyMode == .byDate {
                let days = monthlySelectedDays.isEmpty ? [baseDay] : Array(monthlySelectedDays)
                return RepeatRule(
                    frequency: .monthly,
                    interval: selectedInterval,
                    monthDays: days.sorted(),
                    monthMode: .byDate
                )
            } else {
                return RepeatRule(
                    frequency: .monthly,
                    interval: selectedInterval,
                    monthMode: .byWeekday,
                    weekOrdinal: monthlyOrdinalValue,
                    weekday: monthlyWeekdayValue
                )
            }
        case .yearly:
            let months = yearlySelectedMonths.isEmpty ? [baseMonth] : Array(yearlySelectedMonths)
            var rule = RepeatRule(
                frequency: .yearly,
                interval: selectedInterval,
                months: months.sorted(),
                yearMode: yearlyUseWeekdayRule ? .byWeekday : .byDate
            )
            if yearlyUseWeekdayRule {
                rule.weekOrdinal = yearlyOrdinalValue
                rule.weekday = yearlyWeekdayValue
            } else {
                rule.monthDays = [baseDay]
            }
            return rule
        case .none:
            return RepeatRule.none()
        }
    }

    private static func sanitizedRule(from rule: RepeatRule) -> RepeatRule {
        guard !rule.isNone else {
            return RepeatRule(frequency: .daily)
        }
        return rule
    }

    private static func sanitizeWeekdays(_ values: [Int]?, fallback: Int) -> Set<Int> {
        let filtered = (values ?? []).filter { (1...7).contains($0) }
        return filtered.isEmpty ? Set([fallback]) : Set(filtered)
    }

    private static func sanitizeMonthDays(_ values: [Int]?, fallback: Int) -> Set<Int> {
        let filtered = (values ?? []).filter { (1...31).contains($0) }
        return filtered.isEmpty ? Set([fallback]) : Set(filtered)
    }

    private static func sanitizeMonths(_ values: [Int]?, fallback: Int) -> Set<Int> {
        let filtered = (values ?? []).filter { (1...12).contains($0) }
        return filtered.isEmpty ? Set([fallback]) : Set(filtered)
    }

    private static func normalizeWeekday(_ value: Int?, fallback: Int) -> Int {
        guard let value, (1...7).contains(value) else { return fallback }
        return value
    }

    private static func normalizeOrdinal(_ value: Int?, fallback: Int) -> Int {
        guard let value, (1...7).contains(value) else { return fallback }
        return value
    }

    private static func computeOrdinalValue(for date: Date, calendar: Calendar) -> Int {
        guard let next = calendar.date(byAdding: .day, value: 7, to: date) else { return 1 }
        let isSameMonthNext = calendar.isDate(next, equalTo: date, toGranularity: .month)
        if !isSameMonthNext {
            return 7
        }
        guard let secondNext = calendar.date(byAdding: .day, value: 14, to: date) else {
            return 7
        }
        let isSameMonthSecond = calendar.isDate(secondNext, equalTo: date, toGranularity: .month)
        if !isSameMonthSecond {
            return 6
        }
        let weekOfMonth = calendar.component(.weekOfMonth, from: date)
        return max(1, min(5, weekOfMonth))
    }
}

extension RepeatRuleViewController: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        2
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        component == 0 ? intervalValues.count : frequencyOptions.count
    }
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        return 44
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if component == 0 {
            return "\(intervalValues[row])"
        }
        switch frequencyOptions[row] {
        case .daily: return "天"
        case .weekly: return "周"
        case .monthly: return "月"
        case .yearly: return "年"
        case .none: return "无"
        }
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if component == 0 {
            selectedInterval = intervalValues[row]
        } else {
            selectedFrequency = frequencyOptions[row]
            updateFrequencySections()
        }
        refreshSummary()
    }
}

private final class WeekdaySelectorView: UIView {
    var onSelectionChanged: ((Set<Int>) -> Void)?

    private let stackView = UIStackView()
    private var buttons: [SelectionChipButton] = []
    private let calendar: Calendar = .autoupdatingCurrent
    private var selection: Set<Int> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.distribution = .fillEqually
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let orderedWeekdays = orderedWeekdayValues()
        orderedWeekdays.forEach { weekday in
            let button = SelectionChipButton()
            button.setTitle(label(for: weekday), for: .normal)
            button.tag = weekday
            button.addTarget(self, action: #selector(dayTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
            buttons.append(button)
        }
    }

    func updateSelection(_ newSelection: Set<Int>) {
        selection = newSelection
        updateButtons()
    }

    @objc private func dayTapped(_ sender: UIButton) {
        let day = sender.tag
        var newSelection = selection
        if newSelection.contains(day) {
            if newSelection.count == 1 { return }
            newSelection.remove(day)
        } else {
            newSelection.insert(day)
        }
        selection = newSelection
        updateButtons()
        onSelectionChanged?(selection)
    }

    private func updateButtons() {
        buttons.forEach { button in
            button.isSelected = selection.contains(button.tag)
        }
    }

    private func orderedWeekdayValues() -> [Int] {
        let firstWeekday = calendar.firstWeekday
        var values = Array(1...7)
        if firstWeekday > 1 {
            let prefix = values[0..<(firstWeekday - 1)]
            values.removeFirst(firstWeekday - 1)
            values.append(contentsOf: prefix)
        }
        return values
    }

    private func label(for weekday: Int) -> String {
        let labels = [1: "周日", 2: "周一", 3: "周二", 4: "周三", 5: "周四", 6: "周五", 7: "周六"]
        return labels[weekday] ?? "周?"
    }
}

private final class SelectionGridView: UIView {
    struct Item {
        let id: Int
        let title: String
    }

    var onSelectionChanged: ((Set<Int>) -> Void)?
    var minimumSelectionCount: Int = 1

    private let columns: Int
    private let rowsStack = UIStackView()
    private var buttons: [SelectionChipButton] = []
    private var selection: Set<Int> = []
    private var items: [Item]

    init(items: [Item], columns: Int) {
        self.items = items
        self.columns = columns
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        rowsStack.axis = .vertical
        rowsStack.spacing = 8
        addSubview(rowsStack)
        rowsStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        buildGrid()
    }

    private func buildGrid() {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        var currentRow: UIStackView?
        var countInRow = 0

        for (index, item) in items.enumerated() {
            if countInRow == 0 {
                let rowStack = UIStackView()
                rowStack.axis = .horizontal
                rowStack.spacing = 8
                rowStack.distribution = .fillEqually
                rowsStack.addArrangedSubview(rowStack)
                currentRow = rowStack
            }
            let button = SelectionChipButton()
            button.setTitle(item.title, for: .normal)
            button.tag = item.id
            button.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
            currentRow?.addArrangedSubview(button)
            buttons.append(button)
            countInRow += 1
            if countInRow == columns {
                countInRow = 0
            }

            if index == items.count - 1, countInRow != 0, let rowStack = currentRow {
                let paddingCount = columns - countInRow
                for _ in 0..<paddingCount {
                    let spacer = UIView()
                    rowStack.addArrangedSubview(spacer)
                }
            }
        }
    }

    func updateSelection(_ newSelection: Set<Int>) {
        selection = newSelection
        updateButtons()
    }

    @objc private func itemTapped(_ sender: UIButton) {
        let id = sender.tag
        var newSelection = selection
        if newSelection.contains(id) {
            if newSelection.count == minimumSelectionCount { return }
            newSelection.remove(id)
        } else {
            newSelection.insert(id)
        }
        selection = newSelection
        updateButtons()
        onSelectionChanged?(selection)
    }

    private func updateButtons() {
        buttons.forEach { button in
            button.isSelected = selection.contains(button.tag)
        }
    }
}

private final class OrdinalWeekdayPickerView: UIView, UIPickerViewDataSource, UIPickerViewDelegate {
    var onSelectionChanged: ((Int, Int) -> Void)?

    private let picker = UIPickerView()
    private var ordinalValue: Int = 1
    private var weekdayValue: Int = 1
    private let ordinals: [Int] = [1, 2, 3, 4, 5, 6, 7]
    private let ordinalTitles: [Int: String] = [
        1: "第一个",
        2: "第二个",
        3: "第三个",
        4: "第四个",
        5: "第五个",
        6: "倒数第二个",
        7: "最后一个"
    ]
    private let weekdayTitles: [Int: String] = [
        1: "周日",
        2: "周一",
        3: "周二",
        4: "周三",
        5: "周四",
        6: "周五",
        7: "周六"
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        picker.dataSource = self
        picker.delegate = self
        addSubview(picker)
        picker.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalTo(180)
        }
    }

    func updateSelection(ordinal: Int, weekday: Int) {
        ordinalValue = ordinals.contains(ordinal) ? ordinal : 1
        weekdayValue = (1...7).contains(weekday) ? weekday : 1
        if let ordinalIndex = ordinals.firstIndex(of: ordinalValue) {
            picker.selectRow(ordinalIndex, inComponent: 0, animated: false)
        }
        picker.selectRow(max(0, weekdayValue - 1), inComponent: 1, animated: false)
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        2
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        component == 0 ? ordinals.count : 7
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if component == 0 {
            let value = ordinals[row]
            return ordinalTitles[value]
        } else {
            return weekdayTitles[row + 1]
        }
    }
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        return 44
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if component == 0 {
            ordinalValue = ordinals[row]
        } else {
            weekdayValue = row + 1
        }
        onSelectionChanged?(ordinalValue, weekdayValue)
    }
}

private final class SelectionChipButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        titleLabel?.font = UIFont.systemFont(ofSize: 15)
        setTitleColor(.label, for: .normal)
        setTitleColor(.white, for: .selected)
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    override var isSelected: Bool {
        didSet {
            backgroundColor = isSelected ? UIColor.systemBlue : UIColor.clear
            layer.borderColor = (isSelected ? UIColor.systemBlue : UIColor.separator).cgColor
        }
    }
}
