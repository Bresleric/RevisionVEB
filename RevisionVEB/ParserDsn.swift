//
//  ParserDsn.swift
//  RevisionVEB
//
//  Extraction DSN : Payfit (jan-juil 2025) + Arhia (août-déc 2025)
//

import Foundation
import PDFKit

struct DsnExtraction {
    var mois: Int
    var annee: Int
    var etablissement: String  // "LIESEL" ou "FREDDY"
    var siret: String
    var assiettesParPoste: [String: Double]  // "AGIRC T1" -> 9795.37, "CTP 027D" -> 12867.00, etc.
    var ctp100d: Double?  // colonne de contrôle
    var fichierSource: String
}

@MainActor
class DsnParser {
    // Constantes : établissements mappés par SIRET
    // Support des deux formats : 9 chiffres (SIREN) et 14 chiffres (SIRET complet)
    private static let ETABLISSEMENTS: [String: String] = [
        // LIESEL
        "805318466": "LIESEL",        // SIREN (9 chiffres)
        "80531846600010": "LIESEL",   // SIRET complet (14 chiffres)
        // FREDDY
        "80531846600028": "FREDDY"    // SIRET complet (14 chiffres)
    ]

    /// Parse un PDF DSN Payfit (janvier-juillet 2025)
    /// Formats attendus : "chez-tante-liesel-recapitulatif-dsn-01-2025.pdf"
    static func parsePayfitPdf(url: URL) async -> DsnExtraction? {
        guard let pdfDocument = PDFDocument(url: url) else {
            print("❌ Impossible d'ouvrir \(url.lastPathComponent)")
            return nil
        }

        // Extraire le texte complet
        var fullText = ""
        for i in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: i) {
                fullText += page.string ?? ""
            }
        }

        // 1. Identifier SIRET et établissement
        let siretPattern = #"(\d{3}\s?\d{3}\s?\d{3}\s?\d{5})"#
        guard let siretRegex = try? NSRegularExpression(pattern: siretPattern),
              let siretMatch = siretRegex.firstMatch(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)),
              let siretRange = Range(siretMatch.range(at: 1), in: fullText) else {
            print("❌ SIRET non trouvé dans \(url.lastPathComponent)")
            return nil
        }
        let siretRaw = String(fullText[siretRange]).replacingOccurrences(of: " ", with: "")

        // Chercher l'établissement par SIRET
        // D'ABORD : essayer le SIRET complet (14 chiffres)
        // ENSUITE : essayer le SIREN (9 premiers chiffres)
        let siretPrefix = String(siretRaw.prefix(9))
        let etablissement = ETABLISSEMENTS[siretRaw] ?? ETABLISSEMENTS[siretPrefix] ?? "UNKNOWN"

        // 2. Extraire mois/année du nom du fichier
        let filename = url.lastPathComponent.lowercased()
        let moisFrancais = ["janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4,
                            "mai": 5, "juin": 6, "juillet": 7, "août": 8, "aout": 8,
                            "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12, "decembre": 12]

        var mois = 1
        var annee = 2025

        // Chercher le mois en français
        for (nom, num) in moisFrancais {
            if filename.contains(nom) {
                mois = num
                break
            }
        }

        // Chercher l'année
        if let yearMatch = filename.range(of: "202\\d", options: .regularExpression) {
            if let anneeInt = Int(String(filename[yearMatch])) {
                annee = anneeInt
            }
        }

        print("📅 Parsé : \(mois)/\(annee)")

        // 3. Extraire tableaux (AGIRC-ARRCO + Urssaf)
        var assiettes: [String: Double] = [:]

        // DEBUG : afficher un échantillon du texte
        let textSample = String(fullText.prefix(2000))
        print("📄 Échantillon du texte (premiers 2000 chars):")
        print(textSample)
        print("---")

        // Bordereau AGIRC-ARRCO : chercher "Complémentaire - Tranche 1" et "Tranche 2"
        extractAgirc(from: fullText, into: &assiettes)

        // Bordereau Urssaf : chercher CTP 027D (et 100D pour contrôle)
        extractUrssaf(from: fullText, into: &assiettes)

        guard !assiettes.isEmpty else {
            print("⚠️ Aucune assiette trouvée dans \(filename)")
            print("   → Texte trouvé : \(fullText.count) caractères")
            return nil
        }

        return DsnExtraction(
            mois: mois,
            annee: annee,
            etablissement: etablissement,
            siret: siretRaw,
            assiettesParPoste: assiettes,
            ctp100d: nil,
            fichierSource: url.lastPathComponent
        )
    }

    /// Parse un PDF DSN Arhia (août-décembre 2025)
    /// L'établissement s'identifie par le SIRET dans le corps, pas par le nom du fichier.
    static func parseArhiaPdf(url: URL) async -> DsnExtraction? {
        guard let pdfDocument = PDFDocument(url: url) else {
            print("❌ Impossible d'ouvrir \(url.lastPathComponent)")
            return nil
        }

        var fullText = ""
        for i in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: i) {
                fullText += page.string ?? ""
            }
        }

        // 1. SIRET
        let siretPattern = #"(\d{3}\s?\d{3}\s?\d{3}\s?\d{5})"#
        guard let siretRegex = try? NSRegularExpression(pattern: siretPattern),
              let siretMatch = siretRegex.firstMatch(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)),
              let siretRange = Range(siretMatch.range(at: 1), in: fullText) else {
            print("❌ SIRET non trouvé dans \(url.lastPathComponent)")
            return nil
        }
        let siretRaw = String(fullText[siretRange]).replacingOccurrences(of: " ", with: "")
        let siretPrefix = String(siretRaw.prefix(9))
        let etablissement = ETABLISSEMENTS[siretPrefix] ?? ETABLISSEMENTS[siretRaw] ?? "UNKNOWN"

        // 2. Mois/année du nom du fichier (format AAAAMM)
        let filename = url.lastPathComponent
        guard filename.count >= 6 else {
            print("❌ Format nom fichier invalide : \(filename)")
            return nil
        }
        let aaaamm = String(filename.prefix(6))
        guard let annee = Int(aaaamm.prefix(4)), let mois = Int(aaaamm.suffix(2)) else {
            print("❌ Impossible de parser mois/année de \(filename)")
            return nil
        }

        // 3. Extraire assiettes CTP (format Arhia : "100D SS TOTALITE R.G. Déplaf. 37227.00")
        var assiettes: [String: Double] = [:]
        extractArhiaCtp(from: fullText, into: &assiettes)

        guard !assiettes.isEmpty else {
            print("⚠️ Aucune assiette trouvée dans \(filename)")
            return nil
        }

        return DsnExtraction(
            mois: mois,
            annee: annee,
            etablissement: etablissement,
            siret: siretRaw,
            assiettesParPoste: assiettes,
            ctp100d: nil,
            fichierSource: url.lastPathComponent
        )
    }

    // MARK: - Extraction tableaux

    private static func extractAgirc(from text: String, into assiettes: inout [String: Double]) {
        // Chercher "Complémentaire - Tranche 1" et "Tranche 2"
        let tranche1Pattern = #"Complémentaire\s*-\s*Tranche\s+1[^\d]*(\d+[.,]\d{2})"#
        let tranche2Pattern = #"Complémentaire\s*-\s*Tranche\s+2[^\d]*(\d+[.,]\d{2})"#

        if let regex1 = try? NSRegularExpression(pattern: tranche1Pattern),
           let match1 = regex1.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range1 = Range(match1.range(at: 1), in: text) {
            let montantStr = String(text[range1]).replacingOccurrences(of: ",", with: ".")
            if let montant = Double(montantStr) {
                assiettes["AGIRC T1"] = montant
            }
        }

        if let regex2 = try? NSRegularExpression(pattern: tranche2Pattern),
           let match2 = regex2.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range2 = Range(match2.range(at: 1), in: text) {
            let montantStr = String(text[range2]).replacingOccurrences(of: ",", with: ".")
            if let montant = Double(montantStr) {
                assiettes["AGIRC T2"] = montant
            }
        }

        // Si T1 et T2 existent, créer une clé combinée
        if let t1 = assiettes["AGIRC T1"], let t2 = assiettes["AGIRC T2"] {
            assiettes["AGIRC T1+T2"] = t1 + t2
        }
    }

    private static func extractUrssaf(from text: String, into assiettes: inout [String: Double]) {
        // Format : "CTP XXX - NOM ... | montant € | taux | cotisation €"
        // Chercher les lignes avec CTP 027 et CTP 100

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Chercher CTP 027
            if trimmed.contains("027") && trimmed.contains("SYNDIC") {
                if let montant = extractMontantFromLine(trimmed) {
                    assiettes["CTP 027D"] = montant
                    print("  ✅ CTP 027D trouvé : \(montant)")
                }
            }

            // Chercher CTP 100 (peut apparaître plusieurs fois)
            if trimmed.contains("100") && trimmed.contains("RG CAS GENERAL") {
                if let montant = extractMontantFromLine(trimmed) {
                    // Prendre le max si plusieurs occurrences
                    if let existing = assiettes["CTP 100D"] {
                        assiettes["CTP 100D"] = max(existing, montant)
                    } else {
                        assiettes["CTP 100D"] = montant
                    }
                    print("  ✅ CTP 100D trouvé : \(montant)")
                }
            }
        }
    }

    private static func extractMontantFromLine(_ line: String) -> Double? {
        // Cherche "XXXX,XX €" dans la ligne
        let pattern = #"(\d+[\s.,]?\d{3}[.,]\d{2})\s*€"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let montantStr = String(line[range])
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "") // nbsp
            .replacingOccurrences(of: ",", with: ".")

        return Double(montantStr)
    }

    private static func extractArhiaCtp(from text: String, into assiettes: inout [String: Double]) {
        // Format Arhia : "100D SS TOTALITE R.G. Déplaf. 37227.00"
        let ctpPattern = #"(\d{3}[DP])\s+\w+\s+\w+\s+[^\d]*(\d+[.,]\d{2})"#

        guard let regex = try? NSRegularExpression(pattern: ctpPattern) else { return }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let ctpRange = Range(match.range(at: 1), in: text),
                  let montantRange = Range(match.range(at: 2), in: text) else { continue }

            let ctpCode = String(text[ctpRange])
            let montantStr = String(text[montantRange]).replacingOccurrences(of: ",", with: ".")
            if let montant = Double(montantStr) {
                assiettes["CTP \(ctpCode)"] = montant
            }
        }
    }
}
