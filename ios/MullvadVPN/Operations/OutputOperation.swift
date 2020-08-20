//
//  OutputOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 06/07/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

import Foundation

protocol OutputOperation: OperationProtocol {
    associatedtype Output

    var output: PendingValue<Output> { get set }

    func finish(with output: Output)
}

extension OutputOperation {
    func finish(with output: Output) {
        // Extract error from the `Result<T, F>` output
        var error: Error?
        if let anyResult = output as? AnyResultProtocol {
            error = anyResult.error
        }

        self.output = .ready(output)
        self.finish(error: error)
    }
}

private var kOutputOperationAssociatedValue = 0
extension OutputOperation where Self: OperationSubclassing {
    var output: PendingValue<Output> {
        get {
            return synchronized {
                return AssociatedValue.get(object: self, key: &kOutputOperationAssociatedValue) ?? .pending
            }
        }
        set {
            synchronized {
                AssociatedValue.set(object: self, key: &kOutputOperationAssociatedValue, value: newValue)
            }
        }
    }
}

/// A type erasing `Result` protocol
private protocol AnyResultProtocol {
    var error: Error? { get }
}

extension Result: AnyResultProtocol {
    var error: Error? {
        switch self {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}
