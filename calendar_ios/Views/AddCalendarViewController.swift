import UIKit
import SnapKit
import EventKit

struct CalendarColorOption: Equatable {
    let id: String
    let name: String
    let color: UIColor

    static let predefined: [CalendarColorOption] = [
        ("樱桃红", "#FF3D3D"),
        ("玫瑰粉", "#F74F6D"),
        ("薄荷绿", "#00B2A7"),
        ("松树绿", "#005F3D"),
        ("橄榄绿", "#8B8D4A"),
        ("苍穹蓝", "#0095D9"),
        ("夕阳橙", "#FFA600"),
        ("深海蓝", "#1A2636"),
        ("酒红色", "#8D3B3B"),
        ("钴蓝色", "#007C9A"),
        ("钢铁灰", "#7D7F84"),
        ("柠檬黄", "#FFF600"),
        ("草地绿", "#57A300"),
        ("粉蓝色", "#00B2E2"),
        ("橘子色", "#FFA600"),
        ("紫红色", "#A500B5")
    ].compactMap { item in
        guard let color = UIColor(hexString: item.1) else { return nil }
        return CalendarColorOption(id: item.1, name: item.0, color: color)
    }
}

final class AddCalendarViewController: UIViewController {
    var onCalendarCreated: ((EKCalendarSummary) -> Void)?

    private let calendarService: CalendarService
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleField = UITextField()
    private let titleColorDot = UIView()
    private let storageRow = StorageInfoRow()
    private let colorPaletteView = CalendarColorPaletteView()
    private var selectedColorOption: CalendarColorOption
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var isSaving = false
    private var customColorOptions: [CalendarColorOption] = []
    private let customColorStorageKey = "AddCalendarViewController.customColorHexes"
    private let maxCustomColorCount = 8

    init(calendarService: CalendarService) {
        self.calendarService = calendarService
        self.selectedColorOption = CalendarColorOption.predefined.first ?? CalendarColorOption(id: "default", name: "樱桃红", color: .systemRed)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "添加日历"
        customColorOptions = loadCustomColorOptions()
        setupNavigation()
        setupViews()
        updateColorPalette()
        updateTitleColorIndicator()
        titleField.becomeFirstResponder()
    }

