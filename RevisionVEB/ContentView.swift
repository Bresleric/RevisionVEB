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
    case chartOfAccounts
    case cycle(RevisionCycle)
    case settings

    var id: String {
        switch self {
        case .dashboard:        return "dashboard"
        case .importData:       return "import"
        case .chartOfAccounts:  return "plan-comptable"
        case .cycle(let c):     return "cycle-\(c.rawValue)"
        case .settings:         return "settings"
        }
    }

    var title: String {
        switch self {
        case .dashboard:        return "Dashboard"
        case .importData:       return "Import"
        case .chartOfAccounts:  return "Plan comptable"
        case .cycle(let c):     return c.rawValue
        case .settings:         return "Réglages"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:        return "gauge.with.dots.needle.67percent"
        case .importData:       return "arrow.down.doc"
        case .chartOfAccounts:  return "list.bullet.rectangle"
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
                row(.chartOfAccounts)
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
            case .chartOfAccounts:
                ChartOfAccountsView()
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
    @Query private var rules: [AccountCycleRule]

    private var rulesDict: [String: RevisionCycle] {
        Dictionary(uniqueKeysWithValues: rules.map { ($0.accountNumber, $0.cycle) })
    }

    private var accounts: [BalanceAccount] {
        let dict = rulesDict
        return allAccounts.filter { $0.effectiveCycle(rules: dict) == cycle }
    }

    private var totalDebit: Double { accounts.reduce(0) { $0 + $1.debit } }
    private var totalCredit: Double { accounts.reduce(0) { $0 + $1.credit } }
    private var totalSoldeN: Double { accounts.reduce(0) { $0 + $1.balanceN } }
    private var totalVariation: Double { accounts.reduce(0) { $0 + ($1.balanceN - $1.balanceNMinus1) } }

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
                    statChip(label: "Var. N/N-1", value: formatEuroSigned(totalVariation),
                             color: totalVariation > 0 ? .green : (totalVariation < 0 ? .red : .secondary))
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
                    .width(105)
                    TableColumn("Crédit") { acc in
                        Text(formatEuro(acc.credit)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(105)
                    TableColumn("Solde N") { acc in
                        Text(formatEuro(acc.balanceN)).monospacedDigit()
                            .foregroundStyle(acc.balanceN < 0 ? .red : .primary)
                    }
                    .width(105)
                    TableColumn("Solde N-1") { acc in
                        Text(formatEuro(acc.balanceNMinus1)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(105)
                    TableColumn("Var. N/N-1") { acc in
                        let v = acc.balanceN - acc.balanceNMinus1
                        Text(formatEuroSigned(v)).monospacedDigit()
                            .foregroundStyle(v > 0 ? .green : (v < 0 ? .red : .secondary))
                    }
                    .width(110)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statChip(label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(color)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Plan comptable (table des comptes + correction du cycle)

struct ChartOfAccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BalanceAccount.accountNumber) private var allAccounts: [BalanceAccount]
    @Query private var rules: [AccountCycleRule]

    @State private var search = ""

    private var rulesDict: [String: RevisionCycle] {
        Dictionary(uniqueKeysWithValues: rules.map { ($0.accountNumber, $0.cycle) })
    }

    private var filtered: [BalanceAccount] {
        guard !search.isEmpty else { return allAccounts }
        let q = search.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        return allAccounts.filter {
            $0.accountNumber.lowercased().contains(q)
            || $0.accountLabel.folding(options: .diacriticInsensitive, locale: .current).lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title2).foregroundStyle(.blue)
                    Text("Plan comptable")
                        .font(.largeTitle).fontWeight(.bold)
                    Spacer()
                    Text("\(allAccounts.count) comptes")
                        .foregroundStyle(.secondary)
                }
                Text("Corrige ici le cycle d'un compte : ton choix est mémorisé et prioritaire sur le classement automatique, même après un nouvel import.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("Rechercher un compte ou un intitulé…", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
            }
            .padding()

            Divider()

            if allAccounts.isEmpty {
                PlaceholderView(title: "Aucune balance importée",
                                message: "Va dans Import et charge ta balance — les comptes apparaîtront ici.")
            } else {
                List {
                    // En-tete de colonnes
                    HStack {
                        Text("Compte").frame(width: 90, alignment: .leading)
                        Text("Intitulé").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Auto").frame(width: 60, alignment: .leading)
                        Text("Cycle").frame(width: 220, alignment: .leading)
                    }
                    .font(.caption).foregroundStyle(.secondary)

                    ForEach(filtered) { acc in
                        AccountRowView(
                            account: acc,
                            current: rulesDict[acc.accountNumber] ?? acc.cycle,
                            onChange: { newCycle in setCycle(acc.accountNumber, newCycle) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func setCycle(_ number: String, _ cycle: RevisionCycle) {
        let auto = RevisionCycle.forAccount(number)
        let existing = rules.first { $0.accountNumber == number }
        if cycle == auto {
            if let r = existing { modelContext.delete(r) }   // retour au classement auto
        } else if let r = existing {
            r.cycle = cycle
        } else {
            modelContext.insert(AccountCycleRule(accountNumber: number, cycle: cycle))
        }
        try? modelContext.save()
    }
}

private struct AccountRowView: View {
    let account: BalanceAccount
    let current: RevisionCycle
    let onChange: (RevisionCycle) -> Void

    private var isOverridden: Bool { current != account.cycle }

    var body: some View {
        HStack {
            Text(account.accountNumber).monospaced().frame(width: 90, alignment: .leading)
            Text(account.accountLabel.isEmpty ? account.accountCode : account.accountLabel)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(account.cycle.letter)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Picker("", selection: Binding(get: { current }, set: { onChange($0) })) {
                ForEach(RevisionCycle.allCases.filter { $0 != .nonClasse }) { c in
                    Text("\(c.letter) — \(c.shortName)").tag(c)
                }
            }
            .labelsHidden()
            .frame(width: 220)
            .tint(isOverridden ? .orange : .secondary)
        }
        .padding(.vertical, 2)
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

/// Comme formatEuro mais avec signe explicite (+/-) pour les variations.
func formatEuroSigned(_ value: Double) -> String {
    let rounded = (value).rounded()
    if rounded > 0 { return "+" + formatEuro(value) }
    if rounded < 0 { return "-" + formatEuro(abs(value)) }
    return formatEuro(0)
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
