import UIKit
import SnapKit

/// 事件位置信息
struct EventPosition {
    let isStart: Bool
    let isMiddle: Bool
    let isEnd: Bool
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

    /// 最大显示事件数
    private let maxEventCount = 3

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
        eventsStackView.subviews.forEach { container in
            container.subviews.forEach { eventBar in
                eventBar.subviews.forEach { view in
                    if view.tag == 999 {
                        // 这是需要延伸的文字label，提升其层级
                        view.layer.zPosition = 9999
                    }
                }
            }
        }

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

    /// 配置单元格数据
    func configure(with date: Date, events: [Event]) {
        self.currentDate = date
        self.currentEvents = events

        // 配置事件列表
        configureEvents(events: events, date: date)
    }

    /// 配置事件显示
    private func configureEvents(events: [Event], date: Date) {
        // 清空现有事件视图
        eventsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !events.isEmpty else { return }

        // 为每个事件添加位置信息
        // 注意：events 已经在 ViewModel 中排序好了，这里不需要再排序
        let eventsWithPosition = events.map { event -> (event: Event, position: EventPosition) in
            let position = getEventPosition(for: event, on: date)
            return (event: event, position: position)
        }

        // 计算实际显示的事件数量
        let totalCount = eventsWithPosition.count
        var displayCount = min(totalCount, maxEventCount)

        // 如果只剩1个事件未显示，直接显示它而不是显示"+1"
        if totalCount == maxEventCount + 1 {
            displayCount = totalCount  // 显示所有4个事件
        }

        // 显示事件
        for i in 0..<displayCount {
            let item = eventsWithPosition[i]
            let eventBar = createEventBar(for: item.event, date: date, position: item.position)
            eventsStackView.addArrangedSubview(eventBar)
        }

        // 如果还有2个或更多事件未显示，显示 "+n" 指示器
        let remaining = totalCount - displayCount
        if remaining >= 2 {
            // 计算剩余事件中非空白事件的数量
            let remainingEvents = eventsWithPosition[displayCount..<totalCount]
            let nonBlankRemaining = remainingEvents.filter { !$0.event.isBlank }.count

            // 只有当剩余的非空白事件 >= 2 时才显示 "+n"
            if nonBlankRemaining >= 2 {
                let overflowIndicator = createOverflowIndicator(count: nonBlankRemaining)
                eventsStackView.addArrangedSubview(overflowIndicator)
            } else if nonBlankRemaining == 1 {
                // 如果只剩1个非空白事件，找到它并显示
                if let lastNonBlankEvent = remainingEvents.first(where: { !$0.event.isBlank }) {
                    let eventBar = createEventBar(for: lastNonBlankEvent.event, date: date, position: lastNonBlankEvent.position)
                    eventsStackView.addArrangedSubview(eventBar)
                }
            }
        }
    }

