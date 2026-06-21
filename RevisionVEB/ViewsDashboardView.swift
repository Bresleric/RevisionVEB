//
//  DashboardView.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var invoices: [Invoice]
    @Query private var auditResults: [AuditResult]
    @Query private var importLogs: [ImportLog]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dashboard PLANB")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Audit comptable - Freddy & Chez Tante Liesel")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(Date.now.formatted(date: .long, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                // Stats Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    StatCard(
                        title: "Factures",
                        value: "\(invoices.count)",
                        icon: "doc.text",
                        color: .blue
                    )
                    
                    StatCard(
                        title: "Imports",
                        value: "\(importLogs.count)",
                        icon: "arrow.down.doc",
                        color: .green
                    )
                    
                    StatCard(
                        title: "Anomalies",
                        value: "\(auditResults.filter { $0.status == .failed }.count)",
                        icon: "exclamationmark.triangle",
                        color: .red
                    )
                }
                .padding(.horizontal)
                
                // Charts Section
                HStack(spacing: 16) {
                    // Conformité
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Taux de conformité")
                                .font(.headline)
                            
                            ConformityChart(results: auditResults)
                                .frame(height: 200)
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Imports récents
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Imports récents")
                                .font(.headline)
                            
                            if importLogs.isEmpty {
                                Text("Aucun import")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            } else {
                                ForEach(importLogs.prefix(5)) { log in
                                    HStack {
                                        Image(systemName: log.fileType.icon)
                                            .foregroundStyle(log.status == .success ? .green : .orange)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(log.fileName)
                                                .font(.subheadline)
                                                .lineLimit(1)
                                            
                                            Text("\(log.successCount)/\(log.recordsCount) réussis")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(log.timestamp.formatted(date: .omitted, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                
                // Anomalies récentes
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Anomalies récentes")
                            .font(.headline)
                        
                        if auditResults.filter({ $0.status == .failed }).isEmpty {
                            Text("Aucune anomalie détectée ✅")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(auditResults.filter { $0.status == .failed }.prefix(8)) { result in
                                HStack {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(.red)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(result.ruleId) - \(result.invoiceNumber)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        Text(result.details)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    if result.variance > 0 {
                                        Text("\(String(format: "%.2f", result.variance))€")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        GroupBox {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(color)
                
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

// MARK: - Conformity Chart

struct ConformityChart: View {
    let results: [AuditResult]
    
    private var chartData: [(String, Int)] {
        let passed = results.filter { $0.status == .passed }.count
        let warnings = results.filter { $0.status == .warning }.count
        let failed = results.filter { $0.status == .failed }.count
        
        return [
            ("Conformes", passed),
            ("Alertes", warnings),
            ("Anomalies", failed)
        ]
    }
    
    var body: some View {
        if results.isEmpty {
            Text("Aucun audit réalisé")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            Chart(chartData, id: \.0) { item in
                BarMark(
                    x: .value("Statut", item.0),
                    y: .value("Nombre", item.1)
                )
                .foregroundStyle(by: .value("Statut", item.0))
            }
            .chartForegroundStyleScale([
                "Conformes": .green,
                "Alertes": .orange,
                "Anomalies": .red
            ])
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: Invoice.self, inMemory: true)
        .frame(width: 1200, height: 800)
}
