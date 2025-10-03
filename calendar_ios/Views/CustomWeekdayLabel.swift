import UIKit
import SnapKit

/// 自定义星期标签
/// 仿照 FSCalendar 的星期头部显示
class CustomWeekdayLabel: UIView {

    /// 星期文字数组
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    /// 星期标签容器
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .center
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = .systemBackground

        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 添加星期标签
        for weekday in weekdays {
            let label = UILabel()
            label.text = weekday
            label.textAlignment = .center
            label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            label.textColor = .secondaryLabel
            stackView.addArrangedSubview(label)
        }
    }

    /// 更新主题颜色
    func updateAppearance(textColor: UIColor? = nil, backgroundColor: UIColor? = nil) {
        if let textColor = textColor {
            stackView.arrangedSubviews.forEach { view in
                (view as? UILabel)?.textColor = textColor
            }
        }
        if let bgColor = backgroundColor {
            self.backgroundColor = bgColor
        }
    }
}
