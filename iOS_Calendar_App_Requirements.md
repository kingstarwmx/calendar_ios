# iOS日历应用转换需求文档

## 项目概述

本文档详细描述了从Flutter日历应用转换为原生iOS应用的功能需求和技术规范。

### 技术栈
- **平台**: iOS (Swift + UIKit)
- **自动布局**: SnapKit
- **数据存储**: Core Data
- **日历集成**: EventKit框架
- **架构模式**: MVVM + Combine
- **最低支持版本**: iOS 14.0+

## 模块划分与实现需求

### 1. 核心数据模型 (Models)

#### 1.1 Event模型
```swift
// 对应Flutter中的Event类
class Event {
    var id: String              // 事件唯一标识
    var title: String           // 事件标题
    var startDate: Date         // 开始时间
    var endDate: Date           // 结束时间
    var isAllDay: Bool          // 是否全天事件
    var location: String        // 事件地点
    var calendarId: String      // 所属日历ID
    var description: String?    // 事件描述
    var customColor: UIColor?   // 自定义颜色
    var recurrenceRule: String? // 重复规则
    var reminders: [Date]       // 提醒时间
    var url: String?            // 事件链接
    var calendarName: String?   // 日历名称
    var isFromDeviceCalendar: Bool // 是否来自设备日历
    var deviceEventId: String?  // 设备日历事件ID
}
```

#### 1.2 CalendarViewMode枚举
```swift
enum CalendarViewMode {
    case collapsed  // 收缩模式(显示一行)
    case normal     // 普通模式(显示完整月份)
    case expanded   // 展开模式(最大化日历)
}
```

#### 1.3 RepeatRule模型
```swift
// 重复规则配置
struct RepeatRule {
    var frequency: RepeatFrequency
    var interval: Int
    var endDate: Date?
    var count: Int?
}
```

### 2. 数据层 (Data Layer)

#### 2.1 数据库管理 (DatabaseHelper)
**功能需求:**
- 使用Core Data管理本地事件数据
- 实现事件的增删改查操作
- 数据版本迁移支持
- 批量操作优化

**核心方法:**
```swift
class DatabaseHelper {
    func saveEvent(_ event: Event) async throws
    func deleteEvent(id: String) async throws
    func updateEvent(_ event: Event) async throws
    func fetchEvents(for date: Date) async -> [Event]
    func fetchEventsInRange(start: Date, end: Date) async -> [Event]
}
```

#### 2.2 设备日历服务 (DeviceCalendarService)
**功能需求:**
- 使用EventKit框架访问系统日历
- 请求日历访问权限
- 同步系统日历事件到应用
- 双向同步支持

**核心方法:**
```swift
class DeviceCalendarService {
    func requestCalendarPermission() async -> Bool
    func fetchDeviceEvents() async throws -> [Event]
    func syncToDeviceCalendar(_ event: Event) async throws
    func removeFromDeviceCalendar(eventId: String) async throws
}
```

#### 2.3 日历服务 (CalendarService)
**功能需求:**
- 统一的日历数据管理接口
- 合并本地和设备日历数据
- 数据缓存策略
- 冲突解决机制

### 3. 状态管理层 (ViewModels)

#### 3.1 EventProvider (EventViewModel)
**功能需求:**
- 管理所有事件相关状态
- 处理事件的增删改查业务逻辑
- 日期选择和月份切换
- 视图模式切换

**核心属性和方法:**
```swift
class EventViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var selectedDate: Date = Date()
    @Published var currentMonth: Date = Date()
    @Published var viewMode: CalendarViewMode = .normal

    func loadEvents() async
    func addEvent(_ event: Event) async
    func updateEvent(_ event: Event) async
    func deleteEvent(id: String) async
    func getEventsForDate(_ date: Date) -> [Event]
    func goToToday()
    func setCurrentMonth(_ month: Date)
    func setSelectedDate(_ date: Date)
    func setViewMode(_ mode: CalendarViewMode)
    func syncWithDeviceCalendar() async
}
```

