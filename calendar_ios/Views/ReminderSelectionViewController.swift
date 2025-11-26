import UIKit
import SnapKit

final class ReminderSelectionViewController: UIViewController {
    var onSelectionConfirm: (([AddEventViewController.ReminderOption]) -> Void)?

    private let options: [AddEventViewController.ReminderOption]
    private var selectedIds: Set<String>
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private var rows: [ReminderSelectionRow] = []

    init(options: [AddEventViewController.ReminderOption], initialSelection: [AddEventViewController.ReminderOption]) {
        self.options = options
        self.selectedIds = Set(initialSelection.map { $0.id })
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "自定义提醒"
        view.backgroundColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneTapped))
        configureViews()
        updateRowStates()
    }

    private func configureViews() {
        stackView.axis = .vertical
        stackView.spacing = 4

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
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
        }

        options.forEach { option in
            let row = ReminderSelectionRow(title: option.title, optionId: option.id)
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(row)
            rows.append(row)
        }
    }

    @objc private func rowTapped(_ sender: ReminderSelectionRow) {
        guard let option = options.first(where: { $0.id == sender.optionId }) else { return }
        toggleSelection(for: option)
    }

    private func toggleSelection(for option: AddEventViewController.ReminderOption) {
        if selectedIds.contains(option.id) {
            selectedIds.remove(option.id)
        } else {
            if option.isNone {
                selectedIds = [option.id]
            } else {
                selectedIds.insert(option.id)
                if let noneId = options.first(where: { $0.isNone })?.id {
                    selectedIds.remove(noneId)
                }
            }
        }

        if selectedIds.isEmpty, let noneId = options.first(where: { $0.isNone })?.id {
            selectedIds = [noneId]
        }
        updateRowStates()
    }

    private func updateRowStates() {
        rows.forEach { row in
            row.isOn = selectedIds.contains(row.optionId)
        }
    }

    @objc private func doneTapped() {
        let orderedSelection = options.filter { selectedIds.contains($0.id) }
        onSelectionConfirm?(orderedSelection)
        navigationController?.popViewController(animated: true)
    }
}

private final class ReminderSelectionRow: UIControl {
    let optionId: String
    private let titleLabel = UILabel()
    private let checkImageView = UIImageView(image: UIImage(systemName: "checkmark"))

    var isOn: Bool = false {
        didSet { updateAppearance() }
    }

    init(title: String, optionId: String) {
        self.optionId = optionId
        super.init(frame: .zero)
        setup(title: title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(title: String) {
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 17)
        titleLabel.textColor = .label

        checkImageView.tintColor = .systemBlue
        checkImageView.contentMode = .scaleAspectFit
        checkImageView.isHidden = true

        let container = UIStackView(arrangedSubviews: [titleLabel, UIView(), checkImageView])
        container.axis = .horizontal
        container.alignment = .center
        container.spacing = 12
        container.isUserInteractionEnabled = false

        addSubview(container)
        container.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 24, bottom: 10, right: 16))
        }
        heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        layer.cornerRadius = 12
        layer.masksToBounds = true
        addTarget(self, action: #selector(handleTouchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(handleTouchUp), for: [.touchCancel, .touchDragExit, .touchUpInside, .touchUpOutside])
        updateAppearance()
    }

    private func updateAppearance() {
        checkImageView.isHidden = !isOn
        backgroundColor = isHighlighted ? UIColor.systemGray5 : UIColor.clear
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? UIColor.systemGray5 : UIColor.clear }
    }

    @objc private func handleTouchDown() {
        isHighlighted = true
    }

    @objc private func handleTouchUp() {
        isHighlighted = false
    }
}
