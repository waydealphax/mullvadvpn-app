//
//  PacketTunnelProvider.swift
//  PacketTunnel
//
//  Created by pronebird on 19/03/2019.
//  Copyright © 2019 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Network
import NetworkExtension
import Logging

enum PacketTunnelProviderError: ChainedError {
    /// Failure to process a tunnel command as it was unexpected.
    case unexpectedTunnelCommand

    /// Failure to read the relay cache
    case readRelayCache(RelayCacheError)

    /// Failure to satisfy the relay constraint
    case noRelaySatisfyingConstraint

    /// Missing the persistent keychain reference to the tunnel settings
    case missingKeychainConfigurationReference

    /// Failure to read the tunnel settings from Keychain
    case cannotReadTunnelSettings(TunnelSettingsManager.Error)

    /// Failure to set network settings
    case setNetworkSettings(Error)

    /// Failure to start the Wireguard backend
    case startWireguardDevice(WireguardDevice.Error)

    /// Failure to stop the Wireguard backend
    case stopWireguardDevice(WireguardDevice.Error)

    /// Failure to update the Wireguard configuration
    case updateWireguardConfiguration(Error)

    /// IPC handler failure
    case ipcHandler(PacketTunnelIpcHandler.Error)

    var errorDescription: String? {
        switch self {
        case .readRelayCache:
            return "Failure to read the relay cache"

        case .noRelaySatisfyingConstraint:
            return "No relay satisfying the given constraint"

        case .missingKeychainConfigurationReference:
            return "Invalid protocol configuration"

        case .cannotReadTunnelSettings:
            return "Failure to read tunnel settings"

        case .setNetworkSettings:
            return "Failure to set system network settings"

        case .startWireguardDevice:
            return "Failure to start the WireGuard device"

        case .stopWireguardDevice:
            return "Failure to stop the WireGuard device"

        case .updateWireguardConfiguration:
            return "Failure to update the Wireguard configuration"

        case .ipcHandler:
            return "Failure to handle the IPC request"

        case .unexpectedTunnelCommand:
            return "Unexpected tunnel command"
        }
    }
}

struct PacketTunnelConfiguration {
    var persistentKeychainReference: Data
    var tunnelSettings: TunnelSettings
    var selectorResult: RelaySelectorResult
}

extension PacketTunnelConfiguration {
    var wireguardConfig: WireguardConfiguration {
        let mullvadEndpoint = selectorResult.endpoint
        var peers: [AnyIPEndpoint] = [.ipv4(mullvadEndpoint.ipv4Relay)]

        if let ipv6Relay = mullvadEndpoint.ipv6Relay {
            peers.append(.ipv6(ipv6Relay))
        }

        let wireguardPeers = peers.map {
            WireguardPeer(
                endpoint: $0,
                publicKey: selectorResult.endpoint.publicKey)
        }

        return WireguardConfiguration(
            privateKey: tunnelSettings.interface.privateKey,
            peers: wireguardPeers,
            allowedIPs: [
                IPAddressRange(address: IPv4Address.any, networkPrefixLength: 0),
                IPAddressRange(address: IPv6Address.any, networkPrefixLength: 0)
            ]
        )
    }
}

struct StartTunnelResult {
    let wireguardDevice: WireguardDevice
    let automaticKeyRotationManager: AutomaticKeyRotationManager
    let packetTunnelConfiguration: PacketTunnelConfiguration
}

struct TunnelContext {
    let wireguardDevice: WireguardDevice
    let keyRotationManager: AutomaticKeyRotationManager
}

class PacketTunnelProvider: NEPacketTunnelProvider {

    enum OperationCategory {
        case exclusive
    }

    /// Tunnel provider logger
    private let logger: Logger

    /// Active wireguard device
    private var wireguardDevice: WireguardDevice?

    /// Active tunnel connection information
    private var connectionInfo: TunnelConnectionInfo?

    /// Internal queue
    private let dispatchQueue = DispatchQueue(label: "net.mullvad.MullvadVPN.PacketTunnel", qos: .utility)

