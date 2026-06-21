//
//  BalanceAccount.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import Foundation
import SwiftData

@Model
final class BalanceAccount {
    var id: UUID
    var accountNumber: String
    var accountCode: String
    var accountLabel: String
    var debit: Double
    var credit: Double
    var balanceN: Double
    var balanceNMinus1: Double
    var restaurant: Restaurant
    var sourceFile: String
    var importDate: Date
    
    init(
        id: UUID = UUID(),
        accountNumber: String,
        accountCode: String,
        accountLabel: String,
        debit: Double,
        credit: Double,
        balanceN: Double,
        balanceNMinus1: Double,
        restaurant: Restaurant,
        sourceFile: String,
        importDate: Date = Date()
    ) {
        self.id = id
        self.accountNumber = accountNumber
        self.accountCode = accountCode
        self.accountLabel = accountLabel
        self.debit = debit
        self.credit = credit
        self.balanceN = balanceN
        self.balanceNMinus1 = balanceNMinus1
        self.restaurant = restaurant
        self.sourceFile = sourceFile
        self.importDate = importDate
    }
    
    // Propriétés calculées utiles
    var accountClass: String {
        String(accountNumber.prefix(1))
    }
    
    var isFournisseur: Bool {
        accountNumber.hasPrefix("40")
    }
    
    var isClient: Bool {
        accountNumber.hasPrefix("41")
    }
    
    var isBanque: Bool {
        accountNumber.hasPrefix("51") || accountNumber.hasPrefix("53")
    }
}
