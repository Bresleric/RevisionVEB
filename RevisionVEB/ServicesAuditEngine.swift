//
//  AuditEngine.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import Foundation
import SwiftData

/// Moteur d'audit pour les 4 cycles comptables
@MainActor
final class AuditEngine {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Cycle E: Fournisseurs
    
    /// E.1: Matching factures PDF ↔ fichiers Cegid
    func auditMatchingInvoices() async -> [AuditResult] {
        var results: [AuditResult] = []
        let descriptor = FetchDescriptor<Invoice>()
        
        guard let allInvoices = try? modelContext.fetch(descriptor) else {
            return results
        }
        
        let invoices = allInvoices.filter { $0.cycle == .fournisseurs }
        
        for invoice in invoices {
            // Chercher des correspondances par numéro (excluant la facture elle-même)
            let matches = allInvoices.filter { otherInvoice in
                otherInvoice.number == invoice.number &&
                otherInvoice.id != invoice.id
            }
            
            if matches.isEmpty {
                results.append(AuditResult(
                    ruleId: "E.1",
                    ruleName: "Matching facture",
                    invoiceId: invoice.id,
                    invoiceNumber: invoice.number,
                    status: .failed,
                    details: "Aucune correspondance Cegid trouvée",
                    cycle: .fournisseurs,
                    severity: .critical
                ))
            } else {
                results.append(AuditResult(
                    ruleId: "E.1",
                    ruleName: "Matching facture",
                    invoiceId: invoice.id,
                    invoiceNumber: invoice.number,
                    status: .passed,
                    details: "Correspondance trouvée",
                    cycle: .fournisseurs,
                    severity: .info
                ))
            }
        }
        
        return results
    }
    
    /// E.2: Validation TVA (net × (1 + taux) = gross)
    func auditVATCalculation() async -> [AuditResult] {
        var results: [AuditResult] = []
        let descriptor = FetchDescriptor<Invoice>()
        
        guard let allInvoices = try? modelContext.fetch(descriptor) else {
            return results
        }
        
        let invoices = allInvoices.filter { $0.cycle == .fournisseurs }
        
        for invoice in invoices {
            let expectedGross = invoice.netAmount * (1 + invoice.vatRate)
            let variance = abs(expectedGross - invoice.grossAmount)
            
            if variance > 0.01 {
                results.append(AuditResult(
                    ruleId: "E.2",
                    ruleName: "Validation TVA",
                    invoiceId: invoice.id,
                    invoiceNumber: invoice.number,
                    status: .failed,
                    details: "Écart TVA: \(String(format: "%.2f", variance))€ (attendu: \(String(format: "%.2f", expectedGross))€, trouvé: \(String(format: "%.2f", invoice.grossAmount))€)",
                    variance: variance,
                    cycle: .fournisseurs,
                    severity: .critical
                ))
            } else {
                results.append(AuditResult(
                    ruleId: "E.2",
                    ruleName: "Validation TVA",
                    invoiceId: invoice.id,
                    invoiceNumber: invoice.number,
                    status: .passed,
                    details: "TVA conforme",
                    variance: variance,
                    cycle: .fournisseurs,
                    severity: .info
                ))
            }
        }
        
        return results
    }
    
    /// E.3: Codes fournisseurs normalisés
    func auditSupplierCodes() async -> [AuditResult] {
        var results: [AuditResult] = []
        let descriptor = FetchDescriptor<Invoice>()
        
        guard let allInvoices = try? modelContext.fetch(descriptor) else {
            return results
        }
        
        let invoices = allInvoices.filter { $0.cycle == .fournisseurs }
        
        for invoice in invoices {
            if invoice.supplierCode.hasPrefix("00FOUR") {
                results.append(AuditResult(
                    ruleId: "E.3",
                    ruleName: "Code fournisseur",
                    invoiceId: invoice.id,
                    invoiceNumber: invoice.number,
                    status: .warning,
                    details: "Code générique détecté: \(invoice.supplierCode)",
                    cycle: .fournisseurs,
                    severity: .warning
                ))
            } else if invoice.supplierCode.isEmpty {
                results.append(AuditResult(
                    ruleId: "E.3",
                    ruleName: "Code fournisseur",
                    invoiceId: invoice.id,
                    invoiceNumber: invoice.number,
                    status: .failed,
                    details: "Code fournisseur manquant",
                    cycle: .fournisseurs,
                    severity: .critical
                ))
            } else {
                results.append(AuditResult(
                    ruleId: "E.3",
                    ruleName: "Code fournisseur",
                    invoiceId: invoice.id,
                    invoiceNumber: invoice.number,
                    status: .passed,
                    details: "Code fournisseur valide: \(invoice.supplierCode)",
                    cycle: .fournisseurs,
                    severity: .info
                ))
            }
        }
        
        return results
    }
    
