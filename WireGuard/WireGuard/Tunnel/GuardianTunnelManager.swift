// SPDX-License-Identifier: MIT
// Copyright © 2018-2019 WireGuard LLC. All Rights Reserved.

import Foundation
import NetworkExtension

class GuardianTunnelManager {
    static let sharedTunnelManager = GuardianTunnelManager()

    var tunnelProviderManagers = [NETunnelProviderManager]()

    private init() {
        loadTunnels()
    }

    func loadTunnels() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard error == nil else {
                print("Error: \(error!)")
                return
            }
            guard let self = self else { return }
            if let managers = managers {
                self.tunnelProviderManagers = managers
            }
            print("\(self.tunnelProviderManagers.count) tunnels available")
        }
    }

    func createTunnel(accountManager: AccountManaging?) { // Inject Account Manager or pass in device?
        guard let device = accountManager?.account?.currentDevice,
            let privateKey = (accountManager as? AccountManager)?.credentialsStore.deviceKeys.devicePrivateKey
            else { return }
        // get current city / config
        // TODO: Save city somewhere, and retrieve it here.
        guard let currentCity = VPNCity.fetchFromUserDefaults() else { return }

        createTunnel(device: device, city: currentCity, privateKey: privateKey)
    }

    func createTunnel(device: Device, city: VPNCity, privateKey: Data) {
        guard let tunnelConfiguration = TunnelConfigurationBuilder.createTunnelConfiguration(device: device, city: city, privateKey: privateKey) else { return }

        let tunnelProviderManager = NETunnelProviderManager()
        let tunnelProviderProtocol = NETunnelProviderProtocol(tunnelConfiguration: tunnelConfiguration)!

        tunnelProviderManager.protocolConfiguration = tunnelProviderProtocol
        tunnelProviderManager.localizedDescription = city.name
        tunnelProviderManager.isEnabled = true

        // TODO: Do we want this on demand connect?
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        rule.ssidMatch = nil
        tunnelProviderManager.onDemandRules = [rule]
        tunnelProviderManager.isOnDemandEnabled = false

        tunnelProviderManager.saveToPreferences { _ in
            tunnelProviderManager.loadFromPreferences { error in
                guard error == nil else {
                    print("Error: \(error!)")
                    return
                }
                do {
                    try (tunnelProviderManager.connection as? NETunnelProviderSession)?.startTunnel()
                } catch let error {
                    print("Start Tunnel Error: \(error)")
                }
            }
        }
    }

    func startTunnel() {
        guard let tunnelProviderManager = tunnelProviderManagers.first else {
            print("No tunnels to start")
            return
        }
        do {
            try (tunnelProviderManager.connection as? NETunnelProviderSession)?.startTunnel()
        } catch let error {
            print("Error: \(error)")
        }
    }

    func stopTunnel() {
        guard let connectedTunnelProvider = self.tunnelProviderManagers.first(where: { $0.connection.status == .connected }) else {
            print("No tunnel is connected")
            return
        }
        (connectedTunnelProvider.connection as? NETunnelProviderSession)?.stopTunnel()
    }
}
