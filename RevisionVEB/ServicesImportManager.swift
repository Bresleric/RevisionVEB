//
//  ImportManager.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import Foundation
import SwiftData
import PDFKit
import UniformTypeIdentifiers
import Combine

/// Gestion des imports PDF et Excel
@MainActor
final class ImportManager: ObservableObject {
    var modelContext: ModelContext
    @Published var isImporting = false
    @Published var importProgress = 0.0
    @Published var lastError: String?
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Import PDF Facture
    
    func importInvoicePDF(url: URL, restaurant: Restaurant) async -> ImportLog {
        isImporting = true
        importProgress = 0.0
        
        let log = ImportLog(
            fileName: url.lastPathComponent,
            fileType: .invoicePDF,
            restaurant: restaurant
        )
        
        guard let pdfDocument = PDFDocument(url: url) else {
            log.status = .failed
            log.errorDetails = "Impossible de lire le PDF"
            isImporting = false
            return log
        }
        
        // Extraction basique du texte
        var fullText = ""
        for pageIndex in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: pageIndex) {
                fullText += page.string ?? ""
            }
        }
        
        // Parsing basique (à améliorer avec regex spécifiques)
        let invoice = parseInvoiceFromText(fullText, sourceFile: url.lastPathComponent, restaurant: restaurant)
        
        if let invoice = invoice {
            modelContext.insert(invoice)
            log.status = .success
            log.recordsCount = 1
            log.successCount = 1
        } else {
            log.status = .failed
            log.errorDetails = "Impossible d'extraire les données de la facture"
        }
        
        modelContext.insert(log)
        try? modelContext.save()
        
        isImporting = false
        importProgress = 1.0
        
        return log
    }
    
    private func parseInvoiceFromText(_ text: String, sourceFile: String, restaurant: Restaurant) -> Invoice? {
        // Pattern matching basique - à adapter selon vos formats
        let lines = text.components(separatedBy: .newlines)
        
        var number: String?
        var date: Date?
        let supplier: String? = nil // TODO: Extraire du PDF dans une version future
        var netAmount: Double?
        var grossAmount: Double?
        let vatRate: Double = 0.20 // Défaut 20%
        
        // Recherche patterns courants
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Numéro facture
            if trimmed.contains("Facture") || trimmed.contains("N°") {
                let components = trimmed.components(separatedBy: .whitespaces)
                number = components.last
            }
            
            // Date
            if trimmed.contains("/") && trimmed.count < 15 {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd/MM/yyyy"
                if let parsed = dateFormatter.date(from: trimmed) {
                    date = parsed
                }
            }
            
            // Montants
            if trimmed.contains("€") {
                let cleaned = trimmed.replacingOccurrences(of: "€", with: "")
                    .replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespaces)
                
                if let amount = Double(cleaned) {
                    if trimmed.lowercased().contains("total") || trimmed.lowercased().contains("ttc") {
                        grossAmount = amount
                    } else if trimmed.lowercased().contains("ht") {
                        netAmount = amount
                    }
                }
            }
        }
        
        // Validation minimale
        guard let invoiceNumber = number,
              let invoiceDate = date,
              let net = netAmount,
              let gross = grossAmount else {
            return nil
        }
        
        return Invoice(
            number: invoiceNumber,
            date: invoiceDate,
            supplier: supplier ?? "Fournisseur inconnu",
            supplierCode: "",
            netAmount: net,
            vatRate: vatRate,
            grossAmount: gross,
            cycle: .fournisseurs,
            sourceFile: sourceFile,
            restaurant: restaurant
        )
    }
    
    // MARK: - Import Balance comptable (CSV / TXT)

    func importBalance(url: URL, exerciceID: UUID) async -> ImportLog {
        print("📊 ImportManager.importBalance: \(url.lastPathComponent)")

        isImporting = true
        importProgress = 0.0

        let log = ImportLog(
            fileName: url.lastPathComponent,
            fileType: .balanceExcel,
            exerciceID: exerciceID
        )

        guard FileManager.default.fileExists(atPath: url.path) else {
            log.status = .failed
            log.errorDetails = "Fichier introuvable (s'il est dans iCloud/OneDrive, telecharge-le d'abord)."
            modelContext.insert(log); try? modelContext.save()
            isImporting = false
            return log
        }

        let ext = url.pathExtension.lowercased()
        if ext == "xlsx" || ext == "xls" {
            log.status = .failed
            log.errorDetails = "Format Excel pas encore active. Exporte en CSV pour l'instant — le .xlsx natif arrive juste apres."
            modelContext.insert(log); try? modelContext.save()
            isImporting = false
            return log
        }

        guard let content = readTextWithBestEncoding(url: url) else {
            log.status = .failed
            log.errorDetails = "Impossible de lire le fichier (encodage non reconnu)."
            modelContext.insert(log); try? modelContext.save()
            isImporting = false
            return log
        }

        return await processBalance(content: content, fileName: url.lastPathComponent, exerciceID: exerciceID, log: log)
    }
    
    // MARK: - Lecture texte (detection auto de l'encodage)

    /// Lit le fichier en essayant plusieurs encodages, et garde celui dont
    /// l'en-tete contient le plus de mots-cles comptables. Gere CSV (UTF-8/BOM),
    /// TXT Mac Roman, Windows-1252, etc.
    private func readTextWithBestEncoding(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let encodings: [String.Encoding] = [.utf8, .macOSRoman, .windowsCP1252, .isoLatin1, .utf16]
        var best: (text: String, score: Int)? = nil
        for enc in encodings {
            guard let s = String(data: data, encoding: enc) else { continue }
            let score = Self.headerScore(s)
            if best == nil || score > best!.score { best = (s, score) }
            if score >= 4 { break } // en-tete clairement reconnu
        }
        return best?.text.replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR")).lowercased()
    }

    private static func headerScore(_ content: String) -> Int {
        let first = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").first ?? ""
        let f = fold(first)
        return ["compte", "debit", "credit", "solde", "intitul"].reduce(0) { $0 + (f.contains($1) ? 1 : 0) }
    }

    /// Parse un montant a la francaise : espaces (milliers), virgule decimale,
    /// zero-padding ("000" -> 0, "011" -> 11, "-54 054" -> -54054).
    static func parseFrenchAmount(_ raw: String) -> Double? {
        var s = raw
        for sp in ["\u{00A0}", "\u{202F}", "\u{2009}", " "] { s = s.replacingOccurrences(of: sp, with: "") }
        s = s.replacingOccurrences(of: "€", with: "")
             .replacingOccurrences(of: ",", with: ".")
             .trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        return Double(s)
    }

    private struct BalanceColumns {
        var compte = -1, code = -1, intitule = -1, debit = -1, credit = -1, soldeN = -1, soldeN1 = -1
    }

    private static func detectSeparator(_ headerLine: String) -> String {
        if headerLine.contains("\t") { return "\t" }
        if headerLine.contains(";") { return ";" }
        if headerLine.contains(",") { return "," }
        return ";"
    }

    private static func detectColumns(_ header: [String]) -> BalanceColumns {
        var m = BalanceColumns()
        for (i, raw) in header.enumerated() {
            let c = fold(raw)
            if c.contains("compte") && m.compte < 0 { m.compte = i }
            else if (c.contains("appel") || c.contains("cle")) && m.code < 0 { m.code = i }
            else if (c.contains("intitul") || c.contains("libell")) && m.intitule < 0 { m.intitule = i }
            else if c.contains("debit") && m.debit < 0 { m.debit = i }
            else if c.contains("credit") && m.credit < 0 { m.credit = i }
            else if (c.contains("n-1") || c.contains("n - 1")) && m.soldeN1 < 0 { m.soldeN1 = i }
            else if c.contains("n-2") || c.contains("n - 2") { /* ignore le solde N-2 */ }
            else if c.contains("solde") && m.soldeN < 0 { m.soldeN = i }
        }
        return m
    }

    // MARK: - Traitement de la balance -> BalanceAccount

    private func processBalance(content: String, fileName: String, exerciceID: UUID, log: ImportLog) async -> ImportLog {
        // Normalise les fins de ligne (\r seul, \r\n, \n)
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let headerLine = lines.first else {
            log.status = .failed
            log.errorDetails = "Fichier vide."
            modelContext.insert(log); try? modelContext.save()
            isImporting = false
            return log
        }

        let sep = Self.detectSeparator(headerLine)
        let header = headerLine.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }
        let cols = Self.detectColumns(header)

        guard cols.compte >= 0 else {
            log.status = .failed
            log.errorDetails = "Colonne 'Compte' introuvable dans l'en-tete."
            modelContext.insert(log); try? modelContext.save()
            isImporting = false
            return log
        }

        // Remplace la balance precedente du meme exercice
        if let existing = try? modelContext.fetch(FetchDescriptor<BalanceAccount>()) {
            for acc in existing where acc.exerciceID == exerciceID {
                modelContext.delete(acc)
            }
        }

        func value(_ row: [String], _ idx: Int) -> String {
            (idx >= 0 && idx < row.count) ? row[idx] : ""
        }

        var success = 0
        var skipped = 0
        let total = max(lines.count - 1, 1)

        for (i, line) in lines.dropFirst().enumerated() {
            let row = line.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }
            let compte = value(row, cols.compte)
            if compte.isEmpty { skipped += 1; continue }
            // Exclure les lignes de sous-total / total (ex: 10ZZZZZZZZ, 5ZZZZZZZZZ)
            if compte.uppercased().contains("ZZZ") { skipped += 1; continue }

            let account = BalanceAccount(
                accountNumber: compte,
                accountCode: value(row, cols.code),
                accountLabel: value(row, cols.intitule),
                debit: Self.parseFrenchAmount(value(row, cols.debit)) ?? 0,
                credit: Self.parseFrenchAmount(value(row, cols.credit)) ?? 0,
                balanceN: Self.parseFrenchAmount(value(row, cols.soldeN)) ?? 0,
                balanceNMinus1: Self.parseFrenchAmount(value(row, cols.soldeN1)) ?? 0,
                exerciceID: exerciceID,
                sourceFile: fileName
            )
            modelContext.insert(account)
            success += 1
            if i % 25 == 0 { importProgress = Double(i) / Double(total) }
        }

        log.recordsCount = success
        log.successCount = success
        log.errorCount = 0
        log.status = success > 0 ? .success : .failed
        if success == 0 { log.errorDetails = "Aucun compte detecte dans le fichier." }
        modelContext.insert(log)
        try? modelContext.save()

        // Calcul automatique des SIG
        if success > 0 {
            do {
                let descriptor = FetchDescriptor<BalanceAccount>()
                let accounts = try modelContext.fetch(descriptor).filter { $0.exerciceID == exerciceID }
                SigCalculator.calculateAndStore(exerciceID: exerciceID, from: accounts, in: modelContext)
                print("📊 SIG calculés automatiquement: \(accounts.count) comptes")
            } catch {
                print("⚠️ Erreur lors du calcul des SIG: \(error)")
            }
        }

        isImporting = false
        importProgress = 1.0
        print("📊 Balance importee: \(success) comptes (\(skipped) lignes ignorees)")
        return log
    }
}
