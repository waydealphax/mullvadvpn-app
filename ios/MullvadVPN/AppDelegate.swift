//
//  AppDelegate.swift
//  MullvadVPN
//
//  Created by pronebird on 19/03/2019.
//  Copyright © 2019 Mullvad VPN AB. All rights reserved.
//

import UIKit
import StoreKit
import Logging

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var rootContainer: RootContainerViewController?

    #if targetEnvironment(simulator)
    let simulatorTunnelProvider = SimulatorTunnelProviderHost()
    #endif

    #if DEBUG
    private let packetTunnelLogForwarder = LogStreamer<UTF8>(fileURLs: [ApplicationConfiguration.packetTunnelLogFileURL!])
    #endif

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Setup logging
        initLoggingSystem(bundleIdentifier: Bundle.main.bundleIdentifier!)

        #if DEBUG
        let stdoutStream = TextFileOutputStream.standardOutputStream()
        packetTunnelLogForwarder.start { (str) in
            stdoutStream.write("\(str)\n")
        }
        #endif

        #if targetEnvironment(simulator)
        // Configure mock tunnel provider on simulator
        SimulatorTunnelProvider.shared.delegate = simulatorTunnelProvider
        #endif

        // Create an app window
        self.window = UIWindow(frame: UIScreen.main.bounds)

        // Set an empty view controller while loading tunnels
        let launchController = UIViewController()
        launchController.view.backgroundColor = .primaryColor
        self.window?.rootViewController = launchController

        // Update relays
        RelayCache.shared.updateRelays()

        // Load tunnels
        let accountToken = Account.shared.token
        TunnelManager.shared.loadTunnel(accountToken: accountToken) { (result) in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    fatalError(error.displayChain(message: "Failed to load the tunnel for account"))
                }

                switch UIDevice.current.userInterfaceIdiom {
                case .pad:
                    self.startPadInterfaceFlow()

                case .phone:
                    self.startPhoneInterfaceFlow()

                default:
                    fatalError()
                }
            }
        }

        // Show the window
        self.window?.makeKeyAndVisible()

        startPaymentQueueHandling()

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        TunnelManager.shared.refreshTunnelState(completionHandler: nil)
    }

    private func startPadInterfaceFlow() {
        let rootViewController = RootContainerViewController()
        rootViewController.delegate = self

        rootViewController.setViewControllers([ConnectViewController()], animated: false)

        self.window?.rootViewController = rootViewController
        self.rootContainer = rootViewController

        if !Account.shared.isAgreedToTermsOfService {
            let consentViewController = ConsentViewController()
            consentViewController.preferredContentSize = CGSize(width: 480, height: 600)
            consentViewController.modalPresentationStyle = .formSheet
            if #available(iOS 13.0, *) {
                consentViewController.isModalInPresentation = true
            }
            consentViewController.completionHandler = { [weak self] (viewController) in
                guard let self = self else { return }

                Account.shared.agreeToTermsOfService()
                
                if Account.shared.isLoggedIn {
                    viewController.dismiss(animated: true) {
                        self.showAccountControllerIfExpired()
                    }
                } else {
                    viewController.dismiss(animated: true) {
                        rootViewController.present(self.makeLoginControllerForPad(), animated: true)
                    }
                }
            }
            rootViewController.present(consentViewController, animated: true)
        } else if !Account.shared.isLoggedIn {
            rootViewController.present(makeLoginControllerForPad(), animated: true)
        }
    }

    private func makeLoginControllerForPad() -> LoginViewController {
        let controller = LoginViewController()
        controller.delegate = self
        controller.preferredContentSize = CGSize(width: 320, height: 400)
        controller.modalPresentationStyle = .formSheet
        if #available(iOS 13.0, *) {
            controller.isModalInPresentation = true
        }
        return controller
    }

    private func showAccountControllerIfExpired() {
        if let accountExpiry = Account.shared.expiry, AccountExpiry(date: accountExpiry).isExpired {
            rootContainer?.showSettings(navigateTo: .account, animated: true)
        }
    }

    private func startPhoneInterfaceFlow() {
        let rootViewController = RootContainerViewController()
        rootViewController.delegate = self

        let showMainController = { (_ animated: Bool) in
            let loginViewController = LoginViewController()
            loginViewController.delegate = self

            var viewControllers: [UIViewController] = [loginViewController]

            if Account.shared.isLoggedIn {
                viewControllers.append(ConnectViewController())
            }

            rootViewController.setViewControllers(viewControllers, animated: animated) {
                self.showAccountControllerIfExpired()
            }
        }

        if Account.shared.isAgreedToTermsOfService {
            showMainController(false)
        } else {
            let consentViewController = ConsentViewController()
            consentViewController.completionHandler = { _ in
                Account.shared.agreeToTermsOfService()

                showMainController(true)
            }

            rootViewController.setViewControllers([consentViewController], animated: false)
        }

        self.window?.rootViewController = rootViewController
        self.rootContainer = rootViewController
    }

    private func startPaymentQueueHandling() {
        let paymentManager = AppStorePaymentManager.shared
        paymentManager.delegate = self
        paymentManager.startPaymentQueueMonitoring()

        Account.shared.startPaymentMonitoring(with: paymentManager)
    }

}

extension AppDelegate: RootContainerViewControllerDelegate {

    func rootContainerViewControllerShouldShowSettings(_ controller: RootContainerViewController, navigateTo route: SettingsNavigationRoute?, animated: Bool) {
        let navController = SettingsNavigationController()
        navController.settingsDelegate = self

        if UIDevice.current.userInterfaceIdiom == .pad {
            navController.preferredContentSize = CGSize(width: 480, height: 568)
            navController.modalPresentationStyle = .formSheet
        }

        if let route = route {
            navController.navigate(to: route, animated: animated)
        }

        navController.presentationController?.delegate = navController
        controller.present(navController, animated: animated)
    }

    func rootContainerViewSupportedInterfaceOrientations(_ controller: RootContainerViewController) -> UIInterfaceOrientationMask {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return [.landscape, .portrait]
        case .phone:
            return [.portrait]
        default:
            fatalError("Not supported")
        }
    }
}

extension AppDelegate: LoginViewControllerDelegate {

    func loginViewControllerDidLogin(_ controller: LoginViewController) {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            rootContainer?.pushViewController(ConnectViewController(), animated: true) {
                self.showAccountControllerIfExpired()
            }
        case .pad:
            controller.dismiss(animated: true) {
                self.showAccountControllerIfExpired()
            }
        default:
            fatalError()
        }
    }

}

extension AppDelegate: SettingsNavigationControllerDelegate {

    func settingsNavigationController(_ controller: SettingsNavigationController, didFinishWithReason reason: SettingsDismissReason) {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            if case .userLoggedOut = reason {
                rootContainer?.popToRootViewController(animated: false)

                let loginController = rootContainer?.topViewController as? LoginViewController

                loginController?.reset()
            }
            controller.dismiss(animated: true)

        case .pad:
            controller.dismiss(animated: true) {
                if case .userLoggedOut = reason {
                    self.rootContainer?.present(self.makeLoginControllerForPad(), animated: true)
                }
            }

        default:
            fatalError()
        }

    }

}

extension AppDelegate: AppStorePaymentManagerDelegate {

    func appStorePaymentManager(_ manager: AppStorePaymentManager,
                                didRequestAccountTokenFor payment: SKPayment) -> String?
    {
        // Since we do not persist the relation between the payment and account token between the
        // app launches, we assume that all successful purchases belong to the active account token.
        return Account.shared.token
    }
}