#### 3.2 ThemeProvider (ThemeViewModel)
**功能需求:**
- 管理应用主题状态
- 支持亮色/暗色主题切换
- 主题设置持久化

```swift
class ThemeViewModel: ObservableObject {
    @Published var isDarkMode: Bool = false

    func toggleTheme()
    func setTheme(isDark: Bool)
}
```

### 4. 用户界面层 (Views) - 基于FSCalendar库

#### 4.1 主日历界面 (CalendarViewController) - 集成FSCalendar
**功能需求:**
- 基于FSCalendarScopeExampleViewController实现三种视图模式
- 实现FSCalendarScope的Month/Week/MaxHeight切换
- 自定义滚动动画和手势处理
- 事件列表显示
- 响应式布局适配

**核心组件集成:**
```swift
class CalendarViewController: UIViewController {
    // FSCalendar主组件
    @IBOutlet weak var calendar: FSCalendar!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var calendarHeightConstraint: NSLayoutConstraint!

    // 手势处理
    private var scopeGesture: UIPanGestureRecognizer!

    // 事件数据
    private var eventViewModel: EventViewModel!
    private var dateFormatter: DateFormatter!

    // UI组件
    private var floatingActionButton: UIButton!
}
```

**FSCalendar配置要求:**
```swift
// 初始化配置
calendar.placeholderType = .none
calendar.scope = .week  // 默认周视图
calendar.maxHeight = 820.0
calendar.delegate = self
calendar.dataSource = self

// 手势集成
let panGesture = UIPanGestureRecognizer(target: calendar, action: #selector(FSCalendar.handleScopeGesture(_:)))
view.addGestureRecognizer(panGesture)
tableView.panGestureRecognizer.require(toFail: panGesture)
```

**布局要求:**
- 使用SnapKit约束FSCalendar和TableView
- 支持安全区域适配
- 动态高度调整基于calendarHeightConstraint
- 流畅的Scope过渡动画

#### 4.2 FSCalendar集成 - 替代自定义日历视图
**FSCalendar核心功能:**
- ✅ 内置月份网格显示
- ✅ 内置日期选择交互
- ✅ 内置跨月日期显示
- ✅ 内置手势响应
- ✅ 三种Scope模式切换

**需要定制的FSCalendar组件:**
1. **FSCalendarCell定制** - 匹配Flutter设计
2. **FSCalendarAppearance配置** - 主题适配
3. **事件指示器定制** - 事件数量和颜色显示

#### 4.3 自定义FSCalendarCell - 匹配Flutter效果
**定制需求:**
基于现有FSCalendarCell类，需要修改以实现Flutter中CalendarCell的精确设计效果。

**Flutter CalendarCell UI规则分析:**

1. **Cell边框状态规则:**
   - 选中状态: 虚线边框 + 8pt圆角 (无背景填充)
   - 今天状态: 实线边框 + 8pt圆角 (无背景填充)
   - 普通状态: 无边框，透明背景

2. **布局结构:**
   - 日期数字在顶部固定24pt高度
   - 下方垂直排列事件色块
   - 每个事件色块高度9pt，垂直间距1pt

