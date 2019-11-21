//
//  UINavigationBar+font
//  FirefoxPrivateNetworkVPN
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
//  Copyright © 2019 Mozilla Corporation.
//

import UIKit

extension UINavigationBar {

    func setTitleFont() {
        if let font = UIFont(name: "Metropolis-SemiBold", size: 15) {
            titleTextAttributes = [NSAttributedString.Key.font: font,
                                   NSAttributedString.Key.foregroundColor: UIColor.custom(.grey50)]
        }
    }
}