    private func setupNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "保存", style: .done, target: self, action: #selector(saveTapped))
    }

    private func setupViews() {
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.layoutMargins = .zero
        contentStack.isLayoutMarginsRelativeArrangement = false
        scrollView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(view.safeAreaLayoutGuide.snp.width)
        }

        let nameContainer = UIView()
        nameContainer.backgroundColor = .white
        nameContainer.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        let lineHeight = 1.0 / UIScreen.main.scale
        let nameBottomSeparator = UIView()
        nameBottomSeparator.backgroundColor = UIColor.separator
        nameContainer.addSubview(nameBottomSeparator)
        nameBottomSeparator.snp.makeConstraints { make in
            make.bottom.leading.trailing.equalToSuperview()
            make.height.equalTo(lineHeight)
        }
        nameContainer.snp.makeConstraints { make in
            make.height.equalTo(56)
        }

        titleField.placeholder = "日历名称"
        titleField.font = UIFont.systemFont(ofSize: 23, weight: .semibold)
        titleField.clearButtonMode = .whileEditing
        titleField.returnKeyType = .done
        titleField.delegate = self

        titleColorDot.layer.cornerRadius = 8
        titleColorDot.layer.masksToBounds = true
        nameContainer.addSubview(titleColorDot)
        titleColorDot.snp.makeConstraints { make in
            make.leading.equalTo(nameContainer.layoutMarginsGuide.snp.leading)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(16)
        }

        nameContainer.addSubview(titleField)
        titleField.snp.makeConstraints { make in
            make.top.bottom.equalTo(nameContainer.layoutMarginsGuide)
            make.trailing.equalTo(nameContainer.layoutMarginsGuide)
            make.leading.equalTo(titleColorDot.snp.trailing).offset(12)
            make.height.equalTo(56)
        }

        contentStack.addArrangedSubview(nameContainer)

        storageRow.configure(title: "存储到", value: "iCloud")
        storageRow.setSeparatorVisibility(showTop: false, showBottom: true)
        contentStack.addArrangedSubview(storageRow)

        let paletteContainer = UIView()
        paletteContainer.backgroundColor = .clear
        paletteContainer.addSubview(colorPaletteView)
        contentStack.addArrangedSubview(paletteContainer)
        colorPaletteView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 20, bottom: 0, right: 20))
        }
        colorPaletteView.onColorSelected = { [weak self] option in
            self?.handleColorSelection(option)
        }
        colorPaletteView.onCustomColorTapped = { [weak self] color in
            self?.showCustomColorPicker(initialColor: color)
        }
        contentStack.setCustomSpacing(24, after: storageRow)

        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        activityIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func updateColorPalette() {
        colorPaletteView.configure(
            predefinedColors: CalendarColorOption.predefined,
            customColors: customColorOptions,
            selectedColor: selectedColorOption
        )
    }

    @objc private func cancelTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func saveTapped() {
        guard !isSaving else { return }
        let trimmed = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            showAlert(message: "请输入日历标题")
            return
        }

        setSaving(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await self.calendarService.createCalendar(title: trimmed, color: self.selectedColorOption.color)
                await MainActor.run {
                    self.setSaving(false)
                    self.onCalendarCreated?(summary)
                    self.navigationController?.popViewController(animated: true)
                }
            } catch {
                await MainActor.run {
                    self.setSaving(false)
                    self.showAlert(message: "创建日历失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func handleColorSelection(_ option: CalendarColorOption) {
        selectedColorOption = option
        updateColorPalette()
        updateTitleColorIndicator()
    }

    private func handleCustomColorSelection(_ color: UIColor) {
        let option = insertCustomColorOption(color)
        handleColorSelection(option)
    }

    private func updateTitleColorIndicator() {
        titleColorDot.backgroundColor = selectedColorOption.color
    }

    private func insertCustomColorOption(_ color: UIColor) -> CalendarColorOption {
        let hex = color.toHexString()
        let identifier = "custom-\(hex)"
        let option = CalendarColorOption(id: identifier, name: "自定义颜色", color: color)
        if let index = customColorOptions.firstIndex(where: { $0.color.toHexString().caseInsensitiveCompare(hex) == .orderedSame }) {
            customColorOptions.remove(at: index)
        }
        customColorOptions.insert(option, at: 0)
        if customColorOptions.count > maxCustomColorCount {
            customColorOptions.removeLast(customColorOptions.count - maxCustomColorCount)
        }
        persistCustomColorOptions()
        return option
    }

    private func loadCustomColorOptions() -> [CalendarColorOption] {
        guard let stored = UserDefaults.standard.array(forKey: customColorStorageKey) as? [String] else {
            return []
        }
        return stored.compactMap { hex in
            guard let color = UIColor(hexString: hex) else { return nil }
            let identifier = "custom-\(hex)"
            return CalendarColorOption(id: identifier, name: "自定义颜色", color: color)
        }
    }

    private func persistCustomColorOptions() {
        let values = customColorOptions.map { $0.color.toHexString() }
        UserDefaults.standard.set(values, forKey: customColorStorageKey)
    }

    private func showCustomColorPicker(initialColor: UIColor? = nil) {
        let picker = UIColorPickerViewController()
        picker.delegate = self
        picker.selectedColor = initialColor ?? selectedColorOption.color
        if #available(iOS 15.0, *) {
            picker.modalPresentationStyle = .pageSheet
            picker.sheetPresentationController?.detents = [.medium()]
        } else {
            picker.modalPresentationStyle = .formSheet
        }
        present(picker, animated: true)
    }

    private func setSaving(_ saving: Bool) {
        isSaving = saving
        navigationItem.rightBarButtonItem?.isEnabled = !saving
        saving ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

extension AddCalendarViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

extension AddCalendarViewController: UIColorPickerViewControllerDelegate {
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        handleCustomColorSelection(viewController.selectedColor)
    }

    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        // optional live update not needed
    }
}

private final class StorageInfoRow: UIView {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let topSeparator = UIView()
    private let bottomSeparator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

        titleLabel.font = UIFont.systemFont(ofSize: 16)
        titleLabel.textColor = .label

        valueLabel.font = UIFont.systemFont(ofSize: 16)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right

