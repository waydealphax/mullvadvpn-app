//
//  OperationObserver.swift
//  MullvadVPN
//
//  Created by pronebird on 06/07/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

import Foundation

protocol OperationObserver {
    associatedtype OperationType: OperationProtocol

    func operationWillExecute(_ operation: OperationType)
    func operationDidExecute(_ operation: OperationType)
    func operationWillFinish(_ operation: OperationType, error: Error?)
    func operationDidFinish(_ operation: OperationType, error: Error?)
}