    private lazy var operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.underlyingQueue = self.dispatchQueue
        return operationQueue
    }()

    private lazy var exclusivityController: ExclusivityController<OperationCategory> = {
        return ExclusivityController(operationQueue: self.operationQueue)
    }()

    private var keyRotationManager: AutomaticKeyRotationManager?

    override init() {
        initLoggingSystem(bundleIdentifier: Bundle.main.bundleIdentifier!)
        WireguardDevice.setTunnelLogger(Logger(label: "WireGuard"))

        logger = Logger(label: "PacketTunnelProvider")
    }

    // MARK: - Subclass

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let operation = self.makeStartTunnelOperation { (result, error) in
            if let result = result {
                self.dispatchQueue.async {
                    self.wireguardDevice = result.wireguardDevice
                    self.keyRotationManager = result.automaticKeyRotationManager
                    self.setTunnelConnectionInfo(selectorResult: result.packetTunnelConfiguration.selectorResult)

                    self.logger.info("Started the tunnel")

                    completionHandler(nil)
                }
            } else {
                if let chainedError = error as? ChainedError {
                    self.logger.error(chainedError: chainedError, message: "Failed to start the tunnel")
                } else {
                    self.logger.error("Failed to start the tunnel: \(error?.localizedDescription ?? "No error")")
                }

                completionHandler(error)
            }
        }

        self.exclusivityController.addOperation(operation, categories: [.exclusive])
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        self.logger.info("Stop the tunnel. Reason: \(reason)")

        let operation = self.makeStopTunnelOperation { (error) in
            self.logger.info("Stopped the tunnel")

            completionHandler()
        }

        self.exclusivityController.addOperation(operation, categories: [.exclusive])
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        dispatchQueue.async {
            let decodeResult = PacketTunnelIpcHandler.decodeRequest(messageData: messageData)
                .mapError { PacketTunnelProviderError.ipcHandler($0) }

            switch decodeResult {
            case .success(let request):
                switch request {
                case .reloadTunnelSettings:
                    self.reloadTunnelSettings { (result) in
                        self.replyAppMessage(result.map { true }, completionHandler: completionHandler)
                    }

                case .tunnelInformation:
                    self.replyAppMessage(.success(self.connectionInfo), completionHandler: completionHandler)
                }

            case .failure(let error):
                self.replyAppMessage(Result<String, PacketTunnelProviderError>.failure(error), completionHandler: completionHandler)
            }
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }

    override func wake() {
        // Add code here to wake up.
    }

    // MARK: - Tunnel management

    private func makeStartTunnelOperation(completionHandler: @escaping (StartTunnelResult?, Error?) -> Void) -> GroupOperation {
        let makeTunnelConfigOperation = MakePacketTunnelConfigurationOperation(passwordReference: protocolConfiguration.passwordReference)
        let networkSettingsOperation = SetTunnelNetworkSettingsOperation(tunnelProvider: self).inject(from: makeTunnelConfigOperation) { (output) -> InjectionResult<NETunnelNetworkSettings> in
            switch output {
            case .success(let tunnelConfig):
                let settingsGenerator = PacketTunnelSettingsGenerator(
                    mullvadEndpoint: tunnelConfig.selectorResult.endpoint,
                    tunnelSettings: tunnelConfig.tunnelSettings
                )
                return .success(settingsGenerator.networkSettings())

            case .failure(let error):
                // TODO: handle error?
                return .failure
            }
        }

        let startWireguardOperation = StartWireguardOperation(packetFlow: self.packetFlow)
            .inject(from: makeTunnelConfigOperation) { (output) -> InjectionResult<WireguardConfiguration> in
                switch output {
                case .success(let tunnelConfig):
                    return .success(tunnelConfig.wireguardConfig)
                case .failure(let error):
                    // TODO: handle error?
                    return .failure
                }
        }
        startWireguardOperation.addDependency(networkSettingsOperation)
        startWireguardOperation.setAllowDependencyFailuresAndCancellations(false)

        let startKeyRotationOperation = TransformOperation<Data, Result<AutomaticKeyRotationManager, PacketTunnelProviderError>>(input: protocolConfiguration.passwordReference) { (keychainReference, finish) in
            let keyRotationManager = AutomaticKeyRotationManager(persistentKeychainReference: keychainReference)

            keyRotationManager.eventHandler = { (keyRotationEvent) in
                self.dispatchQueue.async {
                    self.reloadTunnelSettings { (result) in
                        switch result {
                        case .success:
                            break
                        case .failure(let error):
                            self.logger.error(chainedError: error, message: "Failed to reload tunnel settings")
                        }
                    }
                }
            }

            keyRotationManager.startAutomaticRotation {
                finish(.success(keyRotationManager))
            }
        }
        startKeyRotationOperation.addDependency(startWireguardOperation)
        startKeyRotationOperation.setAllowDependencyFailuresAndCancellations(false)

        let startRelayCachePeriodicUpdatesOperation = AsyncBlockOperation { (finish) in
            RelayCache.shared.startPeriodicUpdates {
                finish()
            }
        }
        startRelayCachePeriodicUpdatesOperation.addDependency(startKeyRotationOperation)
        startRelayCachePeriodicUpdatesOperation.setAllowDependencyFailuresAndCancellations(false)

        let mergeResultsOperation = MergeResult3Operation(startWireguardOperation, startKeyRotationOperation, makeTunnelConfigOperation) { (wireguardDevice, keyRotationManager, tunnelConfig) -> Result<StartTunnelResult, PacketTunnelProviderError> in
            let result = StartTunnelResult(
                wireguardDevice: wireguardDevice,
                automaticKeyRotationManager: keyRotationManager,
                packetTunnelConfiguration: tunnelConfig
            )
            return .success(result)
        }

        let groupOperation = GroupOutputOperation(operations: [
            makeTunnelConfigOperation,
            networkSettingsOperation,
            startWireguardOperation,
            startKeyRotationOperation,
            startRelayCachePeriodicUpdatesOperation,
            mergeResultsOperation
        ]) { (children) -> Result<StartTunnelResult, PacketTunnelProviderError>? in
            self.logger.info("MergeResults value: \(mergeResultsOperation.output)")
            return mergeResultsOperation.output.value
        }

        groupOperation.addWillFinishBlockObserver { (op, error) in
            do {
                let result = try op.output.value?.get()

                completionHandler(result, error)
            } catch {
                completionHandler(nil, error)
            }

        }

        return groupOperation
    }

    private func makeStopTunnelOperation(completionHandler: @escaping (Error?) -> Void) -> GroupOperation {
        let makeContextOperation = ResultOperation<TunnelContext, PacketTunnelProviderError> { (finish) in
            guard let wireguardDevice = self.wireguardDevice, let keyRotationManager = self.keyRotationManager else {
                finish(.failure(.unexpectedTunnelCommand))
                return
            }

            let context = TunnelContext(wireguardDevice: wireguardDevice, keyRotationManager: keyRotationManager)

            finish(.success(context))
        }

        let stopRelayUpdatesOperation = AsyncBlockOperation { (finish) in
            RelayCache.shared.stopPeriodicUpdates {
                finish()
            }
        }

        let stopKeyRotationOperation = TransformOperation<TunnelContext, Void> { (context, finish) in
            context.keyRotationManager.stopAutomaticRotation {
                finish(())
            }
        }.injectResult(from: makeContextOperation)

        stopKeyRotationOperation.addDependency(stopRelayUpdatesOperation)

        let stopWireguardOperation = TransformOperation<TunnelContext, Result<Void, PacketTunnelProviderError>> { (context, finish) in
            context.wireguardDevice.stop { (result) in
                self.dispatchQueue.async {
                    self.wireguardDevice = nil
                    self.keyRotationManager = nil

                    let result = result.mapError({ (error) -> PacketTunnelProviderError in
                        return .stopWireguardDevice(error)
                    })

                    finish(result)
                }
            }
        }.injectResult(from: makeContextOperation)

        stopWireguardOperation.addDependency(stopRelayUpdatesOperation)
        stopWireguardOperation.addDependency(stopKeyRotationOperation)

        let groupOperation = GroupOperation(operations: [
            makeContextOperation,
            stopRelayUpdatesOperation,
            stopKeyRotationOperation,
            stopWireguardOperation
        ])

        groupOperation.addWillFinishBlockObserver { (op, error) in
            completionHandler(error)
        }

        return groupOperation
    }

    private func makeReloadTunnelSettingsOperation(completionHandler: @escaping (Error?) -> Void) -> GroupOperation {
        let makeInputOperation = ResultOperation<WireguardDevice, PacketTunnelProviderError> { () -> Result<WireguardDevice, PacketTunnelProviderError> in
            return self.wireguardDevice.map { .success($0) } ?? .failure(.unexpectedTunnelCommand)
        }

        let makeTunnelConfigOperation = MakePacketTunnelConfigurationOperation(passwordReference: protocolConfiguration.passwordReference)

        let networkSettingsOperation = SetTunnelNetworkSettingsOperation(tunnelProvider: self).inject(from: makeTunnelConfigOperation) { (output) -> InjectionResult<NETunnelNetworkSettings> in
            switch output {
            case .success(let tunnelConfig):
                let settingsGenerator = PacketTunnelSettingsGenerator(
                    mullvadEndpoint: tunnelConfig.selectorResult.endpoint,
                    tunnelSettings: tunnelConfig.tunnelSettings
                )
                
                return .success(settingsGenerator.networkSettings())

            case .failure(let error):
                // TODO: handle error?
                return .failure
            }
        }

        let mergeWireguardDeviceAndSettingsOperation = MergeResultOperation(makeInputOperation, makeTunnelConfigOperation) { (a, b) -> Result<(WireguardDevice, WireguardConfiguration), PacketTunnelProviderError> in
            return .success((a, b.wireguardConfig))
        }

        let setWireguardSettingsOperation = TransformOperation<(WireguardDevice, WireguardConfiguration), Result<(), PacketTunnelProviderError>> { (input: (WireguardDevice, WireguardConfiguration), finish) in
            let (device, config) = input
            device.setConfiguration(config) { (result) in
                finish(result.mapError({ (error) -> PacketTunnelProviderError in
                    return .updateWireguardConfiguration(error)
                }))
            }
        }.injectResult(from: mergeWireguardDeviceAndSettingsOperation)

        let startReassertingOperation = TransformOperation<PacketTunnelConfiguration, Void> { (tunnelConfig, finish) in
            self.setTunnelConnectionInfo(selectorResult: tunnelConfig.selectorResult)

            self.reasserting = true
        }.injectResult(from: makeTunnelConfigOperation)

        let stopReassertingOperation = AsyncBlockOperation {
            self.reasserting = false
        }
        stopReassertingOperation.addDependency(setWireguardSettingsOperation)

        let groupOperation = GroupOperation(operations: [
            makeInputOperation,
            makeTunnelConfigOperation,
            networkSettingsOperation,
            mergeWireguardDeviceAndSettingsOperation,
            setWireguardSettingsOperation,
            startReassertingOperation,
            stopReassertingOperation
        ])

        groupOperation.addWillFinishBlockObserver { (op, error) in
            completionHandler(error)
        }

        return groupOperation
    }

    // MARK: - Private

    private func replyAppMessage<T: Codable>(
        _ result: Result<T, PacketTunnelProviderError>,
        completionHandler: ((Data?) -> Void)?) {
        let result = result.flatMap { (response) -> Result<Data, PacketTunnelProviderError> in
            return PacketTunnelIpcHandler.encodeResponse(response: response)
                .mapError { PacketTunnelProviderError.ipcHandler($0) }
        }

        switch result {
        case .success(let data):
            completionHandler?(data)

        case .failure(let error):
            self.logger.error(chainedError: error)
            completionHandler?(nil)
        }
    }

    private func setTunnelConnectionInfo(selectorResult: RelaySelectorResult) {
        self.connectionInfo = TunnelConnectionInfo(
            ipv4Relay: selectorResult.endpoint.ipv4Relay,
            ipv6Relay: selectorResult.endpoint.ipv6Relay,
            hostname: selectorResult.relay.hostname,
            location: selectorResult.location
        )

        logger.info("Tunnel connection info: \(selectorResult.relay.hostname)")
    }

    private func reloadTunnelSettings(completionHandler: @escaping (Result<(), PacketTunnelProviderError>) -> Void) {
        dispatchQueue.async {
            let operation = self.makeReloadTunnelSettingsOperation { (error) in
                self.logger.debug("Reloaded the tunnel.")

                // TODO: propagate error
                completionHandler(.success(()))
            }

            self.exclusivityController.addOperation(operation, categories: [.exclusive])
        }
    }

}

