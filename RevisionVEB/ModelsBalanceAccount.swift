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
    var balanceNMinus2: Double
    var restaurant: Restaurant
    var exerciceID: UUID
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
        balanceNMinus2: Double = 0,
        restaurant: Restaurant = .freddy,
        exerciceID: UUID,
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
        self.balanceNMinus2 = balanceNMinus2
        self.restaurant = restaurant
        self.exerciceID = exerciceID
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
    var dossierID: UUID
    var accountNumber: String
    var cycleRaw: String

    init(dossierID: UUID, accountNumber: String, cycle: RevisionCycle) {
        self.dossierID = dossierID
        self.accountNumber = accountNumber
        self.cycleRaw = cycle.rawValue
    }

    var cycle: RevisionCycle {
        get { RevisionCycle(rawValue: cycleRaw) ?? .nonClasse }
        set { cycleRaw = newValue.rawValue }
    }
}

// MARK: - Dossier (Societe) et Exercice

/// Une societe / dossier de revision (ex: PLANB SARL, Moulin Neuf SARL).
@Model
final class Dossier {
    @Attribute(.unique) var id: UUID
    var nom: String
    var ordre: Int

    init(id: UUID = UUID(), nom: String, ordre: Int = 0) {
        self.id = id
        self.nom = nom
        self.ordre = ordre
    }
}

/// Un exercice comptable rattache a un dossier (ex: 2025, cloture au 31/12/2025).
@Model
final class Exercice {
    @Attribute(.unique) var id: UUID
    var dossierID: UUID
    var libelle: String
    var dateCloture: Date
    var creeLe: Date

    init(id: UUID = UUID(), dossierID: UUID, libelle: String, dateCloture: Date, creeLe: Date = Date()) {
        self.id = id
        self.dossierID = dossierID
        self.libelle = libelle
        self.dateCloture = dateCloture
        self.creeLe = creeLe
    }
}

// MARK: - Cycles de revision

/// Les cycles de revision comptable. Chaque compte est range dans un cycle
/// selon sa classe (prefixe du numero de compte), selon le Plan Comptable General.
enum RevisionCycle: String, Codable, CaseIterable, Identifiable {
    case soldesIntermedialres = "A - Soldes Intermédiaires de Gestion"
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
        case .soldesIntermedialres: return "chart.bar"
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

// MARK: - Controles de revision (feuille de travail par cycle)

import SwiftUI

enum ControlStatus: String, Codable, CaseIterable {
    case aFaire    = "À faire"
    case ok        = "OK"
    case aVerifier = "À vérifier"
    case anomalie  = "Anomalie"

    var icon: String {
        switch self {
        case .aFaire:    return "circle"
        case .ok:        return "checkmark.circle.fill"
        case .aVerifier: return "exclamationmark.circle.fill"
        case .anomalie:  return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .aFaire:    return .secondary
        case .ok:        return .green
        case .aVerifier: return .orange
        case .anomalie:  return .red
        }
    }
}

/// Justification (cross-ref) d'un compte : solde justifie + piece liee.
/// Cle logique = (exerciceID, accountNumber).
@Model
final class AccountJustification {
    var exerciceID: UUID
    var accountNumber: String
    var soldeJustifie: Double?
    var docName: String
    var docPath: String
    var docBookmark: Data?
    var note: String
    var updatedAt: Date

    init(exerciceID: UUID, accountNumber: String,
         soldeJustifie: Double? = nil, docName: String = "", docPath: String = "",
         docBookmark: Data? = nil, note: String = "", updatedAt: Date = Date()) {
        self.exerciceID = exerciceID
        self.accountNumber = accountNumber
        self.soldeJustifie = soldeJustifie
        self.docName = docName
        self.docPath = docPath
        self.docBookmark = docBookmark
        self.note = note
        self.updatedAt = updatedAt
    }