    /// E.4: Délai paiement < 90j
    func auditPaymentDelay() async -> [AuditResult] {
        var results: [AuditResult] = []
        let descriptor = FetchDescriptor<Invoice>()
        
        guard let allInvoices = try? modelContext.fetch(descriptor) else {
            return results
        }
        
        let invoices = allInvoices.filter { $0.cycle == .fournisseurs }
        
        for invoice in invoices {
            guard let paymentDate = invoice.paymentDate else {
                let daysSinceInvoice = Calendar.current.dateComponents([.day], from: invoice.date, to: Date()).day ?? 0
                
                if daysSinceInvoice > 120 {
                    results.append(AuditResult(
                        ruleId: "E.4",
                        ruleName: "Délai paiement",
                        invoiceId: invoice.id,
                        invoiceNumber: invoice.number,
                        status: .failed,
                        details: "Facture impayée depuis \(daysSinceInvoice) jours",
                        variance: Double(daysSinceInvoice),
                        cycle: .fournisseurs,
                        severity: .critical
                    ))
                } else if daysSinceInvoice > 90 {
                    results.append(AuditResult(
                        ruleId: "E.4",
                        ruleName: "Délai paiement",
                        invoiceId: invoice.id,
                        invoiceNumber: invoice.number,
                        status: .warning,
                        details: "Facture impayée depuis \(daysSinceInvoice) jours",
                        variance: Double(daysSinceInvoice),
                        cycle: .fournisseurs,
                        severity: .warning
                    ))
                }
                continue
            }
            
            let delayDays = Calendar.current.dateComponents([.day], from: invoice.date, to: paymentDate).day ?? 0
            
            if delayDays > 120 {
                results.append(AuditResult(
                    ruleId: "E.4",
                    ruleName: "Délai paiement",
                    invoiceId: invoice.id,
                    invoiceNumber: invoice.number,
                    status: .failed,
                    details: "Délai de paiement excessif: \(delayDays) jours",
                    variance: Double(delayDays),
                    cycle: .fournisseurs,
                    severity: .critical
                ))
            } else if delayDays > 90 {
                results.append(AuditResult(
                    ruleId: "E.4",
                    ruleName: "Délai paiement",
                    invoiceId: invoice.id,
                    invoiceNumber: invoice.number,
                    status: .warning,
                    details: "Délai de paiement élevé: \(delayDays) jours",
                    variance: Double(delayDays),
                    cycle: .fournisseurs,
                    severity: .warning
                ))
            } else {
                results.append(AuditResult(
                    ruleId: "E.4",
                    ruleName: "Délai paiement",
                    invoiceId: invoice.id,
                    invoiceNumber: invoice.number,
                    status: .passed,
                    details: "Délai conforme: \(delayDays) jours",
                    variance: Double(delayDays),
                    cycle: .fournisseurs,
                    severity: .info
                ))
            }
        }
        
        return results
    }
    
    /// E.5: Détection doubles-factures (30j window)
    func auditDuplicateInvoices() async -> [AuditResult] {
        var results: [AuditResult] = []
        let descriptor = FetchDescriptor<Invoice>(
            sortBy: [SortDescriptor(\.date)]
        )
        
        guard let allInvoices = try? modelContext.fetch(descriptor) else {
            return results
        }
        
        let invoices = allInvoices.filter { $0.cycle == .fournisseurs }
        
        var checkedPairs = Set<String>()
        
        for invoice in invoices {
            let windowStart = Calendar.current.date(byAdding: .day, value: -30, to: invoice.date) ?? invoice.date
            let windowEnd = Calendar.current.date(byAdding: .day, value: 30, to: invoice.date) ?? invoice.date
            
            // Chercher des doublons potentiels dans la fenêtre de 30 jours
            let duplicates = allInvoices.filter { otherInvoice in
                otherInvoice.id != invoice.id &&
                otherInvoice.supplier == invoice.supplier &&
                otherInvoice.grossAmount == invoice.grossAmount &&
                otherInvoice.date >= windowStart &&
                otherInvoice.date <= windowEnd
            }
            
            if !duplicates.isEmpty {
                for duplicate in duplicates {
                    let pairKey = [invoice.id.uuidString, duplicate.id.uuidString].sorted().joined(separator: "-")
                    
                    if !checkedPairs.contains(pairKey) {
                        checkedPairs.insert(pairKey)
                        
                        results.append(AuditResult(
                            ruleId: "E.5",
                            ruleName: "Doubles factures",
                            invoiceId: invoice.id,
                            invoiceNumber: invoice.number,
                            status: .failed,
                            details: "Doublon potentiel avec \(duplicate.number) (\(duplicate.supplier), \(String(format: "%.2f", duplicate.grossAmount))€)",
                            cycle: .fournisseurs,
                            severity: .critical
                        ))
                    }
                }
            }
        }
        
        return results
    }
    
    // MARK: - Audit complet Cycle E
    
    func runFullAuditCycleE() async -> [AuditResult] {
        async let matching = auditMatchingInvoices()
        async let vat = auditVATCalculation()
        async let codes = auditSupplierCodes()
        async let delays = auditPaymentDelay()
        async let duplicates = auditDuplicateInvoices()
        
        let allResults = await matching + vat + codes + delays + duplicates
        
        // Sauvegarder les résultats
        for result in allResults {
            modelContext.insert(result)
        }
        
        try? modelContext.save()
        
        return allResults
    }
}