class MakePacketTunnelConfigurationOperation: AsyncOperation, InputOperation, OutputOperation {
    typealias Input = Data
    typealias Output = Result<PacketTunnelConfiguration, PacketTunnelProviderError>

    init(passwordReference: Data? = nil) {
        super.init()
        self.input = passwordReference.map { .ready($0) } ?? .pending
    }

    override func main() {
        guard case .ready(let passwordReference) = input else {
            finish(with: .failure(.missingKeychainConfigurationReference))
            return
        }

        Self.makePacketTunnelConfig(keychainReference: passwordReference) { (result) in
            self.finish(with: result)
        }
    }

    /// Returns a `PacketTunnelConfig` that contains the tunnel settings and selected relay
    private class func makePacketTunnelConfig(keychainReference: Data, completionHandler: @escaping (Result<PacketTunnelConfiguration, PacketTunnelProviderError>) -> Void) {
        switch Self.readTunnelSettings(keychainReference: keychainReference) {
        case .success(let tunnelSettings):
            Self.selectRelayEndpoint(relayConstraints: tunnelSettings.relayConstraints) { (result) in
                let result = result.map { (selectorResult) -> PacketTunnelConfiguration in
                    return PacketTunnelConfiguration(
                        persistentKeychainReference: keychainReference,
                        tunnelSettings: tunnelSettings,
                        selectorResult: selectorResult
                    )
                }
                completionHandler(result)
            }

        case .failure(let error):
            completionHandler(.failure(error))
        }
    }

