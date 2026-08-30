//
//  ModelsCentreProfit.swift
//  RevisionVEB
//
//  Rattachement des comptes aux centres de profit, pour eclater les soldes
//  intermediaires de gestion par etablissement.
//

import Foundation
import SwiftData

/// Centre de profit auquel un compte est rattache.
enum CentreProfit: String, Codable, CaseIterable, Identifiable {
    case freddy     = "F"
    case liesel     = "L"
    case commun     = "C"
    case dirigeants = "DIR"

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .freddy:     return "Freddy"
        case .liesel:     return "Chez Tante Liesel"
        case .commun:     return "Commun (réparti)"
        case .dirigeants: return "Dirigeants"
        }
    }

    /// Nom court, pour les en-tetes de colonnes.
    var court: String {
        switch self {
        case .freddy:     return "Freddy"
        case .liesel:     return "Liesel"
        case .commun:     return "Commun"
        case .dirigeants: return "Dirigeants"
        }
    }
}

/// Rattachement d'un compte a un centre de profit, avec sa cle de repartition.
///
/// Une charge commune n'appartient a aucun etablissement : elle se repartit.
/// `partLiesel` porte le pourcentage revenant a Liesel, Freddy prenant le
/// complement. La cle usuelle est 1/6 – 5/6, mais elle varie d'un compte a
/// l'autre : le linge (ELIS) se partage 40/60. Elle n'a de sens que pour un
/// compte commun ; elle est ignoree ailleurs.
///
/// Meme forme que `AccountCycleRule` : une regle par compte et par dossier,
/// qui survit aux reimports de balance.
@Model
final class CentreProfitRule {
    @Attribute(.unique) var id: UUID = UUID()
    var dossierID: UUID = UUID()
    var accountNumber: String = ""
    var centreRaw: String = CentreProfit.commun.rawValue
    /// Pourcentage revenant a Liesel quand le compte est commun.
    var partLiesel: Double = 16.67
    var updatedAt: Date = Date.distantPast

    init(id: UUID = UUID(), dossierID: UUID, accountNumber: String,
         centre: CentreProfit = .commun, partLiesel: Double = 16.67) {
        self.id = id
        self.dossierID = dossierID
        self.accountNumber = accountNumber
        self.centreRaw = centre.rawValue
        self.partLiesel = partLiesel
        self.updatedAt = Date()
    }

    var centre: CentreProfit {
        get { CentreProfit(rawValue: centreRaw) ?? .commun }
        set { centreRaw = newValue.rawValue }
    }

    func touch() { updatedAt = Date() }

    /// Identifiant derive de (dossier, compte) : les deux Macs produisent le
    /// meme, et un reimport de la table met a jour au lieu de dupliquer.
    @MainActor
    static func stableID(dossierID: UUID, accountNumber: String) -> UUID {
        SupabaseSync.stableID("centre-profit", dossierID.uuidString, accountNumber)
    }

    /// Ventilation d'un montant entre les deux etablissements.
    ///
    /// Renvoie le couple (Freddy, Liesel). Un compte propre a un etablissement
    /// lui verse la totalite ; un compte commun se partage selon la cle ; les
    /// comptes dirigeants ne sont imputes ni a l'un ni a l'autre.
    func ventile(_ montant: Double) -> (freddy: Double, liesel: Double) {
        switch centre {
        case .freddy:     return (montant, 0)
        case .liesel:     return (0, montant)
        case .dirigeants: return (0, 0)
        case .commun:
            let l = montant * partLiesel / 100
            return (montant - l, l)
        }
    }
}