**FSCalendarCell修改要点:**
```objectivec
// 需要在FSCalendarCell.m中修改的关键部分:

// 1. layoutSubviews - 重新设计布局和边框效果
- (void)layoutSubviews {
    [super layoutSubviews];

    // 日期标签固定在顶部 24pt 高度
    _titleLabel.frame = CGRectMake(
        self.preferredTitleOffset.x,
        8.0 + self.preferredTitleOffset.y,
        self.contentView.fs_width,
        24.0
    );

    // 事件区域在日期下方
    CGFloat eventTop = CGRectGetMaxY(_titleLabel.frame) + 4.0;
    CGFloat eventHeight = self.contentView.fs_height - eventTop - 4.0;

    // 重新布局事件色块容器
    [self layoutEventStackInFrame:CGRectMake(2, eventTop, self.contentView.fs_width - 4, eventHeight)];

    // 边框效果：替换原有的shapeLayer实现
    [self updateCellBorderForState];
}

// 2. 新增边框状态更新方法
- (void)updateCellBorderForState {
    // 移除原有的圆形选中背景
    _shapeLayer.fillColor = [UIColor clearColor].CGColor;
    _shapeLayer.frame = self.contentView.bounds;

    if (self.selected) {
        // 选中状态：虚线边框
        _shapeLayer.strokeColor = self.calendar.appearance.selectionColor.CGColor;
        _shapeLayer.lineWidth = 1.0;
        _shapeLayer.lineDashPattern = @[@3, @3];  // 虚线模式
        _shapeLayer.opacity = 1.0;
    } else if (self.dateIsToday) {
        // 今天状态：实线边框
        _shapeLayer.strokeColor = self.calendar.appearance.todayColor.CGColor;
        _shapeLayer.lineWidth = 1.0;
        _shapeLayer.lineDashPattern = nil;  // 实线
        _shapeLayer.opacity = 1.0;
    } else {
        // 普通状态：无边框
        _shapeLayer.opacity = 0.0;
    }

    // 圆角矩形路径
    CGPathRef path = [UIBezierPath bezierPathWithRoundedRect:_shapeLayer.bounds
                                                cornerRadius:8.0].CGPath;
    _shapeLayer.path = path;
}
```

**事件色块显示复杂规则实现:**

