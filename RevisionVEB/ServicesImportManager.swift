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
    
    // MARK: - Import Excel (simulation CSV)
    
    func importBalanceExcel(url: URL, restaurant: Restaurant) async -> ImportLog {
        print("📊 ImportManager.importBalanceExcel appelé")
        print("📁 Fichier: \(url.lastPathComponent)")
        print("🏪 Restaurant: \(restaurant.rawValue)")
        print("📍 Chemin complet: \(url.path)")
        
        isImporting = true
        importProgress = 0.0
        
        let log = ImportLog(
            fileName: url.lastPathComponent,
            fileType: .balanceExcel,
            restaurant: restaurant
        )
        
        // Vérifier si le fichier existe
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            print("❌ Le fichier n'existe pas à ce chemin")
            log.status = .failed
            log.errorDetails = "Fichier introuvable"
            isImporting = false
            return log
        }
        
        // Détecter le type de fichier
        let ext = url.pathExtension.lowercased()
        
        if ext == "xlsx" || ext == "xls" {
            // Pour les fichiers Excel, demander à l'utilisateur d'exporter en CSV/TXT
            print("⚠️ Fichier Excel détecté - veuillez exporter en CSV pour l'instant")
            log.status = .failed
            log.errorDetails = "Format Excel non supporté. Veuillez exporter votre fichier en format CSV ou TXT."
            isImporting = false
            return log
        } else {
            // Parser CSV/TXT
            return await importTextFile(url: url, restaurant: restaurant, log: log)
        }
    }
    
    // MARK: - Import fichier texte (CSV/TXT)
    
    private func importTextFile(url: URL, restaurant: Restaurant, log: ImportLog) async -> ImportLog {
        
        // Lecture fichier texte (CSV ou tab-separated)
        // Essayer plusieurs encodages
        var content: String?
        let encodings: [String.Encoding] = [.utf8, .utf16, .windowsCP1252, .macOSRoman, .isoLatin1]
        
        for encoding in encodings {
            do {
                content = try String(contentsOf: url, encoding: encoding)
                print("✅ Fichier lu avec encodage \(encoding): \(content!.count) caractères")
                break
            } catch {
                print("⚠️ Échec avec encodage \(encoding): \(error.localizedDescription)")
                continue
            }
        }
        
        guard let fileContent = content else {
            print("❌ Impossible de lire le fichier avec aucun encodage")
            log.status = .failed
            log.errorDetails = "Format de fichier non reconnu"
            isImporting = false
            return log
        }
        
        return await processBalanceContent(content: fileContent, fileName: url.lastPathComponent, restaurant: restaurant, log: log)
    }
    
    private func processBalanceContent(content: String, fileName: String, restaurant: Restaurant, log: ImportLog) async -> ImportLog {
        let lines = content.components(separatedBy: .newlines)
        print("📝 Nombre de lignes: \(lines.count)")
        
        var successCount = 0
        var errorCount = 0
        
        // Skip header
        for line in lines.dropFirst() where !line.isEmpty {
            let columns = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            
            print("🔍 Ligne: \(columns.count) colonnes - \(columns.joined(separator: " | "))")
            
            // Format attendu: Date | N° | Fournisseur | Code | Net | TVA | Gross
            if columns.count >= 7 {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd/MM/yyyy"
                
                if let date = dateFormatter.date(from: columns[0]),
                   let net = Double(columns[4].replacingOccurrences(of: ",", with: ".")),
                   let vatRate = Double(columns[5].replacingOccurrences(of: ",", with: ".")),
                   let gross = Double(columns[6].replacingOccurrences(of: ",", with: ".")) {
                    
                    let invoice = Invoice(
                        number: columns[1],
                        date: date,
                        supplier: columns[2],
                        supplierCode: columns[3],
                        netAmount: net,
                        vatRate: vatRate,
                        grossAmount: gross,
                        cycle: .fournisseurs,
                        sourceFile: fileName,
                        restaurant: restaurant
                    )
                    
                    modelContext.insert(invoice)
                    successCount += 1
                    print("✅ Facture importée: \(columns[1])")
                } else {
                    errorCount += 1
                    print("❌ Erreur parsing: date=\(columns[0]), net=\(columns[4]), vat=\(columns[5]), gross=\(columns[6])")
                }
            } else {
                errorCount += 1
                print("❌ Pas assez de colonnes: \(columns.count)")
            }
        }
        
        print("📊 Résultat: \(successCount) réussis, \(errorCount) erreurs")
        
        log.recordsCount = successCount + errorCount
        log.successCount = successCount
        log.errorCount = errorCount
        log.status = errorCount == 0 ? .success : .partialSuccess
        
        modelContext.insert(log)
        try? modelContext.save()
        
        isImporting = false
        importProgress = 1.0
        
        return log
    }
}
