import UIKit
import SnapKit

/// 事件位置信息
struct EventPosition {
    let isStart: Bool
    let isMiddle: Bool
    let isEnd: Bool
}

private final class EventSlotView: UIView {

    enum LabelMode {
        case hidden
        case extendLeading(text: String, color: UIColor)
        case centered(text: String, color: UIColor)
    }

    private let eventBar = UIView()
    private let textLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        label.clipsToBounds = false
        label.isHidden = true
        return label
    }()

    private let overflowBackground: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 2
        view.isHidden = true
        return view
    }()

    private let overflowLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 8, weight: .semibold)
        label.textAlignment = .center
        label.textColor = .label
        return label
    }()

    init(slotHeight: CGFloat) {
        super.init(frame: .zero)
        setup(slotHeight: slotHeight)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(slotHeight: CustomCalendarCell.layoutMetrics.eventSlotHeight)
    }

    private func setup(slotHeight: CGFloat) {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
        isHidden = true

        snp.makeConstraints { make in
            make.height.equalTo(slotHeight)
        }

        addSubview(eventBar)
        eventBar.clipsToBounds = false
        eventBar.isHidden = true
        eventBar.layer.cornerRadius = 2

        eventBar.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.equalToSuperview().offset(2)
            make.trailing.equalToSuperview().offset(-2)
        }

        eventBar.addSubview(textLabel)

        addSubview(overflowBackground)
        overflowBackground.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.equalToSuperview().offset(2)
            make.trailing.equalToSuperview().offset(-2)
        }

        overflowBackground.addSubview(overflowLabel)
        overflowLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        overflowBackground.isHidden = true
    }

    func configureBlank() {
        isHidden = false
        eventBar.isHidden = true
        overflowBackground.isHidden = true
        textLabel.isHidden = true
        textLabel.text = nil
        textLabel.tag = 0
    }

    func configureOverflow(count: Int) {
        isHidden = false
        eventBar.isHidden = true
        overflowBackground.isHidden = false
        overflowBackground.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.2)
        overflowLabel.text = "+\(count)"
        textLabel.isHidden = true
        textLabel.tag = 0
    }

    func configureEvent(with configuration: CustomCalendarCell.EventSlotConfiguration) {
        isHidden = false
        overflowBackground.isHidden = true
        eventBar.isHidden = false

        eventBar.backgroundColor = configuration.backgroundColor
        eventBar.layer.cornerRadius = 2
        eventBar.layer.maskedCorners = configuration.maskedCorners

        eventBar.snp.remakeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.equalToSuperview().offset(configuration.leadingInset)
            make.trailing.equalToSuperview().offset(configuration.trailingInset)
        }

        applyLabelMode(configuration.labelMode)
    }

    func reset() {
        isHidden = true
        eventBar.isHidden = true
        overflowBackground.isHidden = true
        textLabel.text = nil
        textLabel.isHidden = true
        textLabel.tag = 0
        textLabel.layer.zPosition = 0
    }

    func elevateExtendedLabel() {
        textLabel.layer.zPosition = textLabel.tag == 999 ? 9999 : 0
    }

    private func applyLabelMode(_ mode: LabelMode) {
        switch mode {
        case .hidden:
            textLabel.isHidden = true
            textLabel.tag = 0
            textLabel.text = nil
        case let .extendLeading(text, color):
            textLabel.isHidden = false
            textLabel.tag = 999
            textLabel.text = text
            textLabel.textColor = color
            textLabel.textAlignment = .left
            textLabel.numberOfLines = 1
            textLabel.lineBreakMode = .byClipping

            textLabel.snp.remakeConstraints { make in
                make.centerY.equalToSuperview()
                make.leading.equalToSuperview().offset(4)
                make.width.greaterThanOrEqualTo(200)
            }
        case let .centered(text, color):
            textLabel.isHidden = false
            textLabel.tag = 0
            textLabel.text = text
            textLabel.textColor = color
            textLabel.textAlignment = .center
            textLabel.numberOfLines = 1
            textLabel.lineBreakMode = .byTruncatingTail

            textLabel.snp.remakeConstraints { make in
                make.center.equalToSuperview()
                make.leading.greaterThanOrEqualToSuperview().offset(2)
                make.trailing.lessThanOrEqualToSuperview().offset(-2)
            }
        }
    }
}

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
        stackView.distribution = .equalSpacing
        stackView.spacing = 1
        stackView.layoutMargins = .zero  // 确保没有内边距
        stackView.isLayoutMarginsRelativeArrangement = false  // 禁用内边距
        return stackView
    }()

    private enum EventDisplayItem {
        case event(Event, EventPosition)
        case overflow(Int)
    }

    fileprivate struct EventSlotConfiguration {
        let backgroundColor: UIColor
        let leadingInset: CGFloat
        let trailingInset: CGFloat
        let maskedCorners: CACornerMask
        let labelMode: EventSlotView.LabelMode
    }

    /// 选中状态的 shapeLayer（实线描边）
    private let selectedShapeLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.systemBlue.withAlphaComponent(0.1).cgColor
        
        layer.strokeColor = UIColor.systemGray4.cgColor
        layer.lineWidth = 1.5
        layer.isHidden = true
        return layer
    }()

    /// 今天状态的 shapeLayer（虚线描边）
    private let todayShapeLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.systemGray4.cgColor
        layer.lineWidth = 1.5
        layer.lineDashPattern = [4, 2]  // 虚线样式
        layer.isHidden = true
        return layer
    }()

    /// 顶部分割线（用于每行的分割）
    private let topSeparatorView: UIView = {
        let view = UIView()
        view.backgroundColor = .separator  // 系统标准分割线颜色
        return view
    }()


    /// 布局相关常量
    struct LayoutMetrics {
        let separatorHeight: CGFloat
        let titleTopInset: CGFloat
        let titleHeight: CGFloat
        let eventSlotHeight: CGFloat
        let eventSlotSpacing: CGFloat

        var reservedHeight: CGFloat {
            separatorHeight + titleTopInset + titleHeight
        }
    }

    static let layoutMetrics = LayoutMetrics(
        separatorHeight: 1.0 / UIScreen.main.scale,
        titleTopInset: 2,
        titleHeight: 24,
        eventSlotHeight: 14,
        eventSlotSpacing: 1
    )

    /// 最大显示事件数（默认值，若未设置 maxVisibleSlots 时使用）
    private let maxEventCount = 3

    /// 理论上可显示的最大色块数量（由外部根据高度计算后传入）
    var maxVisibleSlots: Int = 0 {
        didSet {
            if maxVisibleSlots < 0 {
                maxVisibleSlots = 0
                return
            }
            prepareSlots(capacity: max(maxVisibleSlots, eventSlots.count))
        }
    }

    /// 事件槽位池
    private var eventSlots: [EventSlotView] = []

    /// 当前事件列表（用于配置）
    private var currentEvents: [Event] = []
    private var currentDate: Date = Date()

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

        // 隐藏原有的 shapeLayer
        shapeLayer.isHidden = true

        // 允许事件条超出边界，实现连续效果
        contentView.clipsToBounds = false
        self.clipsToBounds = false

        // 添加自定义 shapeLayers（顺序：today 在下，selected 在上）
        contentView.layer.insertSublayer(todayShapeLayer, at: 0)
        contentView.layer.insertSublayer(selectedShapeLayer, at: 1)

        // 添加自定义视图
        contentView.addSubview(topSeparatorView)  // 添加顶部分割线
        contentView.addSubview(customTitleLabel)
        contentView.addSubview(eventsStackView)

        // 确保eventsStackView不裁剪内容，允许文字延伸
        eventsStackView.clipsToBounds = false

        // 设置约束
        topSeparatorView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalToSuperview()
            make.trailing.equalToSuperview()
            make.height.equalTo(1.0 / UIScreen.main.scale)  // 标准分割线高度（1像素）
        }

        customTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(2)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(24)
        }

        eventsStackView.snp.makeConstraints { make in
            make.top.equalTo(customTitleLabel.snp.bottom)
            make.leading.trailing.equalToSuperview()  // 移除内边距，让事件条可以延伸到边缘
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // 查找并提升所有标记为999的label的层级
        eventSlots.forEach { $0.elevateExtendedLabel() }

        // 更新 shapeLayer 的路径
        let cornerRadius: CGFloat = 8
        let bounds = contentView.bounds.insetBy(dx: 1, dy: 1)
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)

        selectedShapeLayer.path = path.cgPath
        todayShapeLayer.path = path.cgPath
    }

    override func configureAppearance() {
        super.configureAppearance()

        // 设置日期文本
        let day = Calendar.current.component(.day, from: currentDate)
        customTitleLabel.text = "\(day)"

        // 判断状态
        let calendar = Calendar.current
        let isSelected = self.isSelected
        let isToday = calendar.isDateInToday(currentDate)
        let isPlaceholder = self.isPlaceholder

        // 更新文字颜色和字体
        let titleFontSize = 16.0
        if isSelected {
            customTitleLabel.font = UIFont.systemFont(ofSize: titleFontSize, weight: .bold)
            customTitleLabel.textColor = .label
        } else if isToday {
            customTitleLabel.font = UIFont.systemFont(ofSize: titleFontSize, weight: .bold)
            customTitleLabel.textColor = .label
        } else {
            customTitleLabel.font = UIFont.systemFont(ofSize: titleFontSize, weight: .medium)
            customTitleLabel.textColor = isPlaceholder ? .systemGray3 : .label
        }

        // 更新 shapeLayer 显示状态
        if isSelected {
            // 选中状态：显示实线描边，隐藏虚线
            selectedShapeLayer.isHidden = false
            todayShapeLayer.isHidden = true
        } else if isToday {
            // 今天状态：显示虚线描边，隐藏实线
            selectedShapeLayer.isHidden = true
            todayShapeLayer.isHidden = false
        } else {
            // 普通状态：隐藏所有描边
            selectedShapeLayer.isHidden = true
            todayShapeLayer.isHidden = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetSlots()
    }

    /// 配置单元格数据
    func configure(with date: Date, events: [Event]) {
        self.currentDate = date
        self.currentEvents = events

        // 配置事件列表
        configureEvents(events: events, date: date)
    }

    /// 配置事件显示
    private func configureEvents(events: [Event], date: Date) {
        resetSlots()

        guard !events.isEmpty else { return }

        // 为每个事件添加位置信息
        let eventsWithPosition = events.map { event -> (event: Event, position: EventPosition) in
            let position = getEventPosition(for: event, on: date)
            return (event: event, position: position)
        }

        let totalCount = eventsWithPosition.count
        let slotLimit = maxVisibleSlots > 0 ? maxVisibleSlots : maxEventCount

        guard slotLimit > 0 else { return }

        var displayItems: [EventDisplayItem] = []

        if totalCount <= slotLimit {
            for item in eventsWithPosition {
                displayItems.append(.event(item.event, item.position))
            }
        } else {
            let eventSlots = max(slotLimit - 1, 0)

            if eventSlots > 0 {
                for index in 0..<min(eventSlots, totalCount) {
                    let item = eventsWithPosition[index]
                    displayItems.append(.event(item.event, item.position))
                }
            }

            let startIndex = min(eventSlots, totalCount)
            if startIndex < totalCount {
                let remainingSlice = eventsWithPosition[startIndex..<totalCount]
                let nonBlankRemaining = remainingSlice.filter { !$0.event.isBlank }

                if nonBlankRemaining.count >= 2 {
                    displayItems.append(.overflow(nonBlankRemaining.count))
                } else if nonBlankRemaining.count == 1,
                          let lastNonBlankEvent = remainingSlice.first(where: { !$0.event.isBlank }) {
                    displayItems.append(.event(lastNonBlankEvent.event, lastNonBlankEvent.position))
                } else if let filler = remainingSlice.first,
                          displayItems.count < slotLimit {
                    displayItems.append(.event(filler.event, filler.position))
                }
            }
        }

        let targetCapacity = max(slotLimit, displayItems.count)
        prepareSlots(capacity: targetCapacity)

        for (index, item) in displayItems.enumerated() where index < eventSlots.count {
            let slot = eventSlots[index]
            switch item {
            case let .event(event, position):
                configure(slot: slot, with: event, position: position, on: date)
            case let .overflow(count):
                slot.configureOverflow(count: count)
            }
        }

        if displayItems.count < eventSlots.count {
            for index in displayItems.count..<eventSlots.count {
                eventSlots[index].reset()
            }
        }
    }

    /// 准备槽位池
    private func prepareSlots(capacity: Int) {
        guard capacity > eventSlots.count else { return }

        let metrics = CustomCalendarCell.layoutMetrics
        for _ in eventSlots.count..<capacity {
            let slot = EventSlotView(slotHeight: metrics.eventSlotHeight)
            eventsStackView.addArrangedSubview(slot)
            slot.reset()
            eventSlots.append(slot)
        }
    }

    /// 重置所有槽位
    private func resetSlots() {
        eventSlots.forEach { $0.reset() }
    }

    /// 配置单个槽位
    private func configure(slot: EventSlotView, with event: Event, position: EventPosition, on date: Date) {
        if event.isBlank {
            slot.configureBlank()
            return
        }

        let originalColor = event.customColor ?? .systemBlue
        let baseColor = desaturateColor(originalColor, by: 0.3)

        if event.title.contains("国庆") {
            let calendar = Calendar.current
            let currentDate = calendar.startOfDay(for: date)
            print("🎨 创建国庆节事件条:")
            print("   日期: \(currentDate)")
            print("   position: start=\(position.isStart), middle=\(position.isMiddle), end=\(position.isEnd)")
        }

        let configuration = makeEventConfiguration(for: event,
                                                    position: position,
                                                    date: date,
                                                    baseColor: baseColor)

        slot.configureEvent(with: configuration)
    }

    private func makeEventConfiguration(for event: Event,
                                        position: EventPosition,
                                        date: Date,
                                        baseColor: UIColor) -> EventSlotConfiguration {
        let calendar = Calendar.current
        let currentDate = calendar.startOfDay(for: date)

        let isSingleDay = !isMultiDayEvent(event)
        let shouldExtendToEdges = !isSingleDay && (
            position.isMiddle ||
            (position.isStart && !position.isEnd) ||
            (position.isEnd && !position.isStart)
        )

        let weekday = calendar.component(.weekday, from: currentDate)
        let firstWeekday = calendar.firstWeekday
        let lastWeekday = firstWeekday == 1 ? 7 : firstWeekday - 1

        var visualStart = true
        var visualEnd = true

        if shouldExtendToEdges {
            visualStart = position.isStart || weekday == firstWeekday
            visualEnd = position.isEnd || weekday == lastWeekday
        }

        if event.title.contains("国庆") {
            print("   isSingleDay: \(isSingleDay)")
            print("   shouldExtendToEdges: \(shouldExtendToEdges)")
            print("   visualStart: \(visualStart), visualEnd: \(visualEnd)")
        }

        let defaultCorners: CACornerMask = [
            .layerMinXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMinYCorner,
            .layerMaxXMaxYCorner
        ]

        let layout = shouldExtendToEdges
            ? layoutForExtendedEvent(visualStart: visualStart, visualEnd: visualEnd)
            : (leading: CGFloat(2), trailing: CGFloat(-2), maskedCorners: defaultCorners)

        let shouldShowText = shouldShowEventText(event: event, date: date, position: position)
        let textColor = getTextColor(for: baseColor)

        var labelMode: EventSlotView.LabelMode = .hidden

        if shouldShowText {
            if shouldExtendToEdges {
                let needExtendText = (position.isStart && !position.isEnd) || (visualStart && !position.isEnd)
                if needExtendText {
                    labelMode = .extendLeading(text: event.title, color: textColor)
                } else {
                    labelMode = .centered(text: event.title, color: textColor)
                }
            } else if position.isStart && !position.isEnd {
                labelMode = .extendLeading(text: event.title, color: textColor)
            } else {
                labelMode = .centered(text: event.title, color: textColor)
            }
        }

        return EventSlotConfiguration(
            backgroundColor: baseColor.withAlphaComponent(0.6),
            leadingInset: layout.leading,
            trailingInset: layout.trailing,
            maskedCorners: layout.maskedCorners,
            labelMode: labelMode
        )
    }

    private func layoutForExtendedEvent(visualStart: Bool,
                                        visualEnd: Bool) -> (leading: CGFloat, trailing: CGFloat, maskedCorners: CACornerMask) {
        switch (visualStart, visualEnd) {
        case (true, false):
            return (leading: 2, trailing: 0, maskedCorners: [.layerMinXMinYCorner, .layerMinXMaxYCorner])
        case (false, true):
            return (leading: 0, trailing: -2, maskedCorners: [.layerMaxXMinYCorner, .layerMaxXMaxYCorner])
        case (false, false):
            return (leading: 0, trailing: 0, maskedCorners: [])
        case (true, true):
            return (leading: 2,
                    trailing: -2,
                    maskedCorners: [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner])
        }
    }

    /// 判断是否为多天事件
    private func isMultiDayEvent(_ event: Event) -> Bool {
        // 对于全天事件，需要特殊处理
        if event.isAllDay {
            let calendar = Calendar.current
            // 对于全天事件，直接比较日期组件，避免时区问题
            let startComponents = calendar.dateComponents([.year, .month, .day], from: event.startDate)
            let endComponents = calendar.dateComponents([.year, .month, .day], from: event.endDate)

            let isMultiDay = startComponents.year != endComponents.year ||
                             startComponents.month != endComponents.month ||
                             startComponents.day != endComponents.day

            if event.title.contains("国庆") {
                print("🔍 isMultiDayEvent 判断(全天事件):")
                print("   事件: \(event.title)")
                print("   开始日期组件: \(startComponents.year!)-\(startComponents.month!)-\(startComponents.day!)")
                print("   结束日期组件: \(endComponents.year!)-\(endComponents.month!)-\(endComponents.day!)")
                print("   是否多天: \(isMultiDay)")
            }

            return isMultiDay
        } else {
            // 非全天事件，使用原有逻辑
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: event.startDate)
            let end = calendar.startOfDay(for: event.endDate)
            return start != end
        }
    }

    /// 判断是否应该显示事件文字
    private func shouldShowEventText(event: Event, date: Date, position: EventPosition) -> Bool {
        // 单天事件总是显示文字
        if !isMultiDayEvent(event) {
            return true
        }

        // 多天事件：在以下情况显示文字
        // 1. 事件的开始日期
        // 2. 每周的开始（周日）且在事件范围内
        let calendar = Calendar.current
        let currentDate = calendar.startOfDay(for: date)
        let eventStart = calendar.startOfDay(for: event.startDate)
        let eventEnd = calendar.startOfDay(for: event.endDate)

        // 如果是事件开始日期，显示文字
        if position.isStart {
            return true
        }

        // 如果是周日（weekday == 1）且在事件范围内，显示文字
        let weekday = calendar.component(.weekday, from: date)
        let isInEventRange = currentDate >= eventStart && currentDate <= eventEnd

        if weekday == 1 && isInEventRange {
            return true
        }

        return false
    }

    /// 获取根据背景色获取合适的文字颜色
    private func getTextColor(for backgroundColor: UIColor) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        backgroundColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.5 ? UIColor.black.withAlphaComponent(0.87) : .white
    }

    /// 降低颜色饱和度
    private func desaturateColor(_ color: UIColor, by percentage: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        // 获取颜色的HSB值
        if color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            // 降低饱和度
            let newSaturation = max(0, saturation * (1 - percentage))
            return UIColor(hue: hue, saturation: newSaturation, brightness: brightness, alpha: alpha)
        }

        // 如果无法获取HSB值，返回原色
        return color
    }

    /// 获取事件在特定日期的位置信息
    private func getEventPosition(for event: Event, on date: Date) -> EventPosition {
        let calendar = Calendar.current

        // 对于全天事件，使用日期组件比较
        if event.isAllDay {
            let currentComponents = calendar.dateComponents([.year, .month, .day], from: date)
            let startComponents = calendar.dateComponents([.year, .month, .day], from: event.startDate)
            let endComponents = calendar.dateComponents([.year, .month, .day], from: event.endDate)

            // 创建仅包含日期的Date对象用于比较
            let currentDate = calendar.date(from: currentComponents)!
            let eventStart = calendar.date(from: startComponents)!
            let eventEnd = calendar.date(from: endComponents)!

            // 调试国庆节事件
            if event.title.contains("国庆") {
                print("🎌 国庆节事件位置判断(全天):")
                print("   事件: \(event.title)")
                print("   当前日期: \(currentComponents.year!)-\(currentComponents.month!)-\(currentComponents.day!)")
                print("   事件开始: \(startComponents.year!)-\(startComponents.month!)-\(startComponents.day!)")
                print("   事件结束: \(endComponents.year!)-\(endComponents.month!)-\(endComponents.day!)")
            }

            // 检查是否为单天事件
            if eventStart == eventEnd {
                if event.title.contains("国庆") {
                    print("   判定为单天全天事件")
                }
                return EventPosition(isStart: true, isMiddle: false, isEnd: true)
            }

            // 多天事件
            let isStart = currentDate == eventStart
            let isEnd = currentDate == eventEnd
            let isMiddle = currentDate > eventStart && currentDate < eventEnd

            if event.title.contains("国庆") {
                print("   位置: isStart=\(isStart), isMiddle=\(isMiddle), isEnd=\(isEnd)")
            }

            return EventPosition(isStart: isStart, isMiddle: isMiddle, isEnd: isEnd)
        } else {
            // 非全天事件，使用原有逻辑
            let currentDate = calendar.startOfDay(for: date)
            let eventStart = calendar.startOfDay(for: event.startDate)
            let eventEnd = calendar.startOfDay(for: event.endDate)

            // 单天事件
            if eventStart == eventEnd {
                return EventPosition(isStart: true, isMiddle: false, isEnd: true)
            }

            // 多天事件
            let isStart = currentDate == eventStart
            let isEnd = currentDate == eventEnd
            let isMiddle = currentDate > eventStart && currentDate < eventEnd

            return EventPosition(isStart: isStart, isMiddle: isMiddle, isEnd: isEnd)
        }
    }
}
