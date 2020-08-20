//
//  GroupOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 20/08/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

import Foundation

class GroupOperation: AsyncOperation {
    private let operationQueue = OperationQueue()
    private let childLock = NSRecursiveLock()
    private var children: Set<Operation> = []
    private var childError: Error?

    init(underlyingQueue: DispatchQueue? = nil, operations: [Operation]) {
        operationQueue.underlyingQueue = underlyingQueue
        operationQueue.isSuspended = true

        super.init()

        addChildren(operations)
    }

    deinit {
        operationQueue.cancelAllOperations()
        operationQueue.isSuspended = false
    }

    override func main() {
        operationQueue.isSuspended = false
    }

    override func operationDidCancel(error: Error?) {
        children.forEach { $0.cancel() }
    }

    final func addChildren(_ operations: [Operation]) {
        childLock.withCriticalBlock {
            precondition(!self.isFinished, "Children cannot be added after the GroupOperation has finished.")

            self.children.formUnion(operations)

            let completionOperation = BlockOperation { [weak self] in
                self?._childrenDidFinish(operations)
            }

            operations.forEach { completionOperation.addDependency($0) }

            self.operationQueue.addOperations(operations, waitUntilFinished: false)
            self.operationQueue.addOperation(completionOperation)
        }
    }

    func childrenDidFinish(_ children: [Operation]) {
        // Override in subclasses
    }

    // MARK: - Private

    private func _childrenDidFinish(_ finishedChildren: [Operation]) {
        childLock.withCriticalBlock {
            self.children.subtract(finishedChildren)

            // Collect the first child error
            if childError == nil {
                let childErrors = finishedChildren.compactMap { (op) -> Error? in
                    return (op as? OperationProtocol)?.error
                }
                childError = childErrors.first
            }

            // Notify subclass
            self.childrenDidFinish(finishedChildren)

            if self.children.isEmpty {
                self.finish(error: childError)
            }
        }
    }
}

class GroupOutputOperation<Output>: GroupOperation, OutputOperation {

    private let transformBlock: ([Operation]) -> Output?

    init(underlyingQueue: DispatchQueue? = nil, operations: [Operation], transformBlock: @escaping ([Operation]) -> Output?) {
        self.transformBlock = transformBlock
        super.init(underlyingQueue: underlyingQueue, operations: operations)
    }

    override func childrenDidFinish(_ children: [Operation]) {
        if let outputValue = transformBlock(children) {
            self.output = .ready(outputValue)
        }
    }
}