```objectivec
// 3. 事件色块显示组件
@interface EventBarView : UIView
@property (strong, nonatomic) UIColor *eventColor;
@property (strong, nonatomic) NSString *eventTitle;
@property (assign, nonatomic) BOOL isSingleDay;
@property (assign, nonatomic) BOOL isStart;
@property (assign, nonatomic) BOOL isMiddle;
@property (assign, nonatomic) BOOL isEnd;
@property (assign, nonatomic) BOOL shouldShowText;
@end

@implementation EventBarView

- (void)layoutSubviews {
    [super layoutSubviews];

    // 根据事件类型决定圆角
    CALayer *layer = self.layer;
    if (self.isSingleDay) {
        // 单天事件：四周圆角，左右边距
        layer.cornerRadius = 2.0;
        layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
                             kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    } else {
        // 连续事件：根据位置决定圆角
        CACornerMask corners = 0;
        if (self.isStart) {
            corners |= kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;  // 左侧圆角
        }
        if (self.isEnd) {
            corners |= kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;  // 右侧圆角
        }
        layer.maskedCorners = corners;
        layer.cornerRadius = corners ? 2.0 : 0.0;
    }

    layer.backgroundColor = [self.eventColor colorWithAlphaComponent:0.9].CGColor;
}

@end

// 4. 事件数据配置接口
@interface FSCalendarCell (EventConfiguration)
- (void)configureWithEvents:(NSArray<Event *> *)events
                    forDate:(NSDate *)date
                   viewMode:(CalendarViewMode)viewMode;
@end

@implementation FSCalendarCell (EventConfiguration)

- (void)configureWithEvents:(NSArray<Event *> *)events
                    forDate:(NSDate *)date
                   viewMode:(CalendarViewMode)viewMode {

    // 清除现有事件视图
    [self clearEventViews];

    // 排序事件：连续事件优先
    NSArray *sortedEvents = [self sortEventsByPriority:events forDate:date];

    // 根据视图模式确定最大显示数量
    NSInteger maxEventCount = [self maxEventCountForViewMode:viewMode];

    // 创建事件色块
    [self createEventBarsWithEvents:sortedEvents
                            maxCount:maxEventCount
                            viewMode:viewMode
                             forDate:date];
}

- (NSArray *)sortEventsByPriority:(NSArray<Event *> *)events forDate:(NSDate *)date {
    return [events sortedArrayUsingComparator:^NSComparisonResult(Event *a, Event *b) {
        BOOL isMultiDayA = [self isRealMultiDayEvent:a];
        BOOL isMultiDayB = [self isRealMultiDayEvent:b];

        // 连续事件优先
        if (isMultiDayA && !isMultiDayB) return NSOrderedAscending;
        if (!isMultiDayA && isMultiDayB) return NSOrderedDescending;

        // 相同类型按开始时间排序
        return [a.startDate compare:b.startDate];
    }];
}

- (void)createEventBarsWithEvents:(NSArray *)events
                         maxCount:(NSInteger)maxCount
                         viewMode:(CalendarViewMode)viewMode
                          forDate:(NSDate *)date {

    CGFloat barHeight = 9.0;
    CGFloat verticalSpacing = 1.0;
    CGFloat horizontalMargin = 2.0;

    NSInteger displayCount = MIN(events.count, maxCount == -1 ? events.count : maxCount - 1);

    for (NSInteger i = 0; i < displayCount; i++) {
        Event *event = events[i];

        // 计算事件位置信息
        EventPosition position = [self calculateEventPosition:event forDate:date];

        // 创建事件色块
        EventBarView *eventBar = [[EventBarView alloc] init];
        eventBar.eventColor = event.customColor ?: [UIColor systemBlueColor];
        eventBar.eventTitle = event.title;
        eventBar.isSingleDay = position.isSingleDay;
        eventBar.isStart = position.isStart;
        eventBar.isEnd = position.isEnd;
        eventBar.isMiddle = position.isMiddle;
        eventBar.shouldShowText = [self shouldShowTextForEvent:event
                                                       atDate:date
                                                     position:position
                                                     viewMode:viewMode];

        // 设置事件条框架
        CGFloat y = CGRectGetMaxY(_titleLabel.frame) + 4.0 + i * (barHeight + verticalSpacing);
        CGFloat x = position.shouldExtendToEdges ? 0 : horizontalMargin;
        CGFloat width = position.shouldExtendToEdges ?
                       self.contentView.bounds.size.width :
                       self.contentView.bounds.size.width - 2 * horizontalMargin;

        eventBar.frame = CGRectMake(x, y, width, barHeight);
        [self.contentView addSubview:eventBar];
    }

    // 如果有溢出事件，显示"+n"指示器
    if (maxCount != -1 && events.count > maxCount - 1) {
        [self createOverflowIndicatorWithCount:events.count - (maxCount - 1)
                                       atIndex:maxCount - 1];
    }
}

@end
```

**文字显示策略实现:**
```objectivec
- (BOOL)shouldShowTextForEvent:(Event *)event
                        atDate:(NSDate *)date
                      position:(EventPosition)position
                      viewMode:(CalendarViewMode)viewMode {

    // 展开模式：所有事件显示文字
    if (viewMode == CalendarViewModeExpanded) {
        return YES;
    }

    // 设备日历全天事件的特殊规则
    if (event.isAllDay && event.isFromDeviceCalendar) {
        if (position.isSingleDay) {
            return YES;  // 单天事件总是显示
        } else {
            // 多天事件：在开始日期或周日显示
            NSCalendar *calendar = [NSCalendar currentCalendar];
            NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:date];

            return position.isStart || (weekday == 1);  // 周日 = 1
        }
    }

    // 其他事件：只在开始位置显示
    return position.isStart;
}
```