    /// 创建事件条
    private func createEventBar(for event: Event, date: Date, position: EventPosition) -> UIView {
        // 如果是空白事件，返回透明的占位视图
        if event.isBlank {
            let container = UIView()
            container.snp.makeConstraints { make in
                make.height.equalTo(14)
            }
            container.backgroundColor = .clear
            return container
        }

        // 获取事件颜色并降低饱和度
        let originalColor = event.customColor ?? .systemBlue
        let eventColor = desaturateColor(originalColor, by: 0.3) // 降低30%饱和度

        let calendar = Calendar.current
        let currentDate = calendar.startOfDay(for: date)

        // 判断是否为真正的多天事件
        let isSingleDay = !isMultiDayEvent(event)

        // 判断是否延伸到边缘（连续事件的中间部分或开始/结束的连接部分）
        let shouldExtendToEdges = !isSingleDay && (position.isMiddle ||
                                                   (position.isStart && !position.isEnd) ||
                                                   (position.isEnd && !position.isStart))

        // 调试国庆节事件
        if event.title.contains("国庆") {
            print("🎨 创建国庆节事件条:")
            print("   日期: \(currentDate)")
            print("   isSingleDay: \(isSingleDay)")
            print("   position: start=\(position.isStart), middle=\(position.isMiddle), end=\(position.isEnd)")
            print("   shouldExtendToEdges: \(shouldExtendToEdges)")
        }

        // 创建事件条视图
        let eventBar = UIView()
        // 降低透明度到0.6，让色块更柔和
        eventBar.backgroundColor = eventColor.withAlphaComponent(0.6)

        if shouldExtendToEdges {
            // 连续事件：创建一个容器来允许超出边界
            let container = UIView()
            container.clipsToBounds = false  // 允许子视图超出边界
            container.snp.makeConstraints { make in
                make.height.equalTo(14)
            }

            container.addSubview(eventBar)
            eventBar.clipsToBounds = false  // 允许事件条的内容（文字）超出边界

            // 根据位置决定延伸方向
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: currentDate)

            // 获取一周的开始和结束（根据系统设置）
            // FSCalendar的firstWeekday: 1=周日, 2=周一, etc.
            let firstWeekday = calendar.firstWeekday  // 系统设置的一周开始
            let lastWeekday = firstWeekday == 1 ? 7 : firstWeekday - 1  // 一周的最后一天

            let isWeekStart = (weekday == firstWeekday)  // 一周的开始
            let isWeekEnd = (weekday == lastWeekday)     // 一周的结束

            // 判断实际的视觉位置
            let visualStart = position.isStart || isWeekStart  // 事件开始或每周开始
            let visualEnd = position.isEnd || isWeekEnd        // 事件结束或每周结束

            eventBar.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview()

                if visualStart && !visualEnd {
                    // 视觉开始位置：左边正常（有内边距），右边延伸
                    make.leading.equalToSuperview().offset(2)
                    make.trailing.equalToSuperview()  // 右边延伸到边缘
                } else if visualEnd && !visualStart {
                    // 视觉结束位置：左边延伸，右边正常（有内边距）
                    make.leading.equalToSuperview()  // 左边延伸到边缘
                    make.trailing.equalToSuperview().offset(-2)
                } else if !visualStart && !visualEnd {
                    // 中间位置：两边都延伸
                    make.leading.equalToSuperview()  // 左边延伸到边缘
                    make.trailing.equalToSuperview()  // 右边延伸到边缘
                } else {
                    // 单独的一天（一周的开始同时也是结束，比如只有一天的事件）
                    make.leading.equalToSuperview().offset(2)
                    make.trailing.equalToSuperview().offset(-2)
                }
            }

            // 设置圆角：根据视觉位置决定哪边有圆角
            eventBar.layer.cornerRadius = 2
            eventBar.layer.maskedCorners = []

            if visualStart {
                // 视觉开始位置：左边有圆角
                eventBar.layer.maskedCorners.insert([.layerMinXMinYCorner, .layerMinXMaxYCorner])
            }
            if visualEnd {
                // 视觉结束位置：右边有圆角
                eventBar.layer.maskedCorners.insert([.layerMaxXMinYCorner, .layerMaxXMaxYCorner])
            }

