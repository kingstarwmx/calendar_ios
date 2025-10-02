import UIKit
import SnapKit

/// 自定义日历单元格
/// 参考 Flutter 版本的 CalendarCell 布局
class CustomCalendarCell: FSCalendarCell {

    /// 自定义日期标签（顶部显示）
    private let customTitleLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        return label
    }()

    /// 事件容器（垂直列表）
    private let eventsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .equalSpacing  // 改为等间距分布，不拉伸子视图
        stackView.spacing = 1
        return stackView
    }()

    /// 最大显示事件数
    private let maxEventCount = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // 隐藏原有的 titleLabel 和其他元素
        titleLabel.isHidden = true
        subtitleLabel.isHidden = true
        eventIndicator.isHidden = true

        // 添加自定义视图
        contentView.addSubview(customTitleLabel)
        contentView.addSubview(eventsStackView)

        // 设置约束
        customTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(2)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(24)
        }

        eventsStackView.snp.makeConstraints { make in
            make.top.equalTo(customTitleLabel.snp.bottom)
            make.leading.equalToSuperview().offset(2)
            make.trailing.equalToSuperview().offset(-2)
            // 不设置 bottom 约束，让 StackView 根据内容自适应高度
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // 确保自定义视图在最上层
        contentView.bringSubviewToFront(customTitleLabel)
        contentView.bringSubviewToFront(eventsStackView)
    }

    /// 配置单元格
    func configure(with date: Date, events: [Event], isSelected: Bool, isToday: Bool, isPlaceholder: Bool) {
        // 设置日期文本
        let day = Calendar.current.component(.day, from: date)
        customTitleLabel.text = "\(day)"

        // 设置日期标签样式
        if isSelected {
            customTitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
            customTitleLabel.textColor = .white
            contentView.backgroundColor = .systemBlue
            contentView.layer.cornerRadius = 8
        } else if isToday {
            customTitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
            customTitleLabel.textColor = .systemBlue
            contentView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
            contentView.layer.cornerRadius = 8
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.5).cgColor
        } else {
            customTitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            customTitleLabel.textColor = isPlaceholder ? .systemGray3 : .label
            contentView.backgroundColor = .clear
            contentView.layer.borderWidth = 0
        }

        // 配置事件列表
        configureEvents(events: events, date: date)
    }

    /// 配置事件显示
    private func configureEvents(events: [Event], date: Date) {
        // 清空现有事件视图
        eventsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !events.isEmpty else { return }

        // 排序：多天事件优先，然后按时间排序
        let sortedEvents = events.sorted { event1, event2 in
            let isMultiDay1 = isMultiDayEvent(event1)
            let isMultiDay2 = isMultiDayEvent(event2)

            if isMultiDay1 && !isMultiDay2 {
                return true
            } else if !isMultiDay1 && isMultiDay2 {
                return false
            } else {
                return event1.startDate < event2.startDate
            }
        }

        // 显示前几个事件
        let displayCount = min(sortedEvents.count, maxEventCount)
        for i in 0..<displayCount {
            let event = sortedEvents[i]
            let eventBar = createEventBar(for: event, date: date)
            eventsStackView.addArrangedSubview(eventBar)
        }

        // 如果还有更多事件，显示 "+n" 指示器
        if sortedEvents.count > maxEventCount {
            let remaining = sortedEvents.count - maxEventCount
            let overflowIndicator = createOverflowIndicator(count: remaining)
            eventsStackView.addArrangedSubview(overflowIndicator)
        }
    }

    /// 创建事件条
    private func createEventBar(for event: Event, date: Date) -> UIView {
        let container = UIView()
        container.snp.makeConstraints { make in
            make.height.equalTo(14)
        }

        let eventColor = event.customColor ?? .systemBlue
        let calendar = Calendar.current
        let currentDate = calendar.startOfDay(for: date)
        let eventStart = calendar.startOfDay(for: event.startDate)
        let eventEnd = calendar.startOfDay(for: event.endDate)

        let isStart = currentDate == eventStart
        let isEnd = currentDate == eventEnd
        let isMiddle = currentDate > eventStart && currentDate < eventEnd
        let isSingleDay = !isMultiDayEvent(event)

        // 判断是否延伸到边缘
        let shouldExtendToEdges = !isSingleDay && (isMiddle || (isStart && !isEnd) || (isEnd && !isStart))

        let eventBar = UIView()
        eventBar.backgroundColor = eventColor.withAlphaComponent(0.9)
        container.addSubview(eventBar)

        if shouldExtendToEdges {
            // 延伸到边缘：左右无内边距
            eventBar.snp.makeConstraints { make in
                make.top.equalToSuperview()
                make.bottom.equalToSuperview()
                make.leading.trailing.equalToSuperview()
            }

            // 设置圆角
            eventBar.layer.cornerRadius = 2
            eventBar.layer.maskedCorners = []
            if isStart {
                eventBar.layer.maskedCorners.insert([.layerMinXMinYCorner, .layerMinXMaxYCorner])
            }
            if isEnd {
                eventBar.layer.maskedCorners.insert([.layerMaxXMinYCorner, .layerMaxXMaxYCorner])
            }
        } else {
            // 单天事件：左右有内边距
            eventBar.snp.makeConstraints { make in
                make.top.equalToSuperview()
                make.bottom.equalToSuperview()
                make.leading.trailing.equalToSuperview()
            }
            eventBar.layer.cornerRadius = 2
        }

        // 判断是否显示文字
        let shouldShowText = shouldShowEventText(event: event, date: date, isStart: isStart)

        if shouldShowText {
            let label = UILabel()
            label.text = event.title
            label.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
            label.textColor = getTextColor(for: eventColor)
            label.textAlignment = .center
            label.numberOfLines = 1
            eventBar.addSubview(label)

            label.snp.makeConstraints { make in
                make.center.equalToSuperview()
                make.leading.greaterThanOrEqualToSuperview().offset(2)
                make.trailing.lessThanOrEqualToSuperview().offset(-2)
            }
        }

        return container
    }

    /// 创建溢出指示器 "+n"
    private func createOverflowIndicator(count: Int) -> UIView {
        let container = UIView()
        container.snp.makeConstraints { make in
            make.height.equalTo(14)
        }

        let indicator = UIView()
        indicator.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.3)
        indicator.layer.cornerRadius = 2
        container.addSubview(indicator)

        indicator.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview()
        }

        let label = UILabel()
        label.text = "+\(count)"
        label.font = UIFont.systemFont(ofSize: 8, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        indicator.addSubview(label)

        label.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        return container
    }

    /// 判断是否为多天事件
    private func isMultiDayEvent(_ event: Event) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: event.startDate)
        let end = calendar.startOfDay(for: event.endDate)
        return start != end
    }

    /// 判断是否应该显示事件文字
    private func shouldShowEventText(event: Event, date: Date, isStart: Bool) -> Bool {
        // 单天事件总是显示文字
        if !isMultiDayEvent(event) {
            return true
        }

        // 多天事件：在开始日期或每周开始（周日）显示
        let calendar = Calendar.current
        let currentDate = calendar.startOfDay(for: date)
        let eventStart = calendar.startOfDay(for: event.startDate)
        let eventEnd = calendar.startOfDay(for: event.endDate)

        if currentDate == eventStart {
            return true
        }

        let weekday = calendar.component(.weekday, from: date)
        let isInEventRange = currentDate >= eventStart && currentDate <= eventEnd

        if weekday == 1 && isInEventRange { // 周日
            return true
        }

        return false
    }

    /// 根据背景色获取合适的文字颜色
    private func getTextColor(for backgroundColor: UIColor) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        backgroundColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.5 ? UIColor.black.withAlphaComponent(0.87) : .white
    }
}