#### 4.4 FSCalendarAppearance主题配置
**主题适配需求:**
```swift
// 在ViewController中配置FSCalendar外观
private func configureCalendarAppearance() {
    let appearance = calendar.appearance

    // 基础颜色配置
    appearance.titleDefaultColor = UIColor.label
    appearance.titleSelectionColor = UIColor.systemBackground
    appearance.titleTodayColor = UIColor.systemBlue

    // 选中状态配置
    appearance.selectionColor = UIColor.systemBlue
    appearance.todayColor = UIColor.systemBlue.withAlphaComponent(0.3)
    appearance.borderRadius = 8.0  // 圆角矩形

    // 事件指示器配置
    appearance.eventDefaultColor = UIColor.systemBlue
    appearance.eventSelectionColor = UIColor.white

    // 字体配置
    appearance.titleFont = UIFont.systemFont(ofSize: 16, weight: .medium)
    appearance.subtitleFont = UIFont.systemFont(ofSize: 12, weight: .regular)

    // 头部配置
    appearance.headerTitleColor = UIColor.label
    appearance.headerTitleFont = UIFont.systemFont(ofSize: 18, weight: .semibold)
    appearance.weekdayTextColor = UIColor.secondaryLabel
}
```

#### 4.5 FSCalendar代理实现
**数据源实现:**
```swift
extension CalendarViewController: FSCalendarDataSource {

    // 事件数量配置
    func calendar(_ calendar: FSCalendar, numberOfEventsFor date: Date) -> Int {
        return eventViewModel.getEventsForDate(date).count
    }

    // 自定义Cell
    func calendar(_ calendar: FSCalendar, cellFor date: Date, at position: FSCalendarMonthPosition) -> FSCalendarCell {
        let cell = calendar.dequeueReusableCell(withIdentifier: "CustomEventCell", for: date, at: position)
        let events = eventViewModel.getEventsForDate(date)
        cell.configureWithEvents(events)
        return cell
    }

    // 日期范围
    func minimumDate(for calendar: FSCalendar) -> Date {
        return Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
    }

    func maximumDate(for calendar: FSCalendar) -> Date {
        return Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
    }
}
```

**代理实现:**
```swift
extension CalendarViewController: FSCalendarDelegate {

    // 日期选择
    func calendar(_ calendar: FSCalendar, didSelect date: Date, at monthPosition: FSCalendarMonthPosition) {
        eventViewModel.setSelectedDate(date)
        updateEventList(for: date)

        // 跨月跳转
        if monthPosition == .next || monthPosition == .previous {
            calendar.setCurrentPage(date, animated: true)
        }
    }

    // Scope变化处理
    func calendar(_ calendar: FSCalendar, boundingRectWillChange bounds: CGRect, animated: Bool) {
        calendarHeightConstraint.constant = bounds.height
        view.layoutIfNeeded()

        // 更新视图模式
        let newMode: CalendarViewMode
        switch calendar.scope {
        case .month:
            newMode = .normal
        case .week:
            newMode = .collapsed
        case .maxHeight:
            newMode = .expanded
        @unknown default:
            newMode = .normal
        }
        eventViewModel.setViewMode(newMode)
    }

    // 月份切换
    func calendarCurrentPageDidChange(_ calendar: FSCalendar) {
        let newMonth = calendar.currentPage
        eventViewModel.setCurrentMonth(newMonth)
        updateMonthEvents()
    }
}
```

#### 4.6 事件列表视图 (EventListView)
**功能需求:**
- 当日事件列表显示
- 事件卡片设计
- 空状态处理
- 滚动性能优化

```swift
class EventListView: UIView {
    private var tableView: UITableView
    private var emptyStateView: UIView

    func updateEvents(_ events: [Event], for date: Date)
}
```

#### 4.7 添加事件界面 (AddEventViewController)
**功能需求:**
- 事件信息输入表单
- 日期时间选择器
- 重复规则设置
- 颜色选择
- 表单验证

**表单字段:**
```swift
class AddEventViewController: UIViewController {
    @IBOutlet weak var titleTextField: UITextField
    @IBOutlet weak var startDatePicker: UIDatePicker
    @IBOutlet weak var endDatePicker: UIDatePicker
    @IBOutlet weak var allDaySwitch: UISwitch
    @IBOutlet weak var locationTextField: UITextField
    @IBOutlet weak var descriptionTextView: UITextView
    @IBOutlet weak var colorSelectionView: ColorSelectionView
    @IBOutlet weak var repeatSettingsView: RepeatSettingsView
}
```

