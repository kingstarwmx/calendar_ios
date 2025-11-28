import UIKit
import MapKit
import CoreLocation
import SnapKit
import Contacts

struct LocationSelection {
    let title: String
    let subtitle: String
    let mapItem: MKMapItem?

    var combinedDescription: String {
        if subtitle.isEmpty {
            return title
        }
        return "\(title) \(subtitle)"
    }

    var multilineDescription: String {
        if subtitle.isEmpty {
            return title
        }
        return "\(title)\n\(subtitle)"
    }
}

final class LocationSelectViewController: UIViewController {
    var onLocationSelected: ((LocationSelection?) -> Void)?
    var initialSelection: LocationSelection?

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private let locationManager = CLLocationManager()
    private let searchCompleter = MKLocalSearchCompleter()
    private var searchTask: MKLocalSearch?
    private let geocoder = CLGeocoder()
    private var suggestions: [MKLocalSearchCompletion] = []
    private var currentLocation: CLLocation? {
        didSet {
            guard oldValue?.coordinate.latitude != currentLocation?.coordinate.latitude ||
                    oldValue?.coordinate.longitude != currentLocation?.coordinate.longitude else { return }
            updateCompleterRegion()
            reloadCurrentLocationRow()
        }
    }
    private var isResolvingCurrentLocation = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "选择地点"
        view.backgroundColor = .systemBackground
        configureSearchBar()
        configureTableView()
        configureLoadingIndicator()
        configureLocationServices()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    private func configureSearchBar() {
        searchBar.delegate = self
        searchBar.placeholder = "搜索地点"
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.returnKeyType = .done
        searchBar.backgroundImage = UIImage()
        if let initialSelection {
            searchBar.text = initialSelection.title
        }

        let container = UIView()
        container.backgroundColor = UIColor.systemBackground
        view.addSubview(container)
        container.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalToSuperview()
        }

        container.addSubview(searchBar)
        searchBar.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
        }

        searchBar.layer.cornerRadius = 10
        searchBar.clipsToBounds = true

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(container.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func configureTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.tableFooterView = UIView()
        tableView.register(LocationResultCell.self, forCellReuseIdentifier: LocationResultCell.reuseIdentifier)
        tableView.register(CurrentLocationCell.self, forCellReuseIdentifier: CurrentLocationCell.reuseIdentifier)
    }

    private func configureLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        loadingIndicator.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-24)
        }
    }

    private func configureLocationServices() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        searchCompleter.delegate = self
        searchCompleter.resultTypes = [.address, .pointOfInterest]
        searchCompleter.pointOfInterestFilter = .includingAll
        requestLocationAccessIfNeeded()
    }

    private func requestLocationAccessIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }

    private func updateCompleterRegion() {
        if let location = currentLocation {
            let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
            searchCompleter.region = region
        } else if let item = initialSelection?.mapItem {
            let region = MKCoordinateRegion(center: item.placemark.coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
            searchCompleter.region = region
        }
    }

    private func handleSearchTextChange(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            suggestions = []
            tableView.reloadData()
            return
        }
        searchCompleter.queryFragment = trimmed
    }

    private func resolveSelection(from completion: MKLocalSearchCompletion) {
        searchTask?.cancel()
        loadingIndicator.startAnimating()
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        searchTask = search
        search.start { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadingIndicator.stopAnimating()
                let mapItem = response?.mapItems.first
                let title = mapItem?.name ?? completion.title
                let selection = LocationSelection(title: title, subtitle: completion.subtitle, mapItem: mapItem)
                self.onLocationSelected?(selection)
                self.navigationController?.popViewController(animated: true)
            }
        }
    }
}

extension LocationSelectViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        handleSearchTextChange(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension LocationSelectViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // 第一行用于“当前位置”
        return suggestions.count + 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: CurrentLocationCell.reuseIdentifier, for: indexPath) as? CurrentLocationCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "当前位置",
                isLoading: isResolvingCurrentLocation,
                isEnabled: currentLocation != nil
            )
            return cell
        }
        guard let cell = tableView.dequeueReusableCell(withIdentifier: LocationResultCell.reuseIdentifier, for: indexPath) as? LocationResultCell else {
            return UITableViewCell()
        }
        let completion = suggestions[indexPath.row - 1]
        cell.configure(with: completion)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 {
            handleCurrentLocationSelection()
            return
        }
        let suggestionIndex = indexPath.row - 1
        guard suggestionIndex < suggestions.count else { return }
        let completion = suggestions[suggestionIndex]
        searchBar.resignFirstResponder()
        resolveSelection(from: completion)
    }
}