        [topSeparator, bottomSeparator].forEach {
            $0.backgroundColor = UIColor.separator
            addSubview($0)
        }
        let scale = UIScreen.main.scale
        topSeparator.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(1.0 / scale)
        }
        bottomSeparator.snp.makeConstraints { make in
            make.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(1.0 / scale)
        }

        addSubview(titleLabel)
        addSubview(valueLabel)

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(layoutMarginsGuide.snp.leading)
            make.centerY.equalToSuperview()
        }

        valueLabel.snp.makeConstraints { make in
            make.trailing.equalTo(layoutMarginsGuide.snp.trailing)
            make.centerY.equalToSuperview()
            make.leading.greaterThanOrEqualTo(titleLabel.snp.trailing).offset(12)
        }

        snp.makeConstraints { make in
            make.height.equalTo(56)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
    }

    func setSeparatorVisibility(showTop: Bool, showBottom: Bool) {
        topSeparator.isHidden = !showTop
        bottomSeparator.isHidden = !showBottom
    }
}

private final class CalendarColorPaletteView: UIView {
    var onColorSelected: ((CalendarColorOption) -> Void)?
    var onCustomColorTapped: ((UIColor) -> Void)?

    private let stackView = UIStackView()
    private let customSectionContainer = UIView()
    private let customColorsRow = UIStackView()
    private let customSeparator = UIView()
    private let predefinedStack = UIStackView()
    private let buttonSeparator = UIView()
    private let customColorButton = CustomColorPickerButton()
    private var swatchButtons: [ColorSwatchButton] = []
    private var selectedColorID: String?
    private var currentSelectedColor: UIColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.96, alpha: 1.0)
        layer.cornerRadius = 16
        layer.masksToBounds = true
        layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .fill
        stackView.distribution = .fill
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalTo(layoutMarginsGuide)
        }

        customColorsRow.axis = .horizontal
        customColorsRow.spacing = 12
        customColorsRow.alignment = .center
        customSectionContainer.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        customSectionContainer.addSubview(customColorsRow)
        customColorsRow.snp.makeConstraints { make in
            make.edges.equalTo(customSectionContainer.layoutMarginsGuide)
        }
        stackView.addArrangedSubview(customSectionContainer)

        customSeparator.backgroundColor = UIColor.separator
        stackView.addArrangedSubview(customSeparator)
        customSeparator.snp.makeConstraints { make in
            make.height.equalTo(1.0 / UIScreen.main.scale)
        }

        predefinedStack.axis = .vertical
        predefinedStack.spacing = 16
        stackView.addArrangedSubview(predefinedStack)

        buttonSeparator.backgroundColor = UIColor.separator
        stackView.addArrangedSubview(buttonSeparator)
        buttonSeparator.snp.makeConstraints { make in
            make.height.equalTo(1.0 / UIScreen.main.scale)
        }

        stackView.addArrangedSubview(customColorButton)
        customColorButton.snp.makeConstraints { make in
            make.height.equalTo(34)
        }
        customColorButton.addTarget(self, action: #selector(customButtonTapped), for: .touchUpInside)

        stackView.setCustomSpacing(16, after: customSeparator)
        stackView.setCustomSpacing(16, after: predefinedStack)
        stackView.setCustomSpacing(16, after: buttonSeparator)

        customSectionContainer.isHidden = true
        customSeparator.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(predefinedColors: [CalendarColorOption], customColors: [CalendarColorOption], selectedColor: CalendarColorOption) {
        selectedColorID = selectedColor.id
        swatchButtons.removeAll()
        currentSelectedColor = selectedColor.color
        rebuildCustomSection(with: customColors)
        rebuildPredefinedSection(with: predefinedColors)
        updateSelectionIndicators()
    }

    private func rebuildCustomSection(with colors: [CalendarColorOption]) {
        clearArrangedSubviews(in: customColorsRow)
        guard !colors.isEmpty else {
            customSectionContainer.isHidden = true
            customSeparator.isHidden = true
            return
        }

        customSectionContainer.isHidden = false
        customSeparator.isHidden = false
        colors.forEach { option in
            let swatch = makeSwatch(for: option)
            customColorsRow.addArrangedSubview(swatch)
        }
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        customColorsRow.addArrangedSubview(spacer)
    }

    private func rebuildPredefinedSection(with colors: [CalendarColorOption]) {
        clearArrangedSubviews(in: predefinedStack)
        let chunkSize = 8
        for start in stride(from: 0, to: colors.count, by: chunkSize) {
            let end = min(start + chunkSize, colors.count)
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.distribution = .equalSpacing
            row.spacing = 12
            colors[start..<end].forEach { option in
                let swatch = makeSwatch(for: option)
                row.addArrangedSubview(swatch)
            }
            predefinedStack.addArrangedSubview(row)
        }
    }

    private func clearArrangedSubviews(in stack: UIStackView) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func makeSwatch(for option: CalendarColorOption) -> ColorSwatchButton {
        let swatch = ColorSwatchButton()
        swatch.configure(with: option)
        swatch.addTarget(self, action: #selector(colorTapped(_:)), for: .touchUpInside)
        swatchButtons.append(swatch)
        return swatch
    }

    private func updateSelectionIndicators() {
        guard let targetID = selectedColorID else { return }
        swatchButtons.forEach { button in
            guard let option = button.option else { return }
            button.isSelected = option.id.caseInsensitiveCompare(targetID) == .orderedSame
        }
    }

    @objc private func colorTapped(_ sender: ColorSwatchButton) {
        guard let option = sender.option else { return }
        selectedColorID = option.id
        updateSelectionIndicators()
        onColorSelected?(option)
    }

    @objc private func customButtonTapped() {
        onCustomColorTapped?(currentSelectedColor ?? UIColor.white)
    }
}

private final class ColorSwatchButton: UIControl {
    private let colorView = UIView()
    private let selectionImageView = UIImageView(image: UIImage(named: "color_select")?.withRenderingMode(.alwaysTemplate))
    private(set) var option: CalendarColorOption?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits.insert(.button)
        colorView.layer.cornerRadius = 17
        colorView.layer.masksToBounds = true
        colorView.isUserInteractionEnabled = false
        addSubview(colorView)
        colorView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        selectionImageView.contentMode = .scaleAspectFit
        selectionImageView.isHidden = true
        selectionImageView.isUserInteractionEnabled = false
        selectionImageView.tintColor = .white

        colorView.addSubview(selectionImageView)
        selectionImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(18)
        }

        snp.makeConstraints { make in
            make.width.height.equalTo(34)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with option: CalendarColorOption) {
        self.option = option
        colorView.backgroundColor = option.color
        accessibilityLabel = option.name
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1.0
        }
    }

    override var isSelected: Bool {
        didSet {
            selectionImageView.isHidden = !isSelected
            colorView.layer.borderColor = isSelected ? UIColor.white.cgColor : UIColor.black.withAlphaComponent(0.1).cgColor
        }
    }
}