### 5. 自定义组件库

#### 5.1 颜色选择器 (ColorPickerView)
**功能需求:**
- 预设颜色选择
- 自定义颜色支持
- 选中状态指示

#### 5.2 重复设置视图 (RepeatSettingsView)
**功能需求:**
- 重复频率选择(不重复、每天、每周、每月、每年)
- 自定义重复间隔
- 结束条件设置
- 复杂重复规则(对应Flutter的custom_repeat_screen)

#### 5.3 日期选择器 (CustomDatePickerView)
**功能需求:**
- 增强型日期选择
- 快速跳转到今天
- 月份年份快速选择

### 6. 工具类 (Utilities)

#### 6.1 应用颜色管理 (AppColors)
```swift
struct AppColors {
    static let primary = UIColor.systemBlue
    static let background = UIColor.systemBackground
    static let surface = UIColor.secondarySystemBackground
    // ... 更多颜色定义
}
```

#### 6.2 日志系统 (Logger)
```swift
class Logger {
    enum Level {
        case debug, info, warning, error
    }

    static func log(_ message: String, level: Level)
}
```

#### 6.3 本地化支持 (Localizations)
**需要本地化的文本:**
- 界面标签和按钮文字
- 错误提示信息
- 日期格式化
- 支持中文和英文

### 7. 权限和集成

#### 7.1 系统权限
- 日历访问权限 (EventKit)
- 通知权限 (用户提醒功能)

#### 7.2 系统集成
- 与iOS系统日历应用的数据同步
- 支持Siri快捷指令
- 小组件支持(Widget Extension)

### 8. 性能优化需求

#### 8.1 内存管理
- 页面缓存策略
- 图片和视图的懒加载
- 内存警告处理

#### 8.2 渲染优化
- 滚动性能优化
- 动画流畅度保证
- 大量事件显示优化

#### 8.3 数据加载
- 异步数据加载
- 分页加载策略
- 缓存机制

### 9. 架构设计

#### 9.1 MVVM架构
```
View (UIViewController/UIView)
     ↕
ViewModel (ObservableObject)
     ↕
Model (Data Layer)
```

#### 9.2 依赖注入
- 服务层的依赖管理
- 测试友好的架构设计

#### 9.3 数据流
```
UI Event → ViewModel → Service → Database/API
        ← ViewModel ← Service ← Database/API
```

### 10. 测试策略

#### 10.1 单元测试
- ViewModel逻辑测试
- 数据模型测试
- 服务层测试

#### 10.2 UI测试
- 关键用户流程测试
- 界面响应测试

### 11. 开发优先级

#### Phase 1: 核心功能 (MVP)
1. 基础数据模型定义
2. Core Data集成
3. 基础日历视图显示
4. 事件增删改功能
5. 简单的月份切换

#### Phase 2: 高级功能
1. 设备日历同步
2. 复杂视图模式切换
3. 重复事件支持
4. 高级UI动画

#### Phase 3: 优化和扩展
1. 性能优化
2. 本地化完善
3. 小组件支持
4. 高级手势支持

## 技术实现要点

### 1. SnapKit布局示例
```swift
calendarView.snp.makeConstraints { make in
    make.top.equalTo(view.safeAreaLayoutGuide)
    make.leading.trailing.equalToSuperview()
    make.height.equalTo(300)
}
```

### 2. Combine响应式编程
```swift
viewModel.$selectedDate
    .sink { [weak self] date in
        self?.updateEventList(for: date)
    }
    .store(in: &cancellables)
```

### 3. Core Data集成
```swift
// 事件实体定义
@objc(EventEntity)
class EventEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var title: String
    @NSManaged var startDate: Date
    // ... 其他属性
}
```

## FSCalendar库集成专项需求

