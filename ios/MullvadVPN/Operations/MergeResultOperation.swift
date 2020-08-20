//
//  MergeResultOperation.swift
//  TestingOperations
//
//  Created by pronebird on 27/08/2020.
//  Copyright © 2020 MullvadVPN AB. All rights reserved.
//

import Foundation

class MergeResultOperation<A, B, SuccessA, SuccessB, Success, Failure>: MergeOperation<A, B, Result<Success, Failure>>
    where A: OutputOperation, B: OutputOperation,
    A.Output == Result<SuccessA, Failure>,
    B.Output == Result<SuccessB, Failure>,
    Failure: Error
{
    typealias Output = Result<Success, Failure>

    init(_ operationA: A, _ operationB: B, block: @escaping (SuccessA, SuccessB) -> Output) {
        super.init(operationA, operationB) { (resultA, resultB) -> Result<Success, Failure> in
            do {
                return block(try resultA.get(), try resultB.get())
            } catch let error as Failure {
                return .failure(error)
            } catch {
                fatalError()
            }
        }
    }
}

class MergeResult3Operation<A, B, C, SuccessA, SuccessB, SuccessC, Success, Failure>:
    Merge3Operation<A, B, C, Result<Success, Failure>>
    where A: OutputOperation, B: OutputOperation, C: OutputOperation,
    A.Output == Result<SuccessA, Failure>,
    B.Output == Result<SuccessB, Failure>,
    C.Output == Result<SuccessC, Failure>,
    Failure: Error
{
    init(_ operationA: A, _ operationB: B, _ operationC: C, block: @escaping (SuccessA, SuccessB, SuccessC) -> Result<Success, Failure>) {
        super.init(operationA, operationB, operationC) { (resultA, resultB, resultC) -> Result<Success, Failure> in
            do {
                return block(try resultA.get(), try resultB.get(), try resultC.get())
            } catch let error as Failure {
                return .failure(error)
            } catch {
                fatalError()
            }
        }
    }

}