    var hasDocument: Bool { !docPath.isEmpty || docBookmark != nil }
}

/// Mapping compte de vente (classe 70) -> taux de TVA, par exercice.
@Model
final class TvaCompteTaux {
    var exerciceID: UUID = UUID()
    var compte: String = ""
    var taux: String = ""   // "20", "10", "5.5", "2.1", "Exo"

    init(exerciceID: UUID, compte: String, taux: String = "") {
        self.exerciceID = exerciceID
        self.compte = compte
        self.taux = taux
    }
}

/// Une ligne de declaration CA3 : periode + taux + base + TVA collectee.
@Model
final class Ca3Entry {
    var id: UUID = UUID()
    var exerciceID: UUID = UUID()
    var periode: String = ""   // ex: "2025-01"
    var taux: String = ""
    var base: Double = 0
    var tva: Double = 0
    var ordre: Int = 0

    init(id: UUID = UUID(), exerciceID: UUID, periode: String = "", taux: String = "",
         base: Double = 0, tva: Double = 0, ordre: Int = 0) {
        self.id = id
        self.exerciceID = exerciceID
        self.periode = periode
        self.taux = taux
        self.base = base
        self.tva = tva
        self.ordre = ordre
    }
}

/// Totaux d'une declaration CA3 par periode (TVA deductible ; collectee et net se deduisent).
@Model
final class Ca3Period {
    var exerciceID: UUID = UUID()
    var periode: String = ""
    var tvaDeductible: Double = 0   // déductible sur achats (hors report) = ligne 19 + ligne 20
    var creditM1: Double = 0        // report du crédit de la déclaration précédente (ligne 22)
    var caHT: Double = 0            // CA HT total déclaré (ligne A1)
    var ligne16: Double = 0         // Total de la TVA brute due (ligne 16)
    var ligne19: Double = 0         // TVA déductible sur immobilisations (ligne 19)
    var ligne20: Double = 0         // TVA déductible sur autres biens et services (ligne 20)

    init(exerciceID: UUID, periode: String, tvaDeductible: Double = 0, creditM1: Double = 0,
         caHT: Double = 0, ligne16: Double = 0, ligne19: Double = 0, ligne20: Double = 0) {
        self.exerciceID = exerciceID
        self.periode = periode
        self.tvaDeductible = tvaDeductible
        self.creditM1 = creditM1
        self.caHT = caHT
        self.ligne16 = ligne16
        self.ligne19 = ligne19
        self.ligne20 = ligne20
    }

    var ligne23: Double { ligne19 + ligne20 + creditM1 }   // total TVA déductible
}

/// Aides TVA : taux predefinis + detection du taux depuis un libelle de compte.
enum TvaHelper {
    static let presets = ["20", "10", "5.5", "2.1", "Exo", "—"]

    /// Detecte le taux depuis un libelle ("...10%", "...VAE 5,5%", "EXO...").
    static func detectTaux(from label: String) -> String {
        let l = label.lowercased()
        if l.contains("exo") { return "Exo" }
        // cherche un nombre suivi de %
        let pattern = "([0-9]+(?:[.,][0-9]+)?)\\s*%"
        if let re = try? NSRegularExpression(pattern: pattern),
           let m = re.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
           let r = Range(m.range(at: 1), in: label) {
            return String(label[r]).replacingOccurrences(of: ",", with: ".")
        }
        return ""
    }

    /// Valeur numerique du taux (nil si exo / non defini).
    static func rate(_ taux: String) -> Double? {
        Double(taux.replacingOccurrences(of: ",", with: "."))
    }
}

/// Rapprochement bancaire d'un compte (par exercice) : solde extrait + note.
@Model
final class BankReconciliation {
    var exerciceID: UUID
    var accountNumber: String
    var soldeExtrait: Double?
    var note: String
    var updatedAt: Date