### FSCalendar架构分析
基于已提供的FSCalendar库(`/Users/star/Desktop/Projects/Calendar/calendar_ios/calendar_ios/Libs/FSCalendar`)，该库提供了完整的日历功能，无需重新实现复杂的日历逻辑。

### 核心优势
1. **三种Scope模式**: FSCalendarScopeMonth/Week/MaxHeight对应Flutter的normal/collapsed/expanded
2. **内置手势支持**: 自动处理视图模式切换的手势和动画
3. **高度自适应**: 自动计算和调整日历高度
4. **事件系统**: 内置事件指示器和自定义Cell支持
5. **成熟稳定**: 经过广泛使用和测试的第三方库

### 集成策略

#### 1. 主控制器基于FSCalendarScopeExampleViewController
```swift
// 直接基于示例控制器进行定制
class CalendarViewController: UIViewController {
    @IBOutlet weak var calendar: FSCalendar!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var calendarHeightConstraint: NSLayoutConstraint!

    // 集成EventViewModel
    private var eventViewModel: EventViewModel!

    // 保持FSCalendar的原有手势和KVO监听逻辑
    private var scopeGesture: UIPanGestureRecognizer!
}
```

#### 2. FSCalendarCell定制重点
**不改变FSCalendar库的核心逻辑，只定制Cell的视觉表现:**

```objectivec
// 在FSCalendarCell.m中的关键修改点:

// 1. layoutSubviews - 调整布局以匹配Flutter效果
- (void)layoutSubviews {
    [super layoutSubviews];

    // 日期数字固定顶部24pt
    CGFloat titleTop = 8.0;
    _titleLabel.frame = CGRectMake(0, titleTop, self.contentView.fs_width, 24.0);

    // 事件区域在日期下方
    CGFloat eventTop = CGRectGetMaxY(_titleLabel.frame) + 4.0;
    CGFloat eventHeight = self.contentView.fs_height - eventTop - 4.0;

    // 重新设计事件指示器为垂直条状
    [self layoutEventBarsInFrame:CGRectMake(4, eventTop, self.contentView.fs_width - 8, eventHeight)];

    // 选中背景改为圆角矩形
    _shapeLayer.frame = self.contentView.bounds;
    _shapeLayer.path = [UIBezierPath bezierPathWithRoundedRect:_shapeLayer.bounds cornerRadius:8.0].CGPath;
}

// 2. 新增事件条布局方法
- (void)layoutEventBarsInFrame:(CGRect)frame {
    // 移除原有的点状指示器逻辑
    // 添加垂直排列的事件条
    // 支持连续事件的特殊显示
}
```

#### 3. 事件数据桥接
```swift
// 扩展FSCalendarCell以支持Event模型
extension FSCalendarCell {
    func configure(with events: [Event], for date: Date) {
        // 处理事件数据并更新显示
        // 区分连续事件和单天事件
        // 应用自定义颜色
    }
}

// 在FSCalendarDataSource中提供事件数据
func calendar(_ calendar: FSCalendar, cellFor date: Date, at position: FSCalendarMonthPosition) -> FSCalendarCell {
    let cell = calendar.dequeueReusableCell(withIdentifier: "cell", for: date, at: position)
    let events = eventViewModel.getEventsForDate(date)
    cell.configure(with: events, for: date)
    return cell
}
```

#### 4. 视图模式映射
```swift
// FSCalendarScope与CalendarViewMode的映射关系
enum CalendarViewMode {
    case collapsed  // -> FSCalendarScopeWeek
    case normal     // -> FSCalendarScopeMonth
    case expanded   // -> FSCalendarScopeMaxHeight
}

// 在delegate中同步状态
func calendar(_ calendar: FSCalendar, boundingRectWillChange bounds: CGRect, animated: Bool) {
    calendarHeightConstraint.constant = bounds.height

    let newMode: CalendarViewMode
    switch calendar.scope {
    case .week: newMode = .collapsed
    case .month: newMode = .normal
    case .maxHeight: newMode = .expanded
    }

    eventViewModel.setViewMode(newMode)
    view.layoutIfNeeded()
}
```

