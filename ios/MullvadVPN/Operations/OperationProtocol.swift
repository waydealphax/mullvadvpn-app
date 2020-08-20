//
//  OperationProtocol.swift
//  MullvadVPN
//
//  Created by pronebird on 06/07/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

import Foundation

protocol OperationProtocol: Operation {
    /// Operation error
    var error: Error? { get }

    /// Add operation observer
    func addObserver<T: OperationObserver>(_ observer: T) where T.OperationType == Self

    /// Finish operation with optional error
    func finish(error: Error?)

    /// Finish operation
    func finish()

    /// Cancele operation with optional error
    func cancel(error: Error?)

    /// Cancel operation
    func cancel()
}
