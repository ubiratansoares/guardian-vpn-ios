// SPDX-License-Identifier: MIT
// Copyright © 2018-2019 WireGuard LLC. All Rights Reserved.

import Foundation

protocol UserDefaulting: Codable {
    static var userDefaultsKey: String { get }
}

extension UserDefaulting {
    static func fetchFromUserDefaults() -> Self? {
        guard let decoded = UserDefaults.standard.object(forKey: Self.userDefaultsKey) as? Data,
            let response = try? JSONDecoder().decode(Self.self, from: decoded) else {
                return nil
        }
        return response
    }

    func saveToUserDefaults() {
        do {
            let encoded = try JSONEncoder().encode(self)
            let defaults = UserDefaults.standard
            defaults.set(encoded, forKey: Self.userDefaultsKey)
            defaults.synchronize()

        } catch {
            print(error) // TODO: Handle this
        }
    }
}