    init(exerciceID: UUID, accountNumber: String, soldeExtrait: Double? = nil, note: String = "", updatedAt: Date = Date()) {
        self.exerciceID = exerciceID
        self.accountNumber = accountNumber
        self.soldeExtrait = soldeExtrait
        self.note = note
        self.updatedAt = updatedAt
    }
}

/// Element (ecriture) de rapprochement : libelle + montant signe.
@Model
final class ReconItem {
    var id: UUID
    var exerciceID: UUID
    var accountNumber: String
    var libelle: String = ""
    var montant: Double = 0
    var ordre: Int = 0
    var docName: String = ""
    var docPath: String = ""
    var docBookmark: Data? = nil

    init(id: UUID = UUID(), exerciceID: UUID, accountNumber: String,
         libelle: String = "", montant: Double = 0, ordre: Int = 0,
         docName: String = "", docPath: String = "", docBookmark: Data? = nil) {
        self.id = id
        self.exerciceID = exerciceID
        self.accountNumber = accountNumber
        self.libelle = libelle
        self.montant = montant
        self.ordre = ordre
        self.docName = docName
        self.docPath = docPath
        self.docBookmark = docBookmark
    }

    var hasDocument: Bool { !docPath.isEmpty || docBookmark != nil }
}

/// Mouvement du grand livre classe 2 (immobilisations) importe de Cegid.
@Model
final class Class2Movement {
    var id: UUID = UUID()
    var exerciceID: UUID = UUID()
    var date: Date = Date()
    var compte: String = ""
    var libelle: String = ""
    var complement: String = ""
    var debit: Double = 0
    var credit: Double = 0
    var ordre: Int = 0

    init(id: UUID = UUID(), exerciceID: UUID, date: Date = Date(), compte: String = "",
         libelle: String = "", complement: String = "", debit: Double = 0, credit: Double = 0, ordre: Int = 0) {
        self.id = id
        self.exerciceID = exerciceID
        self.date = date
        self.compte = compte
        self.libelle = libelle
        self.complement = complement
        self.debit = debit
        self.credit = credit
        self.ordre = ordre
    }

    /// Report à nouveau (valeur d'ouverture), à distinguer des mouvements de l'exercice.
    var isOuverture: Bool { libelle.contains("S.A.N.") }
}

/// Facture d'investissement (immobilisation) avec piece liee, par exercice.
@Model
final class ImmoInvoice {
    var id: UUID = UUID()
    var exerciceID: UUID = UUID()
    var date: Date = Date()
    var compte: String = ""        // compte immo concerne (20/21/23/26/27)
    var designation: String = ""   // fournisseur / objet
    var montant: Double = 0        // montant HT immobilise
    var docName: String = ""
    var docPath: String = ""
    var docBookmark: Data? = nil
    var ordre: Int = 0

    init(id: UUID = UUID(), exerciceID: UUID, date: Date = Date(), compte: String = "",
         designation: String = "", montant: Double = 0, ordre: Int = 0) {
        self.id = id
        self.exerciceID = exerciceID
        self.date = date
        self.compte = compte
        self.designation = designation
        self.montant = montant
        self.ordre = ordre
    }

    var hasDocument: Bool { !docPath.isEmpty || docBookmark != nil }
}

/// Soldes Intermédiaires de Gestion (SIG) - 8 étapes du compte de résultat.
@Model
final class SoldesIntermedialres {
    var id: UUID = UUID()
    var exerciceID: UUID = UUID()

    // Niveau 1 : Marge brute = CA HT - Coûts directs
    var margeBrute: Double = 0

    // Niveau 2 : Production de l'exercice = Production vendue + stockée + immobilisée
    var productionExercice: Double = 0

    // Niveau 3 : Valeur ajoutée = Marge brute + Production - Consommations externes
    var valeurAjoutee: Double = 0

    // Niveau 4 : EBE = VA - Frais perso - Impôts taxes
    var ebeSig: Double = 0

    // Niveau 5 : Résultat d'exploitation = EBE + Autres produits/charges d'exploitation
    var resultatExploitation: Double = 0

    // Niveau 6 : Résultat financier = Produits financiers - Charges financières
    var resultatFinancier: Double = 0

    // Niveau 7 : Résultat exceptionnel = Produits exceptionnels - Charges
    var resultatExceptionnel: Double = 0

