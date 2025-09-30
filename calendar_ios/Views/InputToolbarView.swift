import UIKit
import SnapKit

/// 自定义输入工具栏视图
/// 参考微信输入框设计，支持文字输入和语音输入切换
/// 支持键盘跟随和安全区域适配
class InputToolbarView: UIView {

    // MARK: - UI组件

    /// 语音/键盘切换按钮
    private let voiceButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "mic"), for: .normal)
        button.tintColor = .label
        return button
    }()

    /// 文本输入框
    private let textField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.backgroundColor = UIColor.systemBackground
        field.layer.cornerRadius = 8
        field.layer.borderWidth = 0.5
        field.layer.borderColor = UIColor.separator.cgColor
        field.font = .systemFont(ofSize: 16)
        field.returnKeyType = .send

        // 设置左边距
        let leftPadding = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        field.leftView = leftPadding
        field.leftViewMode = .always

        // 设置右边距
        let rightPadding = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        field.rightView = rightPadding
        field.rightViewMode = .always

        return field
    }()

    /// 语音按钮（按住说话）
    private let voiceRecordButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.systemBackground
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.separator.cgColor
        button.setTitle("按住说话", for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        button.isHidden = true
        return button
    }()

    /// 日历按钮
    private let calendarButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "calendar"), for: .normal)
        button.tintColor = .label
        return button
    }()

    /// 添加按钮
    private let addButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "plus"), for: .normal)
        button.tintColor = .label
        return button
    }()

    /// 分隔线
    private let separatorLine: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.separator
        return view
    }()

    /// 背景容器视图（用于填充安全区）
    private let backgroundView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemBackground
        return view
    }()

    // MARK: - 属性

    /// 当前是否为语音模式
    private var isVoiceMode = false

    /// 选中的日期
    var selectedDate: Date? {
        didSet {
            updatePlaceholder()
        }
    }

    /// 文本输入回调
    var onTextSubmit: ((String) -> Void)?

    /// 语音录制开始回调
    var onVoiceRecordStart: (() -> Void)?

    /// 语音录制结束回调
    var onVoiceRecordEnd: (() -> Void)?

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI设置

    /// 设置UI布局
    private func setupUI() {
        // 设置背景色
        backgroundColor = .systemBackground

        // 添加子视图
        addSubview(backgroundView)
        addSubview(separatorLine)
        addSubview(voiceButton)
        addSubview(textField)
        addSubview(voiceRecordButton)
        addSubview(calendarButton)
        addSubview(addButton)

        // 背景视图约束（延伸到视图底部，填充安全区）
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 分隔线约束
        separatorLine.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(0.5)
        }

        // 语音切换按钮约束
        voiceButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.top.equalToSuperview().offset(7)
            make.width.height.equalTo(40)
        }

        // 文本输入框约束
        textField.snp.makeConstraints { make in
            make.leading.equalTo(voiceButton.snp.trailing).offset(8)
            make.top.equalToSuperview().offset(7)
            make.trailing.equalTo(calendarButton.snp.leading).offset(-8)
            make.height.equalTo(40)
        }

        // 语音录制按钮约束（与文本输入框位置相同）
        voiceRecordButton.snp.makeConstraints { make in
            make.leading.equalTo(voiceButton.snp.trailing).offset(8)
            make.top.equalToSuperview().offset(7)
            make.trailing.equalTo(calendarButton.snp.leading).offset(-8)
            make.height.equalTo(40)
        }

        // 日历按钮约束
        calendarButton.snp.makeConstraints { make in
            make.trailing.equalTo(addButton.snp.leading).offset(-1)
            make.top.equalToSuperview().offset(7)
            make.width.height.equalTo(40)
        }

        // 添加按钮约束
        addButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-8)
            make.top.equalToSuperview().offset(7)
            make.width.height.equalTo(40)
        }

        // 设置TextField代理
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        // 按钮点击事件
        voiceButton.addTarget(self, action: #selector(toggleVoiceMode), for: .touchUpInside)

        // 更新提示语
        updatePlaceholder()
    }

    /// 设置手势
    private func setupGestures() {
        // 长按语音录制手势
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleVoiceRecordGesture(_:)))
        longPress.minimumPressDuration = 0.1
        voiceRecordButton.addGestureRecognizer(longPress)
    }

    // MARK: - 交互处理

    /// 切换语音/文字输入模式
    @objc private func toggleVoiceMode() {
        isVoiceMode.toggle()

        if isVoiceMode {
            // 切换到语音模式
            voiceButton.setImage(UIImage(named: "keyboard"), for: .normal)
            textField.isHidden = true
            voiceRecordButton.isHidden = false
            textField.resignFirstResponder()
        } else {
            // 切换到文字模式
            voiceButton.setImage(UIImage(named: "mic"), for: .normal)
            textField.isHidden = false
            voiceRecordButton.isHidden = true
        }
    }

    /// 处理语音录制手势
    @objc private func handleVoiceRecordGesture(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            voiceRecordButton.backgroundColor = UIColor.systemGray5
            onVoiceRecordStart?()
        case .ended, .cancelled, .failed:
            voiceRecordButton.backgroundColor = UIColor.systemBackground
            onVoiceRecordEnd?()
        default:
            break
        }
    }

    /// 文本框内容变化
    @objc private func textFieldDidChange() {
        // 可以在这里处理文本变化事件
    }

    /// 更新输入框提示语
    private func updatePlaceholder() {
        if let date = selectedDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日"
            let dateString = formatter.string(from: date)
            textField.placeholder = "在\(dateString)添加事件"
        } else {
            textField.placeholder = "添加事件"
        }
    }

    // MARK: - 公开方法

    /// 获取工具栏内容高度（不含安全区）
    /// - Returns: 内容区域高度
    func getContentHeight() -> CGFloat {
        return 54
    }

    /// 清空输入框
    func clearTextField() {
        textField.text = ""
    }

    /// 获取当前输入的文本
    func getCurrentText() -> String {
        return textField.text ?? ""
    }
}

// MARK: - UITextFieldDelegate

extension InputToolbarView: UITextFieldDelegate {

    /// 处理return键点击
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let text = textField.text, !text.isEmpty else {
            return false
        }

        // 触发提交回调
        onTextSubmit?(text)

        // 清空输入框
        textField.text = ""
        textField.resignFirstResponder()

        return true
    }
}
