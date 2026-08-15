//
//  ModelsPendingItem.swift
//  RevisionVEB
//
//  Points en suspens : commentaires et taches a effectuer, rattaches a un cycle
//  de revision d'un exercice donne.
//

import Foundation
import SwiftData
import SwiftUI

/// Nature du point : simple observation ou travail a realiser.
///
/// Les libelles affiches sont « Note » et « Point en suspens ». Les valeurs
/// stockees restent « Commentaire » et « Tâche » : elles sont deja en base et
/// sur Supabase, les renommer invaliderait l'existant.
enum PendingKind: String, Codable, CaseIterable {
    case commentaire = "Commentaire"
    case tache       = "Tâche"

    /// Libelle affiche a l'utilisateur.
    var label: String {
        switch self {
        case .commentaire: return "Note"
        case .tache:       return "Point en suspens"
        }
    }

    var icon: String {
        switch self {
        case .commentaire: return "note.text"
        case .tache:       return "exclamationmark.bubble"
        }
    }

    var color: Color {
        switch self {
        case .commentaire: return .blue
        case .tache:       return .purple
        }
    }
}

/// Avancement du point en suspens.
enum PendingStatus: String, Codable, CaseIterable {
    case ouvert   = "Ouvert"
    case enCours  = "En cours"
    case resolu   = "Résolu"
    case sansSuite = "Sans suite"

    var icon: String {
        switch self {
        case .ouvert:    return "circle"
        case .enCours:   return "clock.fill"
        case .resolu:    return "checkmark.circle.fill"
        case .sansSuite: return "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ouvert:    return .orange
        case .enCours:   return .blue
        case .resolu:    return .green
        case .sansSuite: return .secondary
        }
    }

    /// Un point clos ne compte plus dans les points restants.
    var isClosed: Bool { self == .resolu || self == .sansSuite }
}

/// Priorite du point en suspens.
enum PendingPriority: String, Codable, CaseIterable {
    case basse   = "Basse"
    case normale = "Normale"
    case haute   = "Haute"

    var icon: String {
        switch self {
        case .basse:   return "arrow.down"
        case .normale: return "equal"
        case .haute:   return "exclamationmark.2"
        }
    }

    var color: Color {
        switch self {
        case .basse:   return .secondary
        case .normale: return .blue
        case .haute:   return .red
        }
    }

    /// Ordre de tri (haute en premier).
    var rank: Int {
        switch self {
        case .haute:   return 0
        case .normale: return 1
        case .basse:   return 2
        }
    }
}

/// Un point en suspens (commentaire ou tache) rattache a un cycle d'un exercice.
@Model
final class PendingItem {
    @Attribute(.unique) var id: UUID = UUID()
    var exerciceID: UUID = UUID()
    var cycleRaw: String = ""
    /// Compte auquel le point se rattache. Vide pour un point qui porte sur le
    /// cycle entier. Valeur par defaut : l'ajout reste une migration additive.
    var accountNumber: String = ""
    var titre: String = ""
    var detail: String = ""
    var typeRaw: String = PendingKind.commentaire.rawValue
    var statutRaw: String = PendingStatus.ouvert.rawValue
    var prioriteRaw: String = PendingPriority.normale.rawValue
    var responsable: String = ""
    var echeance: Date?
    var creeLe: Date = Date()
    var updatedAt: Date = Date()

    init(exerciceID: UUID,
         cycleRaw: String,
         accountNumber: String = "",
         titre: String = "",
         detail: String = "",
         type: PendingKind = .commentaire,
         statut: PendingStatus = .ouvert,
         priorite: PendingPriority = .normale,
         responsable: String = "",
         echeance: Date? = nil) {
        self.id = UUID()
        self.exerciceID = exerciceID
        self.cycleRaw = cycleRaw
        self.accountNumber = accountNumber
        self.titre = titre
        self.detail = detail
        self.typeRaw = type.rawValue
        self.statutRaw = statut.rawValue
        self.prioriteRaw = priorite.rawValue
        self.responsable = responsable
        self.echeance = echeance
        self.creeLe = Date()
        self.updatedAt = Date()
    }

    var type: PendingKind {
        get { PendingKind(rawValue: typeRaw) ?? .commentaire }
        set { typeRaw = newValue.rawValue }
    }

    var statut: PendingStatus {
        get { PendingStatus(rawValue: statutRaw) ?? .ouvert }
        set { statutRaw = newValue.rawValue }
    }

    var priorite: PendingPriority {
        get { PendingPriority(rawValue: prioriteRaw) ?? .normale }
        set { prioriteRaw = newValue.rawValue }
    }

    var cycle: RevisionCycle? { RevisionCycle(rawValue: cycleRaw) }

    /// Echeance depassee sur un point encore ouvert.
    var isLate: Bool {
        guard let e = echeance, !statut.isClosed else { return false }
        return e < Calendar.current.startOfDay(for: Date())
    }
}
