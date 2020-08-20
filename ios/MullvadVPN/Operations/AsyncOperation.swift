//
//  AsyncOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 01/06/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

import Foundation

/// A base implementation of an asynchronous operation
class AsyncOperation: Operation, OperationProtocol {

    /// A state lock used for manipulating the operation state flags in a thread safe fashion.
    fileprivate let stateLock = NSRecursiveLock()

    /// A state transaction lock used to perform critical sections of code within `start`, `cancel`
    /// and `finish` calls.
    fileprivate let transactionLock = NSRecursiveLock()

    /// Operation error
    private var _error: Error?

    /// Operation dependency requirements
    private var _allowDependencyCancellations = true
    private var _allowDependencyFailures = true

    /// The operation observers.
    fileprivate var observers: [AnyOperationObserver<AsyncOperation>] = []

    /// Operation state flags.
    private var _isExecuting = false
    private var _isFinished = false
    private var _isCancelled = false

    // MARK: - Public

    final var error: Error? {
        return stateLock.withCriticalBlock { _error }
    }

    final var allowDependencyCancellations: Bool {
        get {
            stateLock.withCriticalBlock { _allowDependencyCancellations }
        }
        set {
            stateLock.withCriticalBlock { _allowDependencyCancellations = newValue }
        }
    }

    final var allowDependencyFailures: Bool {
        get {
            stateLock.withCriticalBlock { _allowDependencyFailures }
        }
        set {
            stateLock.withCriticalBlock {
                _allowDependencyFailures = newValue
            }
        }
    }

    final func setAllowDependencyFailuresAndCancellations(_ flag: Bool) {
        stateLock.withCriticalBlock {
            _allowDependencyCancellations = flag
            _allowDependencyFailures = flag
        }
    }

    final override var isExecuting: Bool {
        return stateLock.withCriticalBlock { _isExecuting }
    }

    final override var isFinished: Bool {
        return stateLock.withCriticalBlock { _isFinished }
    }

    final override var isCancelled: Bool {
        return stateLock.withCriticalBlock { _isCancelled }
    }

    final override var isAsynchronous: Bool {
        return true
    }

    final override func start() {
        transactionLock.withCriticalBlock {
            if isCancelled {
                finish()
            } else {
                switch checkDependencyRequirements() {
                case .success:
                    stateLock.withCriticalBlock {
                        self.observers.forEach { $0.operationWillExecute(self) }
                    }

                    setExecuting(true)
                    main()

                    stateLock.withCriticalBlock {
                        self.observers.forEach { $0.operationDidExecute(self) }
                    }

                case .failure(let operationError):
                    cancel(error: operationError)
                    finish()
                }
            }
        }
    }

    override func main() {
        // Override in subclasses
    }

    /// Cancel operation
    /// Subclasses should override `operationDidCancel` instead
    final override func cancel() {
        cancel(error: nil)
    }

    /// Cancel operation with error
    final func cancel(error: Error?) {
        transactionLock.withCriticalBlock {
            if isCancelled {
                super.cancel()
            } else {
                stateLock.withCriticalBlock {
                    if _error == nil {
                        _error = error
                    }
                }

                setCancelled(true)

                super.cancel()

                operationDidCancel(error: error)
            }
        }
    }

    /// Override in subclasses to support task cancellation.
    /// Subclasses should call `finish()` to complete the operation
    func operationDidCancel(error: Error?) {
        // no-op
    }

    final func finish() {
        finish(error: nil)
    }

    final func finish(error: Error?) {
        transactionLock.withCriticalBlock {
            guard !self.isFinished else { return }

            stateLock.withCriticalBlock {
                if _error == nil {
                    _error = error
                }

                observers.forEach { $0.operationWillFinish(self, error: _error) }
            }

            if self.isExecuting {
                setExecuting(false)
            }

            setFinished(true)

            stateLock.withCriticalBlock {
                observers.forEach { $0.operationDidFinish(self, error: _error) }
            }
        }
    }

    // MARK: - Private

    private func setExecuting(_ value: Bool) {
        willChangeValue(for: \.isExecuting)
        stateLock.withCriticalBlock { _isExecuting = value }
        didChangeValue(for: \.isExecuting)
    }

    private func setFinished(_ value: Bool) {
        willChangeValue(for: \.isFinished)
        stateLock.withCriticalBlock { _isFinished = value }
        didChangeValue(for: \.isFinished)
    }

    private func setCancelled(_ value: Bool) {
        willChangeValue(for: \.isCancelled)
        stateLock.withCriticalBlock { _isCancelled = value }
        didChangeValue(for: \.isCancelled)
    }

    private func checkDependencyRequirements() -> Result<(), OperationError> {
        let hasCancellations = dependencies.contains { $0.isCancelled }
        let hasFailures = dependencies.contains { (op) -> Bool in
            return (op as? OperationProtocol)?.error != nil
        }

        if !self.allowDependencyFailures && hasFailures {
            return .failure(.failedDependencies)
        }

        if !self.allowDependencyCancellations && hasCancellations {
            return .failure(.cancelledDependencies)
        }

        return .success(())
    }

    /// Add type-erased operation observer
    fileprivate func addAnyObserver(_ observer: AnyOperationObserver<AsyncOperation>) {
        stateLock.withCriticalBlock {
            observers.append(observer)
        }
    }
}

/// This extension exists because Swift has some issues to infer the
extension OperationProtocol where Self: AsyncOperation {
    func addObserver<T: OperationObserver>(_ observer: T) where T.OperationType == Self {
        let transform = TransformOperationObserver<AsyncOperation>(observer)
        let wrapped = AnyOperationObserver(transform)
        addAnyObserver(wrapped)
    }
}


protocol OperationSubclassing {
    /// Use this method in subclasses or extensions where you would like to synchronize
    /// the class members access using the same lock used for guarding from race conditions
    /// when managing operation state.
    func synchronized<T>(_ body: () -> T) -> T
}

extension AsyncOperation: OperationSubclassing {
    func synchronized<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
