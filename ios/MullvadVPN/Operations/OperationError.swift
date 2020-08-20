//
//  OperationError.swift
//  MullvadVPN
//
//  Created by pronebird on 24/08/2020.
//  Copyright © 2020 MullvadVPN AB. All rights reserved.
//

import Foundation

/// An error type describing common operation errors
enum OperationError: LocalizedError {
    /// A failure to satisfy the operation input requirement
    case inputRequirement

    /// A failure to proceed due to cancelled dependencies
    case cancelledDependencies

    /// A failure to proceed due to failed dependencies
    case failedDependencies

    var errorDescription: String? {
        switch self {
        case .inputRequirement:
            return "Input requirement not satisified"
        case .cancelledDependencies:
            return "Operation has cancelled dependencies"
        case .failedDependencies:
            return "Operation has failed dependencies"
        }
    }
}