    // Niveau 8 : Résultat net = Résultat exploitation + financier + exceptionnel - IS
    var resultatNet: Double = 0

    // Valeurs N-1 pour comparaison
    var margeBruteN1: Double = 0
    var productionExerciceN1: Double = 0
    var valeurAjouteeN1: Double = 0
    var ebeSigN1: Double = 0
    var resultatExploitationN1: Double = 0
    var resultatFinancierN1: Double = 0
    var resultatExceptionnelN1: Double = 0
    var resultatNetN1: Double = 0

    // Valeurs N-2 pour comparaison
    var margeBruteN2: Double = 0
    var productionExerciceN2: Double = 0
    var valeurAjouteeN2: Double = 0
    var ebeSigN2: Double = 0
    var resultatExploitationN2: Double = 0
    var resultatFinancierN2: Double = 0
    var resultatExceptionnelN2: Double = 0
    var resultatNetN2: Double = 0

    // Détails pour chaque niveau (pour affichage déroulable)
    var caHT: Double = 0
    var coutsDirects: Double = 0
    var productionVendue: Double = 0
    var productionStockee: Double = 0
    var productionImmobilisee: Double = 0
    var consommationsExternes: Double = 0
    var fraisPersonnel: Double = 0
    var impotsEtTaxes: Double = 0
    var autresProduitExploitation: Double = 0
    var autresChargesExploitation: Double = 0
    var produitsFinanciers: Double = 0
    var chargesFinancieres: Double = 0
    var produitsExceptionnels: Double = 0
    var chargesExceptionnels: Double = 0
    var impotSurBenefices: Double = 0

    var updatedAt: Date = Date()

    init(exerciceID: UUID) {
        self.exerciceID = exerciceID
    }
}

/// Bien immobilisé (état d'amortissement depuis le fichier Excel), par exercice et compte.
@Model
final class ImmoAsset {
    var id: UUID = UUID()
    var exerciceID: UUID = UUID()
    var compte: String = ""            // classe 2 (20xxx, 21xxx, 26xxx, 27xxx)
    var numeroImmo: String = ""        // numéro identifiant du bien (ex: "00026")
    var libelle: String = ""           // description du bien
    var montantHT: Double = 0          // valeur d'acquisition brute
    var dateAcquisition: Date = Date() // date d'acquisition
    var tauxAmort: Double = 0          // taux d'amortissement en % (ex: 20)
    var amortAnterieur: Double = 0     // amortissements avant l'exercice
    var amortExercice: Double = 0      // amortissement de l'exercice actuel
    var ordre: Int = 0

    init(id: UUID = UUID(), exerciceID: UUID, compte: String = "", numeroImmo: String = "",
         libelle: String = "", montantHT: Double = 0, dateAcquisition: Date = Date(),
         tauxAmort: Double = 0, amortAnterieur: Double = 0, amortExercice: Double = 0, ordre: Int = 0) {
        self.id = id
        self.exerciceID = exerciceID
        self.compte = compte
        self.numeroImmo = numeroImmo
        self.libelle = libelle
        self.montantHT = montantHT
        self.dateAcquisition = dateAcquisition
        self.tauxAmort = tauxAmort
        self.amortAnterieur = amortAnterieur
        self.amortExercice = amortExercice
        self.ordre = ordre
    }

    var amortTotal: Double { amortAnterieur + amortExercice }
    var valeurResiduelle: Double { montantHT - amortTotal }
    var estCompletementAmortie: Bool { valeurResiduelle <= 0.01 }