            // 判断是否显示文字
            let shouldShowText = shouldShowEventText(event: event, date: date, position: position)
            if shouldShowText {
                let label = UILabel()
                label.text = event.title
                label.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
                label.textColor = getTextColor(for: eventColor)

                // 对于连续事件的开始位置或每周的视觉开始位置，允许文字延伸
                // 需要文字延伸的情况：
                // 1. 事件真正的开始且是多天事件
                // 2. 每周的视觉开始（周日）且不是事件的最后一天
                let needExtendText = (position.isStart && !position.isEnd) ||
                                   (visualStart && !position.isEnd)
                if needExtendText {
                    // 连续事件开始或跨周后的开始：文字左对齐，可以延伸到右边
                    label.textAlignment = .left
                    label.lineBreakMode = .byClipping  // 不截断文字，允许超出边界
                    label.clipsToBounds = false  // 允许内容超出边界
                    label.tag = 999  // 标记需要提升层级的label

                    eventBar.addSubview(label)
                    label.snp.makeConstraints { make in
                        make.centerY.equalToSuperview()
                        make.leading.equalToSuperview().offset(4)
                        // 不限制trailing，让文字可以延伸
                        make.width.greaterThanOrEqualTo(200)  // 给足够的宽度显示长文字
                    }
                } else if visualStart && visualEnd {
                    // 一周内的单独一天，或跨周的开始同时也是结束
                    label.textAlignment = .center
                    label.numberOfLines = 1
                    eventBar.addSubview(label)

                    label.snp.makeConstraints { make in
                        make.center.equalToSuperview()
                        make.leading.greaterThanOrEqualToSuperview().offset(2)
                        make.trailing.lessThanOrEqualToSuperview().offset(-2)
                    }
                } else {
                    // 其他情况：居中显示
                    label.textAlignment = .center
                    label.numberOfLines = 1
                    eventBar.addSubview(label)

                    label.snp.makeConstraints { make in
                        make.center.equalToSuperview()
                        make.leading.greaterThanOrEqualToSuperview().offset(2)
                        make.trailing.lessThanOrEqualToSuperview().offset(-2)
                    }
                }
            }

            return container
        } else {
            // 单天事件：创建带内边距的容器
            let container = UIView()
            container.snp.makeConstraints { make in
                make.height.equalTo(14)
            }

            container.addSubview(eventBar)
            eventBar.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview()
                make.leading.equalToSuperview().offset(2)  // 单天事件有内边距
                make.trailing.equalToSuperview().offset(-2)  // 单天事件有内边距
            }
            eventBar.layer.cornerRadius = 2

            // 判断是否显示文字：基于位置信息
            let shouldShowText = shouldShowEventText(event: event, date: date, position: position)

            if shouldShowText {
                let label = UILabel()
                label.text = event.title
                label.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
                label.textColor = getTextColor(for: eventColor)

                // 对于连续事件的开始位置，允许文字延伸
                if position.isStart && !position.isEnd {
                    // 连续事件开始：文字左对齐，可以延伸到右边
                    label.textAlignment = .left
                    label.lineBreakMode = .byClipping  // 不截断文字，允许超出边界
                    label.clipsToBounds = false  // 允许内容超出边界
                    label.tag = 999  // 标记需要提升层级的label

                    eventBar.addSubview(label)
                    label.snp.makeConstraints { make in
                        make.centerY.equalToSuperview()
                        make.leading.equalToSuperview().offset(4)
                        // 不限制trailing，让文字可以延伸
                        make.width.greaterThanOrEqualTo(200)  // 给足够的宽度显示长文字
                    }
                } else {
                    // 单天事件或其他情况：居中显示
                    label.textAlignment = .center
                    label.numberOfLines = 1
                    eventBar.addSubview(label)

                    label.snp.makeConstraints { make in
                        make.center.equalToSuperview()
                        make.leading.greaterThanOrEqualToSuperview().offset(2)
                        make.trailing.lessThanOrEqualToSuperview().offset(-2)
                    }
                }
            }

            return container
        }
    }

    /// 创建溢出指示器 "+n"
    private func createOverflowIndicator(count: Int) -> UIView {
        let container = UIView()
        container.snp.makeConstraints { make in
            make.height.equalTo(14)
        }

        let indicator = UIView()
        // 降低透明度，与事件条保持一致的视觉效果
        indicator.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.2)
        indicator.layer.cornerRadius = 2
        container.addSubview(indicator)

        indicator.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.bottom.equalToSuperview()
            make.leading.equalToSuperview().offset(2)  // 溢出指示器有内边距
            make.trailing.equalToSuperview().offset(-2)  // 溢出指示器有内边距
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
