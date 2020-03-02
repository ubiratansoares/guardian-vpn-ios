//
//  SettingsDataSource
//  FirefoxPrivateNetworkVPN
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
//  Copyright © 2019 Mozilla Corporation.
//

import UIKit
import RxSwift

class SettingsDataSource: NSObject, UITableViewDataSource {
    // MARK: - Properties
    private let representedObject: [SettingsItem]
    private let cellName = String(describing: AccountInformationCell.self)
    private var account: Account? { return DependencyFactory.sharedFactory.accountManager.account }

    let rowSelected = PublishSubject<NavigableItem>()

    // MARK: - Initialization
    init(with tableView: UITableView) {
        representedObject = [.device, .help, .about, .feedback]
        super.init()
        tableView.delegate = self
        tableView.dataSource = self

        let cellNib = UINib.init(nibName: cellName, bundle: nil)
        tableView.register(cellNib, forCellReuseIdentifier: cellName)
    }

    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        representedObject.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellName, for: indexPath) as? AccountInformationCell
            else { return UITableViewCell(frame: .zero) }
        let settingsItem = representedObject[indexPath.row]
        cell.setup(settingsItem)

        if settingsItem.action == .devices,
            let account = account,
            !account.hasDeviceBeenAdded {
            cell.accessoryIconImageView.image = UIImage(named: "icon_alert")
            cell.accessoryIconImageView.isHidden = false
        } else {
            cell.accessoryIconImageView.isHidden = true
        }

        return cell
    }
}

// MARK: - UITableViewDelegate
extension SettingsDataSource: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        rowSelected.onNext(representedObject[indexPath.row].action)

        tableView.deselectRow(at: indexPath, animated: false)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return AccountInformationCell.height
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return .zero
    }
}
