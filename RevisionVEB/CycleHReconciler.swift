//
//  CycleHReconciler.swift
//  RevisionVEB
//
//  Moteur de rapprochement Cycle H : 641 ↔ DSN
//

import Foundation
import SwiftData

@MainActor
class CycleHReconciler {
    // Constantes
    private static let COMPTES_641 = [
        "64111000", "64111100",  // Salaires
        "64120000", "64120001",  // Congés payés
        "64130000", "64130001",  // Primes
        "64140000", "64140001",  // Indemnités
        "64170000", "64170001"   // Avantages en nature
        // EXCLURE : 64115000-64116510 (non-salariés)
    ]

    private static let SIRETS: [String: String] = [
        "805318466": "LIESEL",
        "805318466000028": "FREDDY"
    ]

    // Seuils de tollérance (en €)
    private static let SEUIL_OK: Double = 1.0
    private static let SEUIL_CHECK: Double = 100.0

    // MARK: - Calcul assiette GL

    /// Calcule l'assiette GL pour un mois/établissement
    /// Neutralise les lignes "AN repas à déduire"
    static func calculateGlAssiette(
        entries: [SocialPayrollEntry],
        mois: Int,
        etablissement: String
    ) -> (montant: Double, details: [String]) {
        let filtered = entries.filter {
            $0.mois == mois && $0.etablissement == etablissement &&
            COMPTES_641.contains($0.compte) &&
            !$0.compte.hasPrefix("64115")  // Exclure non-salariés
        }

        var montant: Double = 0.0
        var details: [String] = []

        for entry in filtered {
            // Vérifier si c'est une AN repas à déduire
            let isAnRepas = entry.libelle.lowercased().contains("an repas") &&
                            entry.libelle.lowercased().contains("déduire")

            if isAnRepas {
                entry.retenuDansAssiette = false
                entry.motifExclusion = "AN repas à déduire"
                details.append("[\(entry.dateEcriture.formatted())] \(entry.compte) - \(entry.libelle): \(entry.montant) € (EXCLUE)")
            } else {
                entry.retenuDansAssiette = true
                montant += entry.montant
                details.append("[\(entry.dateEcriture.formatted())] \(entry.compte) - \(entry.libelle): \(entry.montant) € (retenue)")
            }
        }

        return (montant, details)
    }

    // MARK: - Cascade assiette DSN

    /// Choisit l'assiette DSN selon la cascade :
    /// 1. AGIRC T1+T2 (si disponible)
    /// 2. CTP 027D
    /// Garde CTP 100D en contrôle
    static func selectDsnAssiette(from assiettes: [String: Double]) -> (montant: Double, poste: String, ctp100d: Double?) {
        // Priorité 1 : AGIRC T1+T2
        if let combined = assiettes["AGIRC T1+T2"] {
            return (combined, "AGIRC T1+T2", assiettes["CTP 100D"])
        }
        if let t1 = assiettes["AGIRC T1"] {
            return (t1, "AGIRC T1", assiettes["CTP 100D"])
        }

        // Priorité 2 : CTP 027D
        if let ctp027 = assiettes["CTP 027D"] {
            return (ctp027, "CTP 027D", assiettes["CTP 100D"])
        }

        // Fallback : le premier montant dispo
        if let first = assiettes.first {
            return (first.value, first.key, assiettes["CTP 100D"])
        }

        return (0.0, "UNKNOWN", nil)
    }

    // MARK: - Détection retraitement

    /// Extrait les régularisations du mois depuis les entrées GL
    /// (lignes dont le libellé contient "régularisation")
    static func detectRetratement(
        entries: [SocialPayrollEntry],
        mois: Int,
        etablissement: String
    ) -> Double {
        let reguls = entries.filter {
            $0.mois == mois && $0.etablissement == etablissement &&
            $0.libelle.lowercased().contains("régularisation")
        }

        return reguls.reduce(0.0) { $0 + $1.montant }
    }

    // MARK: - Détecteurs d'anomalies

    static func detectAnomalies(
        glEntries: [SocialPayrollEntry],
        dsnEntries: [DsnAssiette],
        reconciliations: [SocialReconciliation],
        exerciceID: UUID,
        etablissements: [String]
    ) -> [SocialAnomaly] {
        var anomalies: [SocialAnomaly] = []

        for entries in [glEntries] {  // On travaille sur GL uniquement
            for mois in 1...12 {
                for etab in etablissements {
                    let siret = SIRETS[etab] ?? "UNKNOWN"

                    // RÈGLE 1 : DOUBLE_ECRITURE_PAIE
                    // Deux jeux d'écritures sans lot (Complément vide)
                    let noLotEntries = entries.filter {
                        $0.mois == mois && $0.etablissement == etab && $0.complement.isEmpty
                    }
                    if noLotEntries.count > 1 {
                        let montant = noLotEntries.map { abs($0.montant) }.reduce(0, +)
                        anomalies.append(SocialAnomaly(
                            exerciceID: exerciceID,
                            mois: mois,
                            annee: 2025,
                            etablissement: etab,
                            siret: siret,
                            type: .doubleEcriture,
                            montant: montant,
                            titre: "Deux jeux d'écritures sans référence de lot",
                            actionProposee: "Identifier le jeu à conserver et fusionner",
                            impactResultat: true
                        ))
                    }

                    // RÈGLE 2 : OD_NON_VENTILEE
                    // Une nature 641 mouvementée qu'en un seul établissement quand les deux ont de la paie
                    let naturesByEtab = Dictionary(grouping: entries.filter { $0.mois == mois }, by: { $0.compte })
                    for (compte, groupe) in naturesByEtab {
                        let etabs = Set(groupe.map { $0.etablissement })
                        if etabs.count < etablissements.count && etabs.contains(etab) {
                            let montant = groupe.filter { $0.etablissement == etab }.map { abs($0.montant) }.reduce(0, +)
                            anomalies.append(SocialAnomaly(
                                exerciceID: exerciceID,
                                mois: mois,
                                annee: 2025,
                                etablissement: etab,
                                siret: siret,
                                type: .odNonVentilee,
                                montant: montant,
                                titre: "Compte \(compte) imputé sur un seul établissement",
                                actionProposee: "Vérifier la ventilation entre établissements",
                                impactResultat: false
                            ))
                        }
                    }
                }
            }
        }

        return anomalies
    }

    // MARK: - Statut de réconciliation

    static func calculateStatus(ecartResiduel: Double) -> ReconciliationStatus {
        let absEcart = abs(ecartResiduel)
        if absEcart < SEUIL_OK {
            return .ok
        } else if absEcart < SEUIL_CHECK {
            return .toCheck
        } else {
            return .toJustify
        }
    }
}
