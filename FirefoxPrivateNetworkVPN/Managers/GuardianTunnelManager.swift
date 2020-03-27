//
//  GuardianTunnelManager
//  FirefoxPrivateNetworkVPN
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
//  Copyright © 2019 Mozilla Corporation.
//

import Foundation
import NetworkExtension
import RxSwift
import RxRelay

class GuardianTunnelManager: TunnelManaging {

    private(set) var cityChangedEvent = PublishSubject<VPNCity>()
    private(set) var stateEvent = BehaviorRelay<VPNState>(value: .off)
    private let accountManager = DependencyManager.shared.accountManager
    private var account: Account? {
        return accountManager.account
    }

    private var tunnel: NETunnelProviderManager?
    private let disposeBag = DisposeBag()

    var timeSinceConnected: Double {
        return Date().timeIntervalSince(tunnel?.connection.connectedDate ?? Date())
    }

    init() {
        loadTunnel { _ in
            guard let tunnel = self.tunnel else { return }
            self.stateEvent.accept(VPNState(with: tunnel.connection.status))
        }

        DispatchQueue.main.async {
            NotificationCenter.default.addObserver(self, selector: #selector(self.vpnStatusDidChange(notification:)), name: Notification.Name.NEVPNStatusDidChange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.vpnConfigurationDidChange(notification:)), name: Notification.Name.NEVPNConfigurationChange, object: nil)
        }

        subscribeToVersionUpdates()
    }

    private func subscribeToVersionUpdates() {
        //swiftlint:disable:next trailing_closure
        DependencyManager.shared.releaseMonitor.updateStatus
            .distinctUntilChanged()
            .filter { $0 == .required }
            .subscribe(onNext: { [weak self] _ in
                self?.stopAndRemove()
            }).disposed(by: disposeBag)
    }

    func connect(with device: Device?) -> Single<Void> {
        return Single<Void>.create { [unowned self] resolver in
            self.loadTunnel { error in
                if let error = error {
                    Logger.global?.log(message: "Connect Tunnel Load Error: \(error)")
                    resolver(.error(error))
                    return
                }
                let tunnelProviderManager = self.tunnel ?? NETunnelProviderManager()
                guard let device = device,
                    let account = self.account,
                    let city = self.accountManager.selectedCity else { return }

                tunnelProviderManager.setNewConfiguration(for: device,
                                                          city: city,
                                                          key: account.privateKey)
                tunnelProviderManager.isEnabled = true

                tunnelProviderManager.saveToPreferences { [unowned self] saveError in
                    if let error = saveError {
                        self.tunnel = nil
                        Logger.global?.log(message: "Connect Tunnel Save Error: \(error)")
                        resolver(.error(error))
                        return
                    }
                    self.tunnel = tunnelProviderManager
                    self.tunnel?.loadFromPreferences { error in
                        if let error = error {
                            Logger.global?.log(message: "Connect Tunnel Load Error: \(error)")
                            resolver(.error(error))
                            return
                        }
                        do {
                            try self.startTunnel()
                            resolver(.success(()))
                        } catch {
                            Logger.global?.log(message: "Connect Tunnel Start Error: \(error)")
                            resolver(.error(error))
                        }
                    }
                }
            }
            return Disposables.create()
        }
    }

    func switchServer(with device: Device) -> Single<Void> {
        return Single<Void>.create { [unowned self] resolver in
            guard let tunnel = self.tunnel else {
                self.connect(with: device)
                    .subscribe { error in
                        resolver(.error(error))
                }.disposed(by: self.disposeBag)

                return Disposables.create()
            }

            if self.stateEvent.value != .off {
                let cityName = tunnel.localizedDescription ?? ""
                let newCityName = self.accountManager.selectedCity?.name ?? ""
                self.stateEvent.accept(.switching(cityName, newCityName))
            }
            guard let account = self.account,
                let newCity = self.accountManager.selectedCity else {
                    resolver(.error(GuardianAppError.needToLogin))
                    return Disposables.create()
            }
            tunnel.setNewConfiguration(for: device,
                                       city: newCity,
                                       key: account.privateKey)

            tunnel.saveToPreferences { saveError in
                if let error = saveError {
                    if case .switching(_, _) = self.stateEvent.value {
                        self.stateEvent.accept(.on)
                    }
                    Logger.global?.log(message: "Switch Tunnel Save Error: \(error)")
                    resolver(.error(error))
                    return
                }

                tunnel.loadFromPreferences { error in
                    if let error = error {
                        Logger.global?.log(message: "Switch Tunnel Load Error: \(error)")
                        resolver(.error(error))
                        return
                    }

                    resolver(.success(()))
                }
            }
            return Disposables.create()
        }
    }

    func getReceivedBytes(completionHandler: @escaping ((UInt?) -> Void)) {
        guard stateEvent.value != .off,
            let session = tunnel?.connection as? NETunnelProviderSession
        else {
            completionHandler(nil)
            return
        }

        do {
            try session.sendProviderMessage(Data([UInt8(0)])) { [weak self] data in
                guard self?.stateEvent.value != .off,
                    let data = data,
                    let configString = String(data: data, encoding: .utf8)
                else {
                    completionHandler(nil)
                    return
                }

                let config: [String: String] = {
                    var dict = [String: String]()
                    configString
                        .splitToArray(separator: "\n")
                        .forEach {
                            let keyValuePair = $0.splitToArray(separator: "=")
                            dict[keyValuePair[0]] = keyValuePair[1]
                    }

                    return dict
                }()

                guard let rxBytes = config["rx_bytes"] else {
                    completionHandler(nil)
                    return
                }

                completionHandler(UInt(rxBytes))
            }
        } catch {
            completionHandler(nil)
        }
    }

    private func startTunnel() throws {
        guard let tunnel = tunnel else { return }

        try (tunnel.connection as? NETunnelProviderSession)?.startTunnel()
    }

    private func loadTunnel(completion: ((Error?) -> Void)? = nil) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let self = self, error == nil {
                self.tunnel = managers?.first { $0.localizedDescription == self.accountManager.selectedCity?.name }
            }
            completion?(error)
        }
    }

    func stop() {
        guard let tunnel = tunnel else { return }
        (tunnel.connection as? NETunnelProviderSession)?.stopTunnel()
    }

    func stopAndRemove() {
        guard let tunnel = tunnel else { return }
        stop()
        tunnel.removeFromPreferences { error in
            if let error = error {
                Logger.global?.log(message: "Tunnel Removal Error: \(error)")
            }
            self.tunnel = nil
            NETunnelProviderManager.loadAllFromPreferences { _, _ in }
        }
        Logger.global?.log(message: "Tunnel Stopped and Removed")
    }

    @objc private func vpnConfigurationDidChange(notification: Notification) {
        if case .switching(_, _) = stateEvent.value {
            stop()
        }
    }

    @objc private func vpnStatusDidChange(notification: Notification) {
        guard let session = (notification.object as? NETunnelProviderSession), tunnel?.connection == session else { return }

        if case .switching(_, _) = stateEvent.value {
            switch session.status {
            case .disconnecting, .connecting:
                return
            case .disconnected:
                do {
                    try startTunnel()
                } catch {
                    NotificationCenter.default.post(Notification(name: .switchServerError))
                }
                return
            default:
                break
            }
        }
        stateEvent.accept(VPNState(with: session.status))
    }
}

private extension NETunnelProviderManager {
    func setNewConfiguration(for device: Device, city: VPNCity, key: Data) {
        guard let newConfiguration = TunnelConfigurationBuilder.createTunnelConfiguration(device: device, city: city, privateKey: key) else { return }

        self.protocolConfiguration = NETunnelProviderProtocol(tunnelConfiguration: newConfiguration)
        self.localizedDescription = newConfiguration.name ?? city.name
    }
}