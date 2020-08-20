//
//  OperationBlockObserver.swift
//  MullvadVPN
//
//  Created by pronebird on 06/07/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

import Foundation

class OperationBlockObserver<OperationType: OperationProtocol>: OperationObserver {
    private var willExecute: ((OperationType) -> Void)?
    private var didExecute: ((OperationType) -> Void)?
    private var willFinish: ((OperationType, Error?) -> Void)?
    private var didFinish: ((OperationType, Error?) -> Void)?

    let queue: DispatchQueue?

    init(queue: DispatchQueue? = nil,
         willExecute: ((OperationType) -> Void)? = nil,
         didExecute: ((OperationType) -> Void)? = nil,
         willFinish: ((OperationType, Error?) -> Void)? = nil,
         didFinish: ((OperationType, Error?) -> Void)? = nil
    ) {
        self.queue = queue
        self.willExecute = willExecute
        self.didExecute = didExecute
        self.willFinish = willFinish
        self.didFinish = didFinish
    }

    func operationWillExecute(_ operation: OperationType) {
        if let willExecute = self.willExecute {
            scheduleEvent {
                willExecute(operation)
            }
        }
    }

    func operationDidExecute(_ operation: OperationType) {
        if let didExecute = self.didExecute {
            scheduleEvent {
                didExecute(operation)
            }
        }
    }

    func operationWillFinish(_ operation: OperationType, error: Error?) {
        if let willFinish = self.willFinish {
            scheduleEvent {
                willFinish(operation, error)
            }
        }
    }

    func operationDidFinish(_ operation: OperationType, error: Error?) {
        if let didFinish = self.didFinish {
            scheduleEvent {
                didFinish(operation, error)
            }
        }
    }

    private func scheduleEvent(_ body: @escaping () -> Void) {
        if let queue = queue {
            queue.async(execute: body)
        } else {
            body()
        }
    }
}

extension OperationProtocol {

    func addWillExecuteBlockObserver(queue: DispatchQueue? = nil, _ block: @escaping (Self) -> Void) {
        addObserver(OperationBlockObserver(queue: queue, willExecute: block))
    }

    func addDidExecuteBlockObserver(queue: DispatchQueue? = nil, _ block: @escaping (Self) -> Void) {
        addObserver(OperationBlockObserver(queue: queue, didExecute: block))
    }

    func addWillFinishBlockObserver(queue: DispatchQueue? = nil, _ block: @escaping (Self, Error?) -> Void) {
        addObserver(OperationBlockObserver(queue: queue, willFinish: block))
    }

    func addDidFinishBlockObserver(queue: DispatchQueue? = nil, _ block: @escaping (Self, Error?) -> Void) {
        addObserver(OperationBlockObserver(queue: queue, didFinish: block))
    }
}
