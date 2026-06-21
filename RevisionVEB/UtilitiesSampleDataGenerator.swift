//
//  SampleDataGenerator.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import Foundation
import SwiftData

/// Génère des données de démo pour tester l'application
@MainActor
struct SampleDataGenerator {
    
    static func generateSampleData(in context: ModelContext) {
        // Clear existing data
        clearAllData(in: context)
        
        // Generate invoices
        let invoices = generateInvoices()
        for invoice in invoices {
            context.insert(invoice)
        }
        
        // Generate import logs
        let logs = generateImportLogs()
        for log in logs {
            context.insert(log)
        }
        
        try? context.save()
    }
    
    private static func clearAllData(in context: ModelContext) {
        // Clear invoices
        let invoiceDescriptor = FetchDescriptor<Invoice>()
        if let invoices = try? context.fetch(invoiceDescriptor) {
            for invoice in invoices {
                context.delete(invoice)
            }
        }
        
        // Clear audit results
        let auditDescriptor = FetchDescriptor<AuditResult>()
        if let results = try? context.fetch(auditDescriptor) {
            for result in results {
                context.delete(result)
            }
        }
        
        // Clear import logs
        let logDescriptor = FetchDescriptor<ImportLog>()
        if let logs = try? context.fetch(logDescriptor) {
            for log in logs {
                context.delete(log)
            }
        }
        
        try? context.save()
    }
    
    private static func generateInvoices() -> [Invoice] {
        let calendar = Calendar.current
        let today = Date()
        
        let suppliers = [
            ("Sysco France", "SYS001"),
            ("Metro Cash & Carry", "MET001"),
            ("Transgourmet", "TRA001"),
            ("Pomona", "POM001"),
            ("Deliveroo", "00FOUR001"), // Code générique
            ("Coca-Cola", "COC001"),
        ]
        
        var invoices: [Invoice] = []
        
        // Generate 20 sample invoices
        for i in 1...20 {
            let daysAgo = Int.random(in: 1...180)
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            
            let supplier = suppliers.randomElement()!
            let netAmount = Double.random(in: 100...5000).rounded(toPlaces: 2)
            let vatRate = [0.055, 0.10, 0.20].randomElement()!
            let grossAmount = (netAmount * (1 + vatRate)).rounded(toPlaces: 2)
            
            // Some invoices have payment dates
            let paymentDate: Date?
            if i % 3 == 0 {
                let paymentDelay = Int.random(in: 10...150)
                paymentDate = calendar.date(byAdding: .day, value: paymentDelay, to: date)
            } else {
                paymentDate = nil
            }
            
            let status: InvoiceStatus
            if let payment = paymentDate {
                let delay = calendar.dateComponents([.day], from: date, to: payment).day ?? 0
                if delay > 120 {
                    status = .overdue
                } else {
                    status = .paid
                }
            } else {
                let daysSince = calendar.dateComponents([.day], from: date, to: today).day ?? 0
                if daysSince > 120 {
                    status = .overdue
                } else {
                    status = .pending
                }
            }
            
            let invoice = Invoice(
                number: String(format: "FAC%03d", i),
                date: date,
                supplier: supplier.0,
                supplierCode: supplier.1,
                netAmount: netAmount,
                vatRate: vatRate,
                grossAmount: grossAmount,
                paymentDate: paymentDate,
                status: status,
                cycle: .fournisseurs,
                sourceFile: "balance_juin_2026.csv",
                restaurant: i % 2 == 0 ? .freddy : .liesel
            )
            
            invoices.append(invoice)
        }
        
        // Add one duplicate invoice (for E.5 test)
        if let original = invoices.first {
            let duplicate = Invoice(
                number: "FAC001_DUP",
                date: calendar.date(byAdding: .day, value: 5, to: original.date) ?? original.date,
                supplier: original.supplier,
                supplierCode: original.supplierCode,
                netAmount: original.netAmount,
                vatRate: original.vatRate,
                grossAmount: original.grossAmount,
                cycle: .fournisseurs,
                sourceFile: "facture_001_duplicate.pdf",
                restaurant: original.restaurant
            )
            invoices.append(duplicate)
        }
        
        // Add one invoice with incorrect VAT (for E.2 test)
        let incorrectVAT = Invoice(
            number: "FAC_BAD_VAT",
            date: today,
            supplier: "Test Fournisseur",
            supplierCode: "TEST001",
            netAmount: 1000.0,
            vatRate: 0.20,
            grossAmount: 1205.0, // Should be 1200.0
            cycle: .fournisseurs,
            sourceFile: "test_vat.pdf",
            restaurant: .freddy
        )
        invoices.append(incorrectVAT)
        
        return invoices
    }
    
    private static func generateImportLogs() -> [ImportLog] {
        let calendar = Calendar.current
        let today = Date()
        
        var logs: [ImportLog] = []
        
        // Recent successful import
        logs.append(ImportLog(
            fileName: "balance_juin_2026.csv",
            fileType: .balanceExcel,
            status: .success,
            recordsCount: 20,
            successCount: 20,
            errorCount: 0,
            timestamp: calendar.date(byAdding: .hour, value: -2, to: today) ?? today,
            restaurant: .freddy
        ))
        
        // PDF import with partial success
        logs.append(ImportLog(
            fileName: "factures_mai_2026.pdf",
            fileType: .invoicePDF,
            status: .partialSuccess,
            recordsCount: 5,
            successCount: 4,
            errorCount: 1,
            timestamp: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
            errorDetails: "1 facture illisible",
            restaurant: .liesel
        ))
        
        // Failed import
        logs.append(ImportLog(
            fileName: "balance_corrupted.csv",
            fileType: .balanceExcel,
            status: .failed,
            recordsCount: 0,
            successCount: 0,
            errorCount: 1,
            timestamp: calendar.date(byAdding: .day, value: -3, to: today) ?? today,
            errorDetails: "Format de fichier invalide",
            restaurant: .freddy
        ))
        
        return logs
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