### 必要的FSCalendar源码修改

#### 1. FSCalendarCell.h 添加事件接口
```objectivec
// 在FSCalendarCell.h中添加事件配置接口
@interface FSCalendarCell (EventConfiguration)
- (void)configureWithEventData:(NSArray *)eventData forDate:(NSDate *)date;
- (void)updateEventDisplayMode:(NSInteger)mode;
@end
```

#### 2. FSCalendarCell.m 重构事件显示
```objectivec
// 替换原有的FSCalendarEventIndicator实现
// 改为支持垂直事件条的EventStackView
@interface FSCalendarCell ()
@property (weak, nonatomic) UIStackView *eventStackView;
@property (strong, nonatomic) NSMutableArray<UIView *> *eventBars;
@end

// 在commonInit中初始化事件条容器
- (void)commonInit {
    // ... 原有代码 ...

    // 创建事件条容器
    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 2.0;
    stackView.distribution = UIStackViewDistributionFillEqually;
    [self.contentView addSubview:stackView];
    self.eventStackView = stackView;

    self.eventBars = [NSMutableArray array];
}
```

#### 3. 支持动态高度的改进
```objectivec
// 在FSCalendar主类中添加动态高度支持
- (CGFloat)preferredRowHeightForScope:(FSCalendarScope)scope {
    switch (scope) {
        case FSCalendarScopeWeek:
            return 60.0;  // collapsed模式高度
        case FSCalendarScopeMonth:
            return 80.0;  // normal模式高度
        case FSCalendarScopeMaxHeight:
            return 120.0; // expanded模式高度
    }
}
```

### 开发工作流

#### Phase 1: 基础集成 (1-2周)
1. 创建基于FSCalendarScopeExampleViewController的主控制器
2. 集成EventViewModel和基础数据绑定
3. 配置FSCalendarAppearance以匹配设计规范
4. 实现基础的日期选择和事件列表联动

#### Phase 2: Cell定制 (2-3周)
1. 修改FSCalendarCell.m实现Flutter样式的Cell布局
2. 实现事件条显示组件EventBarView
3. 添加连续事件的特殊处理逻辑
4. 优化选中状态和今天标识的视觉效果

#### Phase 3: 高级功能 (2-3周)
1. 实现设备日历同步
2. 添加重复事件支持
3. 完善手势交互和动画效果
4. 性能优化和错误处理

### 技术风险评估

#### 低风险项
- ✅ FSCalendar基础功能成熟稳定
- ✅ 手势和动画逻辑已经实现
- ✅ 三种视图模式切换机制完整

#### 中等风险项
- ⚠️ FSCalendarCell的深度定制可能影响库的稳定性
- ⚠️ 事件条的垂直布局需要重构现有EventIndicator逻辑
- ⚠️ 连续事件的显示逻辑较为复杂

#### 缓解措施
1. 在修改FSCalendar源码前创建完整备份
2. 采用渐进式开发，先实现基础功能再添加高级特性
3. 保持FSCalendar核心API不变，只修改显示逻辑
4. 充分测试各种边界情况和用户交互场景

## 设计规范

### 1. 视觉设计
- 遵循iOS Human Interface Guidelines
- 支持iOS暗色模式
- 使用系统字体和颜色
- 保持与系统日历应用的视觉一致性

### 2. 交互设计
- 原生iOS手势支持
- 符合iOS用户习惯的导航模式
- 无障碍功能支持

### 3. 动画效果
- 使用UIKit动画API
- 60fps流畅动画
- 适当的缓动函数

这份需求文档涵盖了从Flutter到iOS原生应用转换的所有核心功能和技术要求。开发团队可以基于此文档进行详细的技术设计和开发计划制定。