extension LocationSelectViewController: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 忽略定位失败，继续使用默认搜索
    }
}

extension LocationSelectViewController: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
        tableView.reloadData()
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
        tableView.reloadData()
    }

    private func handleCurrentLocationSelection() {
        guard !isResolvingCurrentLocation else { return }
        searchBar.resignFirstResponder()
        guard let location = currentLocation else {
            showAlert(title: "提示", message: "无法获取当前位置，请稍后重试。")
            locationManager.requestLocation()
            return
        }
        isResolvingCurrentLocation = true
        reloadCurrentLocationRow()
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isResolvingCurrentLocation = false
                self.reloadCurrentLocationRow()
                if let error {
                    self.showAlert(title: "提示", message: "获取当前位置失败：\(error.localizedDescription)")
                    return
                }
                guard let placemark = placemarks?.first else {
                    self.showAlert(title: "提示", message: "无法解析当前位置地址。")
                    return
                }

                let name = placemark.name ?? "当前位置"
                let subtitle = self.makeSubtitle(from: placemark)
                let mkPlacemark = MKPlacemark(placemark: placemark)
                let mapItem = MKMapItem(placemark: mkPlacemark)
                let selection = LocationSelection(
                    title: name,
                    subtitle: subtitle == name ? "" : subtitle,
                    mapItem: mapItem
                )
                self.onLocationSelected?(selection)
                self.navigationController?.popViewController(animated: true)
            }
        }
    }

    private func reloadCurrentLocationRow() {
        guard isViewLoaded else { return }
        let indexPath = IndexPath(row: 0, section: 0)
        if tableView.numberOfRows(inSection: 0) > 0 {
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }

    private func makeSubtitle(from placemark: CLPlacemark) -> String {
        if let postalAddress = placemark.postalAddress {
            let formatted = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
            return formatted.replacingOccurrences(of: "\n", with: "")
        }
        let components = [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ].compactMap { $0 }
        let joined = components.joined()
        return joined.isEmpty ? (placemark.name ?? "当前位置") : joined
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

private final class LocationResultCell: UITableViewCell {
    static let reuseIdentifier = "LocationResultCell"
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        accessoryType = .none
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        titleLabel.numberOfLines = 2
        subtitleLabel.font = UIFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = UIColor.secondaryLabel
        subtitleLabel.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with completion: MKLocalSearchCompletion) {
        titleLabel.text = completion.title
        subtitleLabel.text = completion.subtitle
        subtitleLabel.isHidden = completion.subtitle.isEmpty
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
        subtitleLabel.isHidden = false
    }
}

private final class CurrentLocationCell: UITableViewCell {
    static let reuseIdentifier = "CurrentLocationCell"

    private let iconContainer = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        accessoryType = .none

        iconContainer.backgroundColor = UIColor.systemGray5
        iconContainer.layer.cornerRadius = 22
        iconContainer.layer.masksToBounds = true

        iconImageView.image = UIImage(systemName: "location.circle.fill")
        iconImageView.tintColor = UIColor.systemBlue

        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = UIColor.label

        loadingIndicator.hidesWhenStopped = true

        contentView.addSubview(iconContainer)
        iconContainer.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(loadingIndicator)

        iconContainer.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.top.equalToSuperview().offset(12)
            make.bottom.equalToSuperview().offset(-12)
            make.width.height.equalTo(44)
        }

        iconImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(26)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconContainer.snp.trailing).offset(16)
            make.centerY.equalTo(iconContainer.snp.centerY)
        }

        loadingIndicator.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(titleLabel.snp.trailing).offset(8)
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, isLoading: Bool, isEnabled: Bool) {
        titleLabel.text = title
        titleLabel.textColor = isEnabled ? UIColor.label : UIColor.secondaryLabel
        if isLoading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }
}