    /// Read tunnel settings from Keychain
    private class func readTunnelSettings(keychainReference: Data) -> Result<TunnelSettings, PacketTunnelProviderError> {
        TunnelSettingsManager.load(searchTerm: .persistentReference(keychainReference))
            .mapError { PacketTunnelProviderError.cannotReadTunnelSettings($0) }
            .map { $0.tunnelSettings }
    }

    /// Load relay cache with potential networking to refresh the cache and pick the relay for the
    /// given relay constraints.
    private class func selectRelayEndpoint(relayConstraints: RelayConstraints, completionHandler: @escaping (Result<RelaySelectorResult, PacketTunnelProviderError>) -> Void) {
        RelayCache.shared.read { (result) in
            switch result {
            case .success(let cachedRelayList):
                let relaySelector = RelaySelector(relays: cachedRelayList.relays)

                if let selectorResult = relaySelector.evaluate(with: relayConstraints) {
                    completionHandler(.success(selectorResult))
                } else {
                    completionHandler(.failure(.noRelaySatisfyingConstraint))
                }

            case .failure(let error):
                completionHandler(.failure(.readRelayCache(error)))
            }
        }
    }
}

class SetTunnelNetworkSettingsOperation: AsyncOperation, InputOperation, OutputOperation {
    typealias Input = NETunnelNetworkSettings
    typealias Output = Result<(), Error>

