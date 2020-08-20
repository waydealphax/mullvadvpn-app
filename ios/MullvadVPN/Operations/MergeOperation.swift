//
//  MergeOperation.swift
//  TestingOperations
//
//  Created by pronebird on 27/08/2020.
//  Copyright © 2020 MullvadVPN AB. All rights reserved.
//

import Foundation

class MergeOperation<A, B, Output>: AsyncOperation, OutputOperation
    where A: OutputOperation, B: OutputOperation
{
    private let operationA: A
    private let operationB: B

    private let transformBlock: (A.Output, B.Output) -> Output

    init(_ operationA: A, _ operationB: B, block: @escaping (A.Output, B.Output) -> Output) {
        self.operationA = operationA
        self.operationB = operationB
        transformBlock = block

        super.init()

        [operationA, operationB].forEach { addDependency($0) }
    }

    override func main() {
        switch (operationA.output.value, operationB.output.value) {
        case let (a?, b?):
            finish(with: transformBlock(a, b))
        default:
            finish(error: OperationError.inputRequirement)
        }
    }
}

class Merge3Operation<A, B, C, Output>: AsyncOperation, OutputOperation
    where A: OutputOperation, B: OutputOperation, C: OutputOperation
{
    private let operationA: A
    private let operationB: B
    private let operationC: C

    private let transformBlock: (A.Output, B.Output, C.Output) -> Output

    init(_ operationA: A, _ operationB: B, _ operationC: C, block: @escaping (A.Output, B.Output, C.Output) -> Output) {
        self.operationA = operationA
        self.operationB = operationB
        self.operationC = operationC
        transformBlock = block

        super.init()

        [operationA, operationB, operationC].forEach { addDependency($0) }
    }

    override func main() {
        switch (operationA.output.value, operationB.output.value, operationC.output.value) {
        case let (a?, b?, c?):
            finish(with: transformBlock(a, b, c))
        default:
            finish(error: OperationError.inputRequirement)
        }
    }
}
