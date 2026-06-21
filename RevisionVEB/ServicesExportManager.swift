//
//  ExportManager.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import Foundation
import SwiftData
import AppKit

/// Gestion des exports Excel (CSV pour MVP)
@MainActor
final class ExportManager {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Export Cycle E
    
    func exportCycleEResults() async -> URL? {
        let descriptor = FetchDescriptor<AuditResult>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        guard let allResults = try? modelContext.fetch(descriptor) else {
            return nil
        }
        
        let results = allResults.filter { $0.cycle == .fournisseurs }
        
        var csvContent = "Date,Règle,N° Facture,Statut,Détails,Écart\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
        
        for result in results {
            let date = dateFormatter.string(from: result.timestamp)
            let rule = "\(result.ruleId) - \(result.ruleName)"
            let status = result.status.rawValue
            let details = result.details.replacingOccurrences(of: ",", with: ";")
            let variance = String(format: "%.2f", result.variance)
            
            csvContent += "\"\(date)\",\"\(rule)\",\"\(result.invoiceNumber)\",\"\(status)\",\"\(details)\",\"\(variance)\"\n"
        }
        
        // Sauvegarder
        let fileName = "PLANB_Audit_CycleE_\(Date().timeIntervalSince1970).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        try? csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        return tempURL
    }
    
    func exportInvoicesMaster() async -> URL? {
        let descriptor = FetchDescriptor<Invoice>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        guard let allInvoices = try? modelContext.fetch(descriptor) else {
            return nil
        }
        
        let invoices = allInvoices.filter { $0.cycle == .fournisseurs }
        
        var csvContent = "Restaurant,Date,N° Facture,Fournisseur,Code,HT,TVA,TTC,Date Paiement,Statut,Source\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        
        for invoice in invoices {
            let date = dateFormatter.string(from: invoice.date)
            let paymentDate = invoice.paymentDate.map { dateFormatter.string(from: $0) } ?? ""
            
            csvContent += "\"\(invoice.restaurant.rawValue)\","
            csvContent += "\"\(date)\","
            csvContent += "\"\(invoice.number)\","
            csvContent += "\"\(invoice.supplier)\","
            csvContent += "\"\(invoice.supplierCode)\","
            csvContent += "\(String(format: "%.2f", invoice.netAmount)),"
            csvContent += "\(String(format: "%.2f", invoice.vatRate * 100))%,"
            csvContent += "\(String(format: "%.2f", invoice.grossAmount)),"
            csvContent += "\"\(paymentDate)\","
            csvContent += "\"\(invoice.status.rawValue)\","
            csvContent += "\"\(invoice.sourceFile)\"\n"
        }
        
        let fileName = "PLANB_Maitresse_Factures_\(Date().timeIntervalSince1970).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        try? csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        return tempURL
    }
    
    func exportSynthesis() async -> URL? {
        let resultDescriptor = FetchDescriptor<AuditResult>()
        guard let results = try? modelContext.fetch(resultDescriptor) else {
            return nil
        }
        
        let totalTests = results.count
        let passed = results.filter { $0.status == .passed }.count
        let warnings = results.filter { $0.status == .warning }.count
        let failed = results.filter { $0.status == .failed }.count
        
        let conformityRate = totalTests > 0 ? Double(passed) / Double(totalTests) * 100 : 0
        
        var csvContent = "PLANB SARL - Synthèse Audit Comptable\n"
        csvContent += "Date: \(Date().formatted())\n\n"
        csvContent += "Tests réalisés,\(totalTests)\n"
        csvContent += "Conformes,\(passed)\n"
        csvContent += "Alertes,\(warnings)\n"
        csvContent += "Anomalies,\(failed)\n"
        csvContent += "Taux de conformité,\(String(format: "%.1f", conformityRate))%\n\n"
        
        csvContent += "Détail par règle\n"
        csvContent += "Règle,Conformes,Alertes,Anomalies\n"
        
        let ruleGroups = Dictionary(grouping: results, by: { $0.ruleId })
        for (ruleId, ruleResults) in ruleGroups.sorted(by: { $0.key < $1.key }) {
            let rulePassed = ruleResults.filter { $0.status == .passed }.count
            let ruleWarnings = ruleResults.filter { $0.status == .warning }.count
            let ruleFailed = ruleResults.filter { $0.status == .failed }.count
            
            csvContent += "\"\(ruleId)\",\(rulePassed),\(ruleWarnings),\(ruleFailed)\n"
        }
        
        let fileName = "PLANB_Synthese_\(Date().timeIntervalSince1970).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        try? csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        return tempURL
    }
    
    func openExportedFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
