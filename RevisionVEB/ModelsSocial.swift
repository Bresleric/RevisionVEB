//
//  ModelsSocial.swift
//  RevisionVEB
//
//  Cycle H — Personnel : rapprochement 641 / DSN
//

import Foundation
import SwiftData

// MARK: - Enums

enum SocialAnomalyType: String, Codable {
    case doubleEcriture = "DOUBLE_ECRITURE_PAIE"
    case odNonVentilee = "OD_NON_VENTILEE"
    case deductionDesequilibree = "DEDUCTION_AN_DESEQUILIBREE"
    case regulPeriodeAnterieure = "REGUL_PERIODE_ANTERIEURE"
    case ecartAssiette = "ECART_ASSIETTE_PRESTATAIRE"

    var label: String {
        switch self {
        case .doubleEcriture: "Double écriture de paie"
        case .odNonVentilee: "OD non ventilée"
        case .deductionDesequilibree: "Déduction AN déséquilibrée"
        case .regulPeriodeAnterieure: "Régularisation période antérieure"
        case .ecartAssiette: "Écart assiette prestataire"
        }
    }
}

enum ReconciliationStatus: String, Codable {
    case ok = "OK"
    case toCheck = "À VÉRIFIER"
    case toJustify = "À JUSTIFIER"

    var color: String {
        switch self {
        case .ok: "green"
        case .toCheck: "orange"
        case .toJustify: "red"
        }
    }
}

// MARK: - Payroll GL Entry

@Model
final class SocialPayrollEntry {
    @Attribute(.unique) var id: UUID
    var exerciceID: UUID
    var mois: Int  // 1-12
    var annee: Int // 2025, etc.
    var compte: String  // compte 641xxx
    var libelle: String
    var complement: String // référence lot OD-PAI-xxx ou vide
    var montant: Double  // débit - crédit
    var etablissement: String  // "LIESEL" ou "FREDDY"
    var siret: String
    var dateEcriture: Date
    var retenuDansAssiette: Bool
    var motifExclusion: String
    var sourceFile: String
    var importDate: Date

    init(
        exerciceID: UUID,
        mois: Int,
        annee: Int,
        compte: String,
        libelle: String,
        complement: String = "",
        montant: Double,
        etablissement: String,
        siret: String,
        dateEcriture: Date,
        retenuDansAssiette: Bool = true,
        motifExclusion: String = "",
        sourceFile: String = "",
        importDate: Date = Date()
    ) {
        self.id = UUID()
        self.exerciceID = exerciceID
        self.mois = mois
        self.annee = annee
        self.compte = compte
        self.libelle = libelle
        self.complement = complement
        self.montant = montant
        self.etablissement = etablissement
        self.siret = siret
        self.dateEcriture = dateEcriture
        self.retenuDansAssiette = retenuDansAssiette
        self.motifExclusion = motifExclusion
        self.sourceFile = sourceFile
        self.importDate = importDate
    }
}

// MARK: - DSN Assiette

@Model
final class DsnAssiette {
    @Attribute(.unique) var id: UUID
    var exerciceID: UUID
    var mois: Int
    var annee: Int
    var etablissement: String
    var siret: String
    var assietteBrute: Double
    var posteRetenu: String
    var ctp100d: Double?
    var fichierSource: String
    var dateExtraction: Date

    init(
        exerciceID: UUID,
        mois: Int,
        annee: Int,
        etablissement: String,
        siret: String,
        assietteBrute: Double,
        posteRetenu: String,
        ctp100d: Double? = nil,
        fichierSource: String,
        dateExtraction: Date = Date()
    ) {
        self.id = UUID()
        self.exerciceID = exerciceID
        self.mois = mois
        self.annee = annee
        self.etablissement = etablissement
        self.siret = siret
        self.assietteBrute = assietteBrute
        self.posteRetenu = posteRetenu
        self.ctp100d = ctp100d
        self.fichierSource = fichierSource
        self.dateExtraction = dateExtraction
    }
}

// MARK: - Social Reconciliation

@Model
final class SocialReconciliation {
    @Attribute(.unique) var id: UUID
    var exerciceID: UUID
    var mois: Int
    var annee: Int
    var etablissement: String
    var siret: String

    var soldeGL: Double
    var soldeGLDetails: String

    var soldeDisn: Double
    var posteDsnRetenu: String

    var ecart: Double
    var retraitement: Double
    var ecartResiduel: Double

    var statut: ReconciliationStatus
    var commentaire: String

    var dateCalcul: Date

