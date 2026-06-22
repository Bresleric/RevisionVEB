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
    case tresorerie      = "B - Trésorerie et financements"
    case clients         = "C - Clients / Ventes"
    case regularisation  = "D - Régularisation et cut-off"
    case fournisseurs    = "E - Fournisseurs / Achats"
    case stocks          = "F - Stocks et en-cours"
    case immobilisations = "G - Immobilisations"
    case personnel       = "H - Personnel et social"
    case fiscal          = "I - Fiscal"
    case provisions      = "J - Provisions et risques"
    case capitaux        = "K - Capitaux propres"
    case autresBilan     = "L - Autres comptes du bilan"
    case groupe          = "M - Groupe et parties liées"
    case nonClasse       = "Z - Non classé"

    var id: String { rawValue }

    /// Lettre du cycle (B, C, D...)
    var letter: String { String(rawValue.prefix(1)) }

    /// Nom court sans la lettre (ex: "Trésorerie et financements")
    var shortName: String {
        guard let range = rawValue.range(of: " - ") else { return rawValue }
        return String(rawValue[range.upperBound...])
    }

    var icon: String {
        switch self {
        case .tresorerie:      return "banknote"
        case .clients:         return "person.crop.circle.badge.checkmark"
        case .regularisation:  return "calendar.badge.clock"
        case .fournisseurs:    return "building.2"
        case .stocks:          return "shippingbox"
        case .immobilisations: return "wrench.and.screwdriver"
        case .personnel:       return "person.2"
        case .fiscal:          return "doc.text"
        case .provisions:      return "exclamationmark.shield"
        case .capitaux:        return "building.columns"
        case .autresBilan:     return "tray.2"
        case .groupe:          return "person.3"
        case .nonClasse:       return "questionmark.folder"
        }
    }

    /// Determine le cycle a partir du numero de compte (nomenclature cabinet B-M).
    static func forAccount(_ accountNumber: String) -> RevisionCycle {
        let s = accountNumber.trimmingCharacters(in: .whitespaces)
        let p1 = String(s.prefix(1))
        let p2 = String(s.prefix(2))
        let p3 = String(s.prefix(3))

        // 1) Comptes specifiques prioritaires (avant les regles de classe)
        // D - Regularisation / cut-off : FNP (408), FAE (418), CCA (486), PCA (487)
        if ["408", "418", "486", "487"].contains(p3) { return .regularisation }
        // M - Groupe / comptes courants associes (451, 455, 456, 458)
        if ["451", "455", "456", "458"].contains(p3) { return .groupe }
        // F - Variation de stocks (603) rattachee au cycle Stocks
        if p3 == "603" { return .stocks }

        // 2) Classes du bilan
        switch p2 {
        case "10", "11", "12", "13", "14": return .capitaux       // K
        case "15":                          return .provisions     // J
        case "16", "17":                    return .tresorerie     // B (financements)
        default: break
        }
        switch p1 {
        case "2": return .immobilisations    // G (20-29)
        case "3": return .stocks             // F (31-39)
        case "5": return .tresorerie         // B (50-59)
        default: break
        }
        switch p2 {
        case "40": return .fournisseurs              // E
        case "41": return .clients                   // C
        case "42", "43": return .personnel           // H
        case "44": return .fiscal                    // I
        case "45", "46", "47", "48": return .autresBilan // L
        default: break
        }

        // 3) Classe 6 - charges (rattachees au cycle du poste)
        switch p2 {
        case "60", "61", "62": return .fournisseurs  // E (achats & charges externes)
        case "63": return .fiscal                     // I (impots & taxes)
        case "64": return .personnel                  // H
        case "66": return .tresorerie                 // B (charges financieres)
        case "68": return .immobilisations            // G (dotations amortissements)
        case "69": return .fiscal                     // I (IS, participation)
        case "65", "67": return .autresBilan          // L (autres / exceptionnel)
        default: break
        }

        // 4) Classe 7 - produits
        switch p2 {
        case "70", "71", "72", "74": return .clients  // C
        case "76": return .tresorerie                  // B (produits financiers)
        case "78": return .immobilisations             // G (reprises amortissements)
        case "75", "77", "79": return .autresBilan     // L
        default: break
        }

        // 5) Reste de la classe 1 (18 comptes de liaison...) -> Capitaux
        if p1 == "1" { return .capitaux }

        return .nonClasse
    }
}