    private let tunnelProvider: NEPacketTunnelProvider

    init(tunnelProvider: NEPacketTunnelProvider, tunnelSettings: NETunnelNetworkSettings? = nil) {
        self.tunnelProvider = tunnelProvider

        super.init()

        input = tunnelSettings.map { .ready($0) } ?? .pending
    }

    override func main() {
        guard case .ready(let tunnelSettings) = input else {
            finish(error: OperationError.inputRequirement)
            return
        }

        tunnelProvider.setTunnelNetworkSettings(tunnelSettings) { [weak self] (error) in
            guard let self = self, !self.isCancelled else { return }

            self.finish(with: error.map { .failure($0) } ?? .success(()))
        }
    }

    override func operationDidCancel(error: Error?) {
        finish()
    }
}

class StartWireguardOperation: AsyncOperation, InputOperation, OutputOperation {
    typealias Input = WireguardConfiguration
    typealias Output = Result<WireguardDevice, PacketTunnelProviderError>

    private let packetFlow: NEPacketTunnelFlow

    init(packetFlow: NEPacketTunnelFlow, configuration: WireguardConfiguration? = nil) {
        self.packetFlow = packetFlow

        super.init()
        input = configuration.map { .ready($0) } ?? .pending
    }

    override func main() {
        guard case .ready(let configuration) = input else {
            finish(error: OperationError.inputRequirement)
            return
        }

        switch WireguardDevice.fromPacketFlow(packetFlow) {
        case .success(let device):
            device.start(configuration: configuration) { (result) in
                self.finish(with: result.map({ (_) -> WireguardDevice in
                    return device
                }).mapError({ (error) -> PacketTunnelProviderError in
                    return .startWireguardDevice(error)
                }))
            }

        case .failure(let error):
            finish(with: .failure(.startWireguardDevice(error)))
        }
    }
}
