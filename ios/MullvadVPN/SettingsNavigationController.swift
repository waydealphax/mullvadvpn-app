//
//  SettingsNavigationController.swift
//  MullvadVPN
//
//  Created by pronebird on 02/07/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

import Foundation
import UIKit

enum SettingsNavigationRoute {
    case account
    case wireguardKeys
    case problemReport
}

enum SettingsDismissReason {
    case none
    case userLoggedOut
}

protocol SettingsNavigationControllerDelegate: class {
    func settingsNavigationController(_ controller: SettingsNavigationController, didFinishWithReason reason: SettingsDismissReason)
}

class SettingsNavigationController: CustomNavigationController, SettingsViewControllerDelegate, AccountViewControllerDelegate, UIAdaptivePresentationControllerDelegate {

    weak var settingsDelegate: SettingsNavigationControllerDelegate?

    init() {
        super.init(navigationBarClass: CustomNavigationBar.self, toolbarClass: nil)

        let settingsController = SettingsViewController()
        settingsController.delegate = self

        pushViewController(settingsController, animated: false)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationBar.barStyle = .black
        navigationBar.tintColor = .white
        navigationBar.prefersLargeTitles = true

        // Update account expiry
        Account.shared.updateAccountExpiry()
    }

    // MARK: - SettingsViewControllerDelegate

    func settingsViewControllerDidFinish(_ controller: SettingsViewController) {
        self.settingsDelegate?.settingsNavigationController(self, didFinishWithReason: .none)
    }

    // MARK: - AccountViewControllerDelegate

    func accountViewControllerDidLogout(_ controller: AccountViewController) {
        self.settingsDelegate?.settingsNavigationController(self, didFinishWithReason: .userLoggedOut)
    }

    // MARK: - Navigation

    func navigate(to route: SettingsNavigationRoute, animated: Bool) {
        switch route {
        case .account:
            let controller = AccountViewController()
            controller.delegate = self
            pushViewController(controller, animated: animated)

        case .wireguardKeys:
            pushViewController(WireguardKeysViewController(), animated: animated)

        case .problemReport:
            pushViewController(ProblemReportViewController(), animated: animated)
        }
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        settingsDelegate?.settingsNavigationController(self, didFinishWithReason: .none)
    }
}
