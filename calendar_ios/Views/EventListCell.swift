import UIKit
import SnapKit

final class EventListCell: UITableViewCell {
    static let reuseIdentifier = "EventListCell"

    private let colorIndicator = UIView()
    private let titleLabel = UILabel()
    private let timeLabel = UILabel()
    private let locationLabel = UILabel()
    private let stackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        configureUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureUI() {
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground

        colorIndicator.layer.cornerRadius = 4
        colorIndicator.backgroundColor = UIColor.systemBlue
        contentView.addSubview(colorIndicator)

        stackView.axis = .vertical
        stackView.spacing = 4
        contentView.addSubview(stackView)

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label

        timeLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        timeLabel.textColor = .secondaryLabel

        locationLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        locationLabel.textColor = .tertiaryLabel

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(timeLabel)
        stackView.addArrangedSubview(locationLabel)

        colorIndicator.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 8, height: 40))
        }

        stackView.snp.makeConstraints { make in
            make.leading.equalTo(colorIndicator.snp.trailing).offset(12)
            make.trailing.equalToSuperview().inset(16)
            make.top.equalToSuperview().offset(12)
            make.bottom.equalToSuperview().inset(12)
        }
    }

    func configure(with event: Event) {
        titleLabel.text = event.title
        if event.isAllDay {
            timeLabel.text = "全天"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            timeLabel.text = "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
        }
        locationLabel.text = event.location.isEmpty ? event.calendarName : event.location
        locationLabel.isHidden = (locationLabel.text ?? "").isEmpty
        colorIndicator.backgroundColor = event.customColor ?? UIColor.systemBlue
    }
}
