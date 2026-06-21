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

    /// Cycle par defaut (deduit automatiquement du numero de compte).
    var cycle: RevisionCycle {
        RevisionCycle.forAccount(accountNumber)
    }

    /// Cycle reel = override manuel s'il existe, sinon cycle automatique.
    func effectiveCycle(rules: [String: RevisionCycle]) -> RevisionCycle {
        rules[accountNumber] ?? RevisionCycle.forAccount(accountNumber)
    }
}

// MARK: - Regle d'affectation compte -> cycle (override manuel)

/// Permet a l'utilisateur de corriger le cycle d'un compte. Persiste independamment
/// des imports (une regle par numero de compte). Si aucune regle, on utilise le
/// cycle automatique deduit du numero de compte.
@Model
final class AccountCycleRule {
    @Attribute(.unique) var accountNumber: String
    var cycleRaw: String

    init(accountNumber: String, cycle: RevisionCycle) {
        self.accountNumber = accountNumber
        self.cycleRaw = cycle.rawValue
    }

    var cycle: RevisionCycle {
        get { RevisionCycle(rawValue: cycleRaw) ?? .nonClasse }
        set { cycleRaw = newValue.rawValue }
    }
}

// MARK: - Cycles de revision

/// Les cycles de revision comptable. Chaque compte est range dans un cycle
/// selon sa classe (prefixe du numero de compte), selon le Plan Comptable General.
enum RevisionCycle: String, Codable, CaseIterable, Identifiable {
    case capitaux               = "A - Capitaux & Financement"
    case immobilisations        = "B - Immobilisations"
    case stocks                 = "C - Stocks"
    case clients                = "D - Clients & Ventes"
    case fournisseurs           = "E - Fournisseurs & Achats"
    case fiscal                 = "F - État & Fiscal"
    case personnel              = "G - Personnel & Social"
    case tresorerie             = "H - Trésorerie"
    case tiersDivers            = "I - Comptes de tiers divers"
    case autresChargesProduits  = "J - Autres charges & produits"
    case nonClasse              = "Z - Non classé"

    var id: String { rawValue }

    /// Lettre du cycle (A, B, C...)
    var letter: String { String(rawValue.prefix(1)) }

    /// Nom court sans la lettre (ex: "Trésorerie")
    var shortName: String {
        guard let range = rawValue.range(of: " - ") else { return rawValue }
        return String(rawValue[range.upperBound...])
    }

    var icon: String {
        switch self {
        case .capitaux:              return "building.columns"
        case .immobilisations:       return "wrench.and.screwdriver"
        case .stocks:                return "shippingbox"
        case .clients:               return "person.crop.circle.badge.checkmark"
        case .fournisseurs:          return "building.2"
        case .fiscal:                return "doc.text"
        case .personnel:             return "person.2"
        case .tresorerie:            return "banknote"
        case .tiersDivers:           return "person.2.badge.gearshape"
        case .autresChargesProduits: return "arrow.left.arrow.right"
        case .nonClasse:             return "questionmark.folder"
        }
    }

    /// Determine le cycle a partir du numero de compte (classe PCG).
    static func forAccount(_ accountNumber: String) -> RevisionCycle {
        let trimmed = accountNumber.trimmingCharacters(in: .whitespaces)
        let p1 = String(trimmed.prefix(1))
        let p2 = String(trimmed.prefix(2))

        switch p1 {
        case "1": return .capitaux          // 10-18 : capitaux propres, emprunts
        case "2": return .immobilisations   // 20-28 : immos & amortissements
        case "3": return .stocks            // 3x : stocks
        case "5": return .tresorerie        // 5x : banques, caisse, virements
        case "4":
            switch p2 {
            case "40": return .fournisseurs
            case "41": return .clients
            case "42", "43": return .personnel
            case "44": return .fiscal
            default:   return .tiersDivers  // 45, 46, 47, 48, 49
            }
        case "6":
            switch p2 {
            case "60", "61", "62": return .fournisseurs
            case "63": return .fiscal
            case "64": return .personnel
            default:   return .autresChargesProduits // 65-69
            }
        case "7":
            switch p2 {
            case "70", "71", "72", "74": return .clients
            default:   return .autresChargesProduits // 75-79
            }
        default: return .nonClasse
        }
    }
}