    init(
        exerciceID: UUID,
        mois: Int,
        annee: Int,
        etablissement: String,
        siret: String
    ) {
        self.id = UUID()
        self.exerciceID = exerciceID
        self.mois = mois
        self.annee = annee
        self.etablissement = etablissement
        self.siret = siret
        self.soldeGL = 0.0
        self.soldeGLDetails = ""
        self.soldeDisn = 0.0
        self.posteDsnRetenu = ""
        self.ecart = 0.0
        self.retraitement = 0.0
        self.ecartResiduel = 0.0
        self.statut = .ok
        self.commentaire = ""
        self.dateCalcul = Date()
    }
}

// MARK: - Piece justificative rattachee a un cycle

/// Une piece du dossier rattachee a un cycle de revision.
///
/// Les pieces existantes sont toutes accrochees a un objet comptable precis —
/// un compte, une ligne de rapprochement, une facture. Il manquait le cas le
/// plus courant en revision : le document qui justifie un cycle entier, comme
/// la feuille de travail du rapprochement 641/DSN, ou les recapitulatifs DSN
/// qui la fondent.
///
/// `mois` et `etablissement` restent vides pour une piece annuelle ; ils sont
/// renseignes pour une piece mensuelle, ce qui permet de la relier a la ligne
/// d'assiette DSN correspondante.
///
/// Toutes les proprietes ont une valeur par defaut : l'ajout de ce modele est
/// une migration purement additive pour les bases existantes.
@Model
final class CyclePiece {
    @Attribute(.unique) var id: UUID = UUID()
    var exerciceID: UUID = UUID()
    var cycleRaw: String = ""        // RevisionCycle.rawValue
    var categorie: String = ""       // "Feuille de travail", "Récapitulatif DSN"...
    var libelle: String = ""
    var mois: Int = 0                // 0 = piece annuelle
    var annee: Int = 0
    var etablissement: String = ""
    var docName: String = ""
    var docPath: String = ""
    var docBookmark: Data? = nil
    var note: String = ""
    var ordre: Int = 0
    var ajouteLe: Date = Date()

    init(
        id: UUID = UUID(),
        exerciceID: UUID,
        cycle: RevisionCycle,
        categorie: String = "",
        libelle: String = "",
        mois: Int = 0,
        annee: Int = 0,
        etablissement: String = "",
        note: String = "",
        ordre: Int = 0
    ) {
        self.id = id
        self.exerciceID = exerciceID
        self.cycleRaw = cycle.rawValue
        self.categorie = categorie
        self.libelle = libelle
        self.mois = mois
        self.annee = annee
        self.etablissement = etablissement
        self.note = note
        self.ordre = ordre
        self.ajouteLe = Date()
    }

    var cycle: RevisionCycle {
        get { RevisionCycle(rawValue: cycleRaw) ?? .nonClasse }
        set { cycleRaw = newValue.rawValue }
    }

    var hasDocument: Bool { !docPath.isEmpty || docBookmark != nil }

    /// Identifiant derive de la cle logique, pour qu'une piece rattachee sur un
    /// Mac ne soit pas dupliquee par la synchronisation sur l'autre.
    @MainActor
    static func stableID(exerciceID: UUID, cycle: RevisionCycle, categorie: String,
                         annee: Int, mois: Int, etablissement: String) -> UUID {
        SupabaseSync.stableID(exerciceID.uuidString, cycle.rawValue, categorie,
                              "\(annee)", "\(mois)", etablissement)
    }
}

// MARK: - Social Anomaly

@Model
final class SocialAnomaly {
    @Attribute(.unique) var id: UUID
    var exerciceID: UUID
    var mois: Int
    var annee: Int
    var etablissement: String
    var siret: String

    var type: SocialAnomalyType
    var montant: Double
    var titre: String
    var lignesAffectees: String
    var actionProposee: String

    var impactResultat: Bool

    var dateDetection: Date

    init(
        exerciceID: UUID,
        mois: Int,
        annee: Int,
        etablissement: String,
        siret: String,
        type: SocialAnomalyType,
        montant: Double,
        titre: String,
        lignesAffectees: String = "",
        actionProposee: String = "",
        impactResultat: Bool = true,
        dateDetection: Date = Date()
    ) {
        self.id = UUID()
        self.exerciceID = exerciceID
        self.mois = mois
        self.annee = annee
        self.etablissement = etablissement
        self.siret = siret
        self.type = type
        self.montant = montant
        self.titre = titre
        self.lignesAffectees = lignesAffectees
        self.actionProposee = actionProposee
        self.impactResultat = impactResultat
        self.dateDetection = dateDetection
    }
}
