//
//  InputOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 06/07/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

import Foundation

enum PendingValue<T> {
    case pending
    case ready(T)

    var value: T? {
        switch self {
        case .ready(let value):
            return value
        case .pending:
            return nil
        }
    }
}

enum InjectionResult<T> {
    case success(T)
    case failure
}

protocol InputOperation: OperationProtocol {
    associatedtype Input

    /// When overriding `input` in Subclasses, make sure to call `operationDidSetInput`
    var input: PendingValue<Input> { get set }

    func operationDidSetInput(_ input: Input)
}

private var kInputOperationAssociatedValue = 0
extension InputOperation where Self: OperationSubclassing {
    var input: PendingValue<Input> {
        get {
            return synchronized {
                return AssociatedValue.get(object: self, key: &kInputOperationAssociatedValue) ?? .pending
            }
        }
        set {
            synchronized {
                AssociatedValue.set(object: self, key: &kInputOperationAssociatedValue, value: newValue)

                if let newValue = newValue.value {
                    operationDidSetInput(newValue)
                }
            }
        }
    }

    func operationDidSetInput(_ input: Input) {
        // Override in subclasses
    }
}

extension InputOperation {

    @discardableResult func inject<Dependency>(from dependency: Dependency, via block: @escaping (Dependency.Output) -> InjectionResult<Input>) -> Self
        where Dependency: OutputOperation
    {
        let observer = OperationBlockObserver<Dependency>(willFinish: { [weak self] (operation, error) in
            guard let self = self else { return }

            if case .ready(let value)  = operation.output {
                switch block(value) {
                case .success(let input):
                    self.input = .ready(input)
                case .failure:
                    // Unable to produce input
                    break
                }
            }
        })
        dependency.addObserver(observer)
        addDependency(dependency)

        return self
    }

    @discardableResult func injectResult<Dependency>(from dependency: Dependency) -> Self
        where Dependency: OutputOperation, Dependency.Output == Input
    {
        return self.inject(from: dependency, via: { .success($0) })
    }

    /// Inject input from operation that outputs `Result<Input, Failure>`
    @discardableResult func injectResult<Dependency, Failure>(from dependency: Dependency) -> Self
        where Dependency: OutputOperation, Failure: Error, Dependency.Output == Result<Input, Failure>
    {
        return self.inject(from: dependency) { (output) -> InjectionResult<Input> in
            switch output {
            case .success(let value):
                return .success(value)
            case .failure:
                return .failure
            }
        }
    }
}