    func valider() -> (statut: ControlStatus, messages: [String]) {
        var messages: [String] = []

        // Contrôle 1 : Taux d'amortissement (15-40% courant)
        if tauxAmort < 0.5 || tauxAmort > 50 {
            messages.append("Taux \(String(format: "%.0f%%", tauxAmort)) insolite")
        }

        // Contrôle 2 : Montant négatif ou nul
        if montantHT <= 0 {
            messages.append("Montant HT non positif")
        }

        // Contrôle 3 : Amortissement total > montant HT
        if amortTotal > montantHT + 0.01 {
            messages.append("Amort. (\(String(format: "%.0f", amortTotal))) > Montant HT (\(String(format: "%.0f", montantHT)))")
        }

        // Contrôle 4 : Si complètement amorti, amortissement exercice doit être 0
        if estCompletementAmortie && amortExercice > 0.01 {
            messages.append("Bien complètement amorti mais amort. exercice > 0")
        }

        // Contrôle 5 : Amortissement exercice cohérent avec taux (si non complètement amorti avant)
        if montantHT > 0 && !estCompletementAmortie && amortExercice > 0 {
            let tauxAttendu = (montantHT - amortAnterieur) * tauxAmort / 100
            let ecart = abs(amortExercice - tauxAttendu)
            if ecart > tauxAttendu * 0.2 {
                messages.append("Amort. exercice (\(String(format: "%.0f", amortExercice))) vs taux attendu (\(String(format: "%.0f", tauxAttendu)))")
            }
        }

        let statut: ControlStatus = messages.isEmpty ? .ok : (messages.count <= 1 ? .aVerifier : .anomalie)
        return (statut, messages)
    }
}


/// Etat d'un point de controle (statut + observation), par exercice et par cycle.
@Model
final class ControlState {
    var exerciceID: UUID
    var cycleRaw: String
    var itemID: String
    var statutRaw: String
    var note: String
    var updatedAt: Date

    init(exerciceID: UUID, cycleRaw: String, itemID: String,
         statut: ControlStatus = .aFaire, note: String = "", updatedAt: Date = Date()) {
        self.exerciceID = exerciceID
        self.cycleRaw = cycleRaw
        self.itemID = itemID
        self.statutRaw = statut.rawValue
        self.note = note
        self.updatedAt = updatedAt
    }

    var statut: ControlStatus {
        get { ControlStatus(rawValue: statutRaw) ?? .aFaire }
        set { statutRaw = newValue.rawValue }
    }
}

// MARK: - Catalogue des controles (la liste type cabinet, par cycle)

struct ControlItem: Identifiable { let id: String; let libelle: String }
struct ControlGroup: Identifiable { let id: String; let titre: String; let items: [ControlItem] }

enum RevisionControls {
    /// Construit un groupe avec des itemID stables (lettre du cycle + index).
    private static func grp(_ letter: String, _ gi: Int, _ titre: String, _ libelles: [String]) -> ControlGroup {
        ControlGroup(
            id: "\(letter)\(gi)",
            titre: titre,
            items: libelles.enumerated().map { ControlItem(id: "\(letter)\(gi)-\($0.offset)", libelle: $0.element) }
        )
    }

