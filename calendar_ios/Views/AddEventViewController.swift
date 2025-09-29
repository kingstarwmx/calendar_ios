import UIKit
import SnapKit

final class AddEventViewController: UIViewController {
    var onSave: ((Event) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let titleField = UITextField()
    private let locationField = UITextField()
    private let urlField = UITextField()
    private let allDaySwitch = UISwitch()
    private let allDayLabel = UILabel()
    private let startDatePicker = UIDatePicker()
    private let endDatePicker = UIDatePicker()
    private let descriptionView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "新建事件"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTapped))

        configureFields()
        layoutUI()
    }

    private func configureFields() {
        titleField.placeholder = "标题"
        titleField.borderStyle = .roundedRect

        locationField.placeholder = "地点"
        locationField.borderStyle = .roundedRect

        urlField.placeholder = "链接"
        urlField.keyboardType = .URL
        urlField.autocapitalizationType = .none
        urlField.borderStyle = .roundedRect

        allDayLabel.text = "全天"
        allDaySwitch.addTarget(self, action: #selector(allDayChanged), for: .valueChanged)

        startDatePicker.datePickerMode = .dateAndTime
        startDatePicker.preferredDatePickerStyle = .inline
        startDatePicker.minuteInterval = 15
        startDatePicker.addTarget(self, action: #selector(startDateChanged), for: .valueChanged)

        endDatePicker.datePickerMode = .dateAndTime
        endDatePicker.preferredDatePickerStyle = .inline
        endDatePicker.minuteInterval = 15

        descriptionView.font = UIFont.preferredFont(forTextStyle: .body)
        descriptionView.layer.cornerRadius = 8
        descriptionView.layer.borderWidth = 1
        descriptionView.layer.borderColor = UIColor.separator.cgColor
        descriptionView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
    }

    private func layoutUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.snp.width)
        }

        let stack = UIStackView(arrangedSubviews: [
            titleField,
            locationField,
            urlField,
            makeAllDayRow(),
            labeledContainer(title: "开始时间", content: startDatePicker),
            labeledContainer(title: "结束时间", content: endDatePicker),
            labeledContainer(title: "备注", content: descriptionView, height: 120)
        ])
        stack.axis = .vertical
        stack.spacing = 16

        contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(20)
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(20)
        }
    }

    private func makeAllDayRow() -> UIView {
        let container = UIView()
        container.addSubview(allDayLabel)
        container.addSubview(allDaySwitch)

        allDayLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
        }

        allDaySwitch.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
        }

        return container
    }

    private func labeledContainer(title: String, content: UIView, height: CGFloat? = nil) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = title
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        container.addSubview(label)
        container.addSubview(content)

        label.snp.makeConstraints { make in
            make.top.leading.equalToSuperview()
        }

        content.snp.makeConstraints { make in
            make.top.equalTo(label.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
            if let height { make.height.equalTo(height) }
        }

        return container
    }

    @objc private func allDayChanged() {
        let mode: UIDatePicker.Mode = allDaySwitch.isOn ? .date : .dateAndTime
        startDatePicker.datePickerMode = mode
        endDatePicker.datePickerMode = mode
    }

    @objc private func startDateChanged() {
        if startDatePicker.date > endDatePicker.date {
            endDatePicker.date = startDatePicker.date.addingTimeInterval(3600)
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        guard let titleText = titleField.text, !titleText.trimmingCharacters(in: .whitespaces).isEmpty else {
            showAlert(message: "请输入事件标题")
            return
        }

        let calendar = Calendar.current
        var startDate = startDatePicker.date
        var endDate = endDatePicker.date

        if allDaySwitch.isOn {
            startDate = calendar.startOfDay(for: startDate)
            endDate = calendar.startOfDay(for: endDate)
            if endDate < startDate {
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(86400)
            } else if endDate == startDate {
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(86400)
            }
        } else if endDate <= startDate {
            endDate = startDate.addingTimeInterval(3600)
        }

        let event = Event(
            id: UUID().uuidString,
            title: titleText,
            startDate: startDate,
            endDate: endDate,
            isAllDay: allDaySwitch.isOn,
            location: locationField.text ?? "",
            calendarId: "local",
            description: descriptionView.text.isEmpty ? nil : descriptionView.text,
            customColor: UIColor.systemBlue,
            recurrenceRule: nil,
            reminders: [],
            url: urlField.text,
            calendarName: "本地日历",
            isFromDeviceCalendar: false,
            deviceEventId: nil
        )

        onSave?(event)
        dismiss(animated: true)
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
