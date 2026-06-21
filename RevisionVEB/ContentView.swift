//
//  ContentView.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSection: NavSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedSection: $selectedSection)
        } detail: {
            DetailContentView(section: selectedSection)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Navigation Section

enum NavSection: Hashable, Identifiable {
    case dashboard
    case importData
    case cycle(RevisionCycle)
    case settings

    var id: String {
        switch self {
        case .dashboard:        return "dashboard"
        case .importData:       return "import"
        case .cycle(let c):     return "cycle-\(c.rawValue)"
        case .settings:         return "settings"
        }
    }

    var title: String {
        switch self {
        case .dashboard:        return "Dashboard"
        case .importData:       return "Import"
        case .cycle(let c):     return c.rawValue
        case .settings:         return "Réglages"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:        return "gauge.with.dots.needle.67percent"
        case .importData:       return "arrow.down.doc"
        case .cycle(let c):     return c.icon
        case .settings:         return "gearshape"
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedSection: NavSection?

    private let cycles = RevisionCycle.allCases.filter { $0 != .nonClasse }

    var body: some View {
        List(selection: $selectedSection) {
            Section("Vue d'ensemble") {
                row(.dashboard)
                row(.importData)
            }

            Section("Cycles de révision") {
                ForEach(cycles) { cycle in
                    row(.cycle(cycle))
                }
            }

            Section {
                row(.settings)
            }
        }
        .navigationTitle("PLANB Audit")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }

    private func row(_ section: NavSection) -> some View {
        NavigationLink(value: section) {
            Label(section.title, systemImage: section.icon)
        }
    }
}

// MARK: - Detail Content

struct DetailContentView: View {
    let section: NavSection?

    var body: some View {
        Group {
            switch section {
            case .dashboard:
                DashboardView()
            case .importData:
                ImportView()
            case .cycle(let cycle):
                CycleBalanceView(cycle: cycle)
            case .settings:
                SettingsView()
            case .none:
                PlaceholderView(title: "PLANB Audit", message: "Sélectionne une section dans la sidebar")
            }
        }
    }
}

// MARK: - Vue Balance par cycle

struct CycleBalanceView: View {
    let cycle: RevisionCycle

    @Query(sort: \BalanceAccount.accountNumber) private var allAccounts: [BalanceAccount]

    private var accounts: [BalanceAccount] {
        allAccounts.filter { $0.cycle == cycle }
    }

    private var totalDebit: Double { accounts.reduce(0) { $0 + $1.debit } }
    private var totalCredit: Double { accounts.reduce(0) { $0 + $1.credit } }
    private var totalSoldeN: Double { accounts.reduce(0) { $0 + $1.balanceN } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // En-tete
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: cycle.icon)
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Cycle \(cycle.rawValue)")
                        .font(.largeTitle).fontWeight(.bold)
                    Spacer()
                }
                HStack(spacing: 16) {
                    statChip(label: "Comptes", value: "\(accounts.count)")
                    statChip(label: "Total débit", value: formatEuro(totalDebit))
                    statChip(label: "Total crédit", value: formatEuro(totalCredit))
                    statChip(label: "Solde N", value: formatEuro(totalSoldeN))
                }
            }
            .padding()

            Divider()

            if accounts.isEmpty {
                if allAccounts.isEmpty {
                    PlaceholderView(title: "Aucune balance importée",
                                    message: "Va dans Import et charge ta balance (CSV/TXT) — les comptes de ce cycle s'afficheront ici.")
                } else {
                    PlaceholderView(title: "Aucun compte dans ce cycle",
                                    message: "La balance importée ne contient pas de compte rattaché au cycle \(cycle.letter).")
                }
            } else {
                Table(accounts) {
                    TableColumn("Compte") { acc in
                        Text(acc.accountNumber).monospaced()
                    }
                    .width(90)
                    TableColumn("Intitulé") { acc in
                        Text(acc.accountLabel.isEmpty ? acc.accountCode : acc.accountLabel)
                    }
                    TableColumn("Débit") { acc in
                        Text(formatEuro(acc.debit)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(110)
                    TableColumn("Crédit") { acc in
                        Text(formatEuro(acc.credit)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(110)
                    TableColumn("Solde N") { acc in
                        Text(formatEuro(acc.balanceN)).monospacedDigit()
                            .foregroundStyle(acc.balanceN < 0 ? .red : .primary)
                    }
                    .width(110)
                    TableColumn("Solde N-1") { acc in
                        Text(formatEuro(acc.balanceNMinus1)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(110)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

/// Formatage monetaire francais (milliers espaces, 0 decimale).
func formatEuro(_ value: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    f.groupingSeparator = "\u{00A0}"
    return (f.string(from: NSNumber(value: value)) ?? "0") + " €"
}

// MARK: - Placeholder

struct PlaceholderView: View {
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Invoice.self, inMemory: true)
}