    static func groups(for cycle: RevisionCycle) -> [ControlGroup] {
        let L = cycle.letter
        switch cycle {
        case .soldesIntermedialres:
            return [
                grp(L, 0, "Synthèse", ["Marge brute", "Valeur ajoutée", "EBE", "Résultat d'exploitation", "Résultat net"]),
                grp(L, 1, "Validations", ["Cohérence marge brute vs CA", "Cohérence EBE vs VA et frais", "Résultat net vs IS", "Rapprochement avec le compte de résultat"]),
            ]
        case .tresorerie:
            return [
                grp(L, 0, "Trésorerie", ["Rapprochements bancaires", "Contrôle des chèques en circulation",
                    "Vérification des virements de fin d'exercice", "Contrôle des soldes bancaires", "Justification des caisses"]),
                grp(L, 1, "Emprunts", ["Vérification des tableaux d'amortissement", "Contrôle du capital restant dû",
                    "Contrôle des intérêts courus", "Contrôle des échéances à moins d'un an"]),
            ]
        case .clients:
            return [
                grp(L, 0, "Ventes", ["Cohérence CA N/N-1", "Contrôle des marges", "Contrôle des avoirs"]),
                grp(L, 1, "Clients", ["Balance âgée", "Analyse des retards de paiement", "Contrôle des créances douteuses",
                    "Vérification des provisions", "Contrôle des comptes créditeurs clients"]),
            ]
        case .regularisation:
            return [
                grp(L, 0, "Charges constatées d'avance", ["Contrats couvrant plusieurs exercices", "Assurances", "Abonnements", "Loyers"]),
                grp(L, 1, "Produits constatés d'avance", ["Prestations non réalisées", "Abonnements facturés d'avance"]),
                grp(L, 2, "FNP / PAR", ["Vérification de l'exhaustivité", "Rattachement à l'exercice"]),
            ]
        case .fournisseurs:
            return [
                grp(L, 0, "Achats", ["Cohérence avec l'activité", "Contrôle des variations de charges"]),
                grp(L, 1, "Fournisseurs", ["Justification des soldes", "Recherche des FNP", "Contrôle des soldes débiteurs",
                    "Vérification des factures post-clôture"]),
            ]
        case .stocks:
            return [
                grp(L, 0, "Existence", ["Inventaire physique", "Contrôle des écarts"]),
                grp(L, 1, "Valorisation", ["CMP ou FIFO", "Contrôle des coûts unitaires", "Stocks obsolètes", "Dépréciations"]),
                grp(L, 2, "Restaurant", ["Inventaire boissons", "Inventaire matières premières", "Contrôle du taux de marge", "Contrôle du ratio matières"]),
            ]
        case .immobilisations:
            return [
                grp(L, 0, "Acquisitions", ["Factures d'investissement", "Distinction charge / immo"]),
                grp(L, 1, "Amortissements", ["Recalcul", "Durées d'amortissement", "Contrôle des sorties"]),
                grp(L, 2, "Existence", ["Contrôle physique des biens significatifs"]),
            ]
        case .personnel:
            return [
                grp(L, 0, "Paie", ["Réconciliation paie / comptabilité", "Contrôle des OD de paie"]),
                grp(L, 1, "Social", ["Contrôle URSSAF", "Congés payés", "Primes à payer", "Charges sociales à payer"]),
            ]
        case .fiscal:
            return [
                grp(L, 0, "TVA", ["Concordance CA / TVA collectée", "Contrôle TVA déductible", "Vérification des CA3"]),
                grp(L, 1, "IS", ["Recalcul du résultat fiscal", "Contrôle des réintégrations et déductions"]),
                grp(L, 2, "Autres impôts", ["CFE", "Taxe d'apprentissage", "Formation professionnelle", "Participation construction"]),
            ]
        case .provisions:
            return [
                grp(L, 0, "Risques", ["Litiges", "Prud'hommes", "Contentieux fournisseurs"]),
                grp(L, 1, "Charges", ["Prime exceptionnelle", "Gros entretien"]),
                grp(L, 2, "Contrôles", ["Justification documentaire", "Recalcul", "Vérification de la probabilité du risque"]),
            ]
        case .capitaux:
            return [
                grp(L, 0, "Contrôles", ["Affectation du résultat", "PV d'assemblée", "Concordance avec les statuts",
                    "Contrôle du report à nouveau", "Vérification des dividendes distribués"]),
            ]
        case .autresBilan:
            return [
                grp(L, 0, "Comptes courants", ["455 Associés", "457 Dividendes"]),
                grp(L, 1, "Comptes d'attente", ["471", "472"]),
                grp(L, 2, "Divers", ["467", "Débiteurs et créditeurs divers"]),
                grp(L, 3, "Contrôles", ["Justification ligne à ligne", "Analyse de l'ancienneté", "Vérification des soldes anormaux"]),
            ]
        case .groupe:
            return [
                grp(L, 0, "Contrôles", ["Comptes courants d'associés", "Opérations intra-groupe", "Conventions réglementées",
                    "Prêts entre sociétés", "Refacturations"]),
            ]
        case .nonClasse:
            return []
        }
    }
}
