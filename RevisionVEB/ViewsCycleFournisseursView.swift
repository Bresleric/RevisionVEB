//
//  CycleFournisseursView.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import SwiftUI
import SwiftData

struct CycleFournisseursView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allInvoices: [Invoice]
    @Query private var allAuditResults: [AuditResult]
    
    private var invoices: [Invoice] {
        allInvoices.filter { $0.cycle == .fournisseurs }
    }
    
    private var auditResults: [AuditResult] {
        allAuditResults.filter { $0.cycle == .fournisseurs }
    }
    
    @State private var isRunningAudit = false
    @State private var showingExportMenu = false
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header avec actions
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cycle E - Fournisseurs")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("\(invoices.count) factures • \(auditResults.count) contrôles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: runAudit) {
                    Label(isRunningAudit ? "Audit en cours..." : "Lancer l'audit", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunningAudit || invoices.isEmpty)
                
                Menu {
                    Button("Export résultats audit (CSV)") {
                        exportAuditResults()
                    }
                    
                    Button("Export maîtresse factures (CSV)") {
                        exportInvoicesMaster()
                    }
                    
                    Button("Export synthèse (CSV)") {
                        exportSynthesis()
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(auditResults.isEmpty)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            // Tabs
            Picker("Vue", selection: $selectedTab) {
                Text("Résultats audit").tag(0)
                Text("Factures").tag(1)
                Text("Statistiques").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                AuditResultsTab(results: auditResults)
                    .tag(0)
                
                InvoicesTab(invoices: invoices)
                    .tag(1)
                
                StatisticsTab(results: auditResults)
                    .tag(2)
            }
            .tabViewStyle(.automatic)
        }
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func runAudit() {
        isRunningAudit = true
        
        Task {
            let engine = AuditEngine(modelContext: modelContext)
            _ = await engine.runFullAuditCycleE()
            
            await MainActor.run {
                isRunningAudit = false
            }
        }
    }
    
    private func exportAuditResults() {
        Task {
            let exporter = ExportManager(modelContext: modelContext)
            if let url = await exporter.exportCycleEResults() {
                exporter.openExportedFile(url)
            }
        }
    }
    
    private func exportInvoicesMaster() {
        Task {
            let exporter = ExportManager(modelContext: modelContext)
            if let url = await exporter.exportInvoicesMaster() {
                exporter.openExportedFile(url)
            }
        }
    }
    
    private func exportSynthesis() {
        Task {
            let exporter = ExportManager(modelContext: modelContext)
            if let url = await exporter.exportSynthesis() {
                exporter.openExportedFile(url)
            }
        }
    }
}

// MARK: - Audit Results Tab

struct AuditResultsTab: View {
    let results: [AuditResult]
    @State private var filterStatus: AuditStatus?
    
    private var filteredResults: [AuditResult] {
        if let status = filterStatus {
            return results.filter { $0.status == status }
        }
        return results
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filtres
            HStack {
                Text("Filtrer par statut:")
                    .font(.subheadline)
                
                Picker("Statut", selection: $filterStatus) {
                    Text("Tous").tag(AuditStatus?.none)
                    ForEach(AuditStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status as AuditStatus?)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 400)
                
                Spacer()
                
                Text("\(filteredResults.count) résultats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
            // Table
            if filteredResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Aucun résultat d'audit")
                        .font(.headline)
                    Text("Lance un audit pour voir les résultats")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredResults) {
                    TableColumn("Règle") { result in
                        Text("\(result.ruleId) - \(result.ruleName)")
                            .fontWeight(.medium)
                    }
                    .width(min: 150)
                    
                    TableColumn("Facture") { result in
                        Text(result.invoiceNumber)
                    }
                    .width(min: 100)
                    
                    TableColumn("Statut") { result in
                        Label(result.status.rawValue, systemImage: statusIcon(result.status))
                            .foregroundStyle(statusColor(result.status))
                    }
                    .width(min: 120)
                    
                    TableColumn("Détails") { result in
                        Text(result.details)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    
                    TableColumn("Écart") { result in
                        if result.variance > 0 {
                            Text("\(String(format: "%.2f", result.variance))€")
                                .foregroundStyle(.red)
                        }
                    }
                    .width(min: 80)
                    
                    TableColumn("Date") { result in
                        Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                    }
                    .width(min: 120)
                }
            }
        }
    }
    
    private func statusIcon(_ status: AuditStatus) -> String {
        switch status {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    private func statusColor(_ status: AuditStatus) -> Color {
        switch status {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }
}

// MARK: - Invoices Tab

struct InvoicesTab: View {
    let invoices: [Invoice]
    
    var body: some View {
        if invoices.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Aucune facture")
                    .font(.headline)
                Text("Importe des factures pour commencer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(invoices) {
                TableColumn("Restaurant") { invoice in
                    Text(invoice.restaurant.rawValue)
                }
                .width(min: 80)
                
                TableColumn("Date") { invoice in
                    Text(invoice.date.formatted(date: .abbreviated, time: .omitted))
                }
                .width(min: 100)
                
                TableColumn("N° Facture") { invoice in
                    Text(invoice.number)
                        .fontWeight(.medium)
                }
                .width(min: 120)
                
                TableColumn("Fournisseur") { invoice in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invoice.supplier)
                        if !invoice.supplierCode.isEmpty {
                            Text(invoice.supplierCode)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                TableColumn("HT") { invoice in
                    Text("\(String(format: "%.2f", invoice.netAmount))€")
                }
                .width(min: 80)
                
                TableColumn("TVA") { invoice in
                    Text("\(String(format: "%.0f", invoice.vatRate * 100))%")
                }
                .width(min: 60)
                
                TableColumn("TTC") { invoice in
                    Text("\(String(format: "%.2f", invoice.grossAmount))€")
                        .fontWeight(.medium)
                }
                .width(min: 80)
                
                TableColumn("Statut") { invoice in
                    Text(invoice.status.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusBackground(invoice.status))
                        .cornerRadius(4)
                }
                .width(min: 100)
            }
        }
    }
    
    private func statusBackground(_ status: InvoiceStatus) -> Color {
        switch status {
        case .matched, .paid: return .green.opacity(0.2)
        case .overdue: return .red.opacity(0.2)
        case .disputed: return .orange.opacity(0.2)
        case .canceled: return .gray.opacity(0.2)
        case .pending: return .blue.opacity(0.2)
        }
    }
}

// MARK: - Statistics Tab

struct StatisticsTab: View {
    let results: [AuditResult]
    
    private var ruleStats: [(String, Int, Int, Int)] {
        let grouped = Dictionary(grouping: results, by: { $0.ruleId })
        return grouped.map { ruleId, ruleResults in
            let passed = ruleResults.filter { $0.status == .passed }.count
            let warnings = ruleResults.filter { $0.status == .warning }.count
            let failed = ruleResults.filter { $0.status == .failed }.count
            return (ruleId, passed, warnings, failed)
        }.sorted { $0.0 < $1.0 }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Résumé global
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Résumé global")
                            .font(.headline)
                        
                        HStack(spacing: 32) {
                            StatItem(
                                label: "Tests réalisés",
                                value: "\(results.count)",
                                color: .blue
                            )
                            
                            StatItem(
                                label: "Conformes",
                                value: "\(results.filter { $0.status == .passed }.count)",
                                color: .green
                            )
                            
                            StatItem(
                                label: "Alertes",
                                value: "\(results.filter { $0.status == .warning }.count)",
                                color: .orange
                            )
                            
                            StatItem(
                                label: "Anomalies",
                                value: "\(results.filter { $0.status == .failed }.count)",
                                color: .red
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
                .padding()
                
                // Stats par règle
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Détail par règle")
                            .font(.headline)
                        
                        ForEach(ruleStats, id: \.0) { ruleId, passed, warnings, failed in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ruleId)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                HStack(spacing: 4) {
                                    ProgressSegment(value: passed, total: passed + warnings + failed, color: .green)
                                    ProgressSegment(value: warnings, total: passed + warnings + failed, color: .orange)
                                    ProgressSegment(value: failed, total: passed + warnings + failed, color: .red)
                                }
                                .frame(height: 20)
                                
                                HStack {
                                    Text("✅ \(passed)")
                                        .font(.caption)
                                    Text("⚠️ \(warnings)")
                                        .font(.caption)
                                    Text("❌ \(failed)")
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(color)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ProgressSegment: View {
    let value: Int
    let total: Int
    let color: Color
    
    private var percentage: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(value) / CGFloat(total)
    }
    
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(color)
                .frame(width: geometry.size.width * percentage)
        }
    }
}

#Preview {
    CycleFournisseursView()
        .modelContainer(for: Invoice.self, inMemory: true)
        .frame(width: 1200, height: 800)
}