private final class CustomColorPickerButton: UIControl {
    private let iconView: UIView

    override init(frame: CGRect) {
        if #available(iOS 14.0, *) {
            let well = UIColorWell()
            well.supportsAlpha = false
            well.isEnabled = false
            well.isUserInteractionEnabled = false
            iconView = well
        } else {
            iconView = ColorWheelIconView()
        }
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits.insert(.button)
        accessibilityLabel = "自定义颜色"

        iconView.isUserInteractionEnabled = false
        addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.height.equalTo(34)
        }

        snp.makeConstraints { make in
            make.height.equalTo(34)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            iconView.alpha = isHighlighted ? 0.6 : 1.0
        }
    }
}

private final class ColorWheelIconView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let innerCircle = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradientLayer.type = .conic
        gradientLayer.colors = [
            UIColor.red.cgColor,
            UIColor.orange.cgColor,
            UIColor.yellow.cgColor,
            UIColor.green.cgColor,
            UIColor.cyan.cgColor,
            UIColor.blue.cgColor,
            UIColor.purple.cgColor,
            UIColor.red.cgColor
        ]
        layer.addSublayer(gradientLayer)
        innerCircle.backgroundColor = .white
        innerCircle.isUserInteractionEnabled = false
        addSubview(innerCircle)
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        layer.cornerRadius = bounds.width / 2
        innerCircle.frame = bounds.insetBy(dx: 6, dy: 6)
        innerCircle.layer.cornerRadius = innerCircle.bounds.width / 2
    }
}
