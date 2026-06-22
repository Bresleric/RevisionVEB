//
//  ContentView.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import SwiftUI
import SwiftData

// MARK: - Racine : choix du dossier (societe) + exercice

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("currentExerciceID") private var currentExerciceID = ""

    @Query(sort: \Dossier.ordre) private var dossiers: [Dossier]
    @Query private var exercices: [Exercice]

    private var current: (dossier: Dossier, exercice: Exercice)? {
        guard let ex = exercices.first(where: { $0.id.uuidString == currentExerciceID }),
              let d = dossiers.first(where: { $0.id == ex.dossierID }) else { return nil }
        return (d, ex)
    }

    var body: some View {
        Group {
            if let cur = current {
                ContentView(dossier: cur.dossier, exercice: cur.exercice,
                            onSwitch: { currentExerciceID = "" })
            } else {
                DossierPickerView(onPick: { currentExerciceID = $0.id.uuidString })
            }
        }
        .onAppear(perform: seedIfNeeded)
    }

    private func seedIfNeeded() {
        guard dossiers.isEmpty else { return }
        modelContext.insert(Dossier(nom: "PLANB SARL", ordre: 0))
        modelContext.insert(Dossier(nom: "Moulin Neuf SARL", ordre: 1))
        try? modelContext.save()
    }
}

struct ContentView: View {
    let dossier: Dossier
    let exercice: Exercice
    var onSwitch: () -> Void

    @State private var selectedSection: NavSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedSection: $selectedSection,
                        dossier: dossier, exercice: exercice, onSwitch: onSwitch)
        } detail: {
            DetailContentView(section: selectedSection,
                              exerciceID: exercice.id, dossierID: dossier.id)
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
    let dossier: Dossier
    let exercice: Exercice
    var onSwitch: () -> Void

    private let cycles = RevisionCycle.allCases.filter { $0 != .nonClasse }

    var body: some View {
        List(selection: $selectedSection) {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dossier.nom).font(.headline)
                    Text("Exercice \(exercice.libelle)")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(action: onSwitch) {
                        Label("Changer de dossier", systemImage: "arrow.left.arrow.right")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }

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
    let exerciceID: UUID
    let dossierID: UUID

    var body: some View {
        Group {
            switch section {
            case .dashboard:
                DashboardView()
            case .importData:
                ImportView(exerciceID: exerciceID)
            case .chartOfAccounts:
                ChartOfAccountsView(exerciceID: exerciceID, dossierID: dossierID)
            case .cycle(let cycle):
                CycleBalanceView(cycle: cycle, exerciceID: exerciceID, dossierID: dossierID)
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
    let exerciceID: UUID
    let dossierID: UUID

    @State private var tab = 0   // 0 = Comptes, 1 = Contrôles

    @Query(sort: \BalanceAccount.accountNumber) private var allAccounts: [BalanceAccount]
    @Query private var rules: [AccountCycleRule]

    private var rulesDict: [String: RevisionCycle] {
        Dictionary(rules.filter { $0.dossierID == dossierID }.map { ($0.accountNumber, $0.cycle) },
                   uniquingKeysWith: { _, last in last })
    }

    private var exerciceAccounts: [BalanceAccount] {
        allAccounts.filter { $0.exerciceID == exerciceID }
    }

    private var accounts: [BalanceAccount] {
        let dict = rulesDict
        return exerciceAccounts.filter { $0.effectiveCycle(rules: dict) == cycle }
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
                Picker("", selection: $tab) {
                    Text("Comptes (\(accounts.count))").tag(0)
                    Text("Contrôles").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .padding(.top, 4)
            }
            .padding()

            Divider()

            if tab == 1 {
                CycleControlsView(cycle: cycle, exerciceID: exerciceID)
            } else if accounts.isEmpty {
                if exerciceAccounts.isEmpty {
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

// MARK: - Controles de revision (feuille de travail par cycle)

struct CycleControlsView: View {
    let cycle: RevisionCycle
    let exerciceID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var states: [ControlState]

    private let syntheseID = "__synthese__"

    private var statesDict: [String: ControlState] {
        Dictionary(
            states.filter { $0.exerciceID == exerciceID && $0.cycleRaw == cycle.rawValue }
                  .map { ($0.itemID, $0) },
            uniquingKeysWith: { _, last in last }
        )
    }

    private var groups: [ControlGroup] { RevisionControls.groups(for: cycle) }

    private var allItems: [ControlItem] { groups.flatMap { $0.items } }
    private var doneCount: Int {
        allItems.filter { (statesDict[$0.id]?.statut ?? .aFaire) != .aFaire }.count
    }
    private var anomalies: Int {
        allItems.filter { statesDict[$0.id]?.statut == .anomalie }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Avancement
                HStack(spacing: 16) {
                    Label("\(doneCount)/\(allItems.count) traités", systemImage: "checklist")
                    if anomalies > 0 {
                        Label("\(anomalies) anomalie\(anomalies > 1 ? "s" : "")", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }
                .font(.subheadline)

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.titre).font(.headline)
                        ForEach(group.items) { item in
                            ControlRowView(
                                item: item,
                                state: statesDict[item.id],
                                onStatut: { setStatut(item.id, $0) },
                                onNote: { setNote(item.id, $0) }
                            )
                        }
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.06))
                    .cornerRadius(10)
                }

                // Note de synthese du cycle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note de synthèse du cycle").font(.headline)
                    SyntheseEditor(
                        text: statesDict[syntheseID]?.note ?? "",
                        onChange: { setNote(syntheseID, $0) }
                    )
                }
            }
            .padding()
        }
    }

    private func state(for itemID: String) -> ControlState {
        if let s = statesDict[itemID] { return s }
        let s = ControlState(exerciceID: exerciceID, cycleRaw: cycle.rawValue, itemID: itemID)
        modelContext.insert(s)
        return s
    }

    private func setStatut(_ itemID: String, _ statut: ControlStatus) {
        let s = state(for: itemID)
        s.statut = statut
        s.updatedAt = Date()
        try? modelContext.save()
    }

    private func setNote(_ itemID: String, _ note: String) {
        let s = state(for: itemID)
        s.note = note
        s.updatedAt = Date()
        try? modelContext.save()
    }
}

private struct ControlRowView: View {
    let item: ControlItem
    let state: ControlState?
    let onStatut: (ControlStatus) -> Void
    let onNote: (String) -> Void

    @State private var note: String = ""

    private var statut: ControlStatus { state?.statut ?? .aFaire }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Menu {
                ForEach(ControlStatus.allCases, id: \.self) { s in
                    Button { onStatut(s) } label: { Label(s.rawValue, systemImage: s.icon) }
                }
            } label: {
                Image(systemName: statut.icon).foregroundStyle(statut.color)
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.libelle)
                TextField("Observation…", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onChange(of: note) { _, nv in onNote(nv) }
            }
        }
        .padding(.vertical, 2)
        .onAppear { if note.isEmpty { note = state?.note ?? "" } }
    }
}

/// Editeur multiligne pour la note de synthese (persistance a la frappe).
private struct SyntheseEditor: View {
    let text: String
    let onChange: (String) -> Void
    @State private var local: String = ""

    var body: some View {
        TextEditor(text: $local)
            .frame(minHeight: 120)
            .padding(6)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
            .onChange(of: local) { _, nv in onChange(nv) }
            .onAppear { if local.isEmpty { local = text } }
    }
}

// MARK: - Plan comptable (table des comptes + correction du cycle)

struct ChartOfAccountsView: View {
    let exerciceID: UUID
    let dossierID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BalanceAccount.accountNumber) private var allAccountsRaw: [BalanceAccount]
    @Query private var rules: [AccountCycleRule]

    @State private var search = ""

    private var allAccounts: [BalanceAccount] {
        allAccountsRaw.filter { $0.exerciceID == exerciceID }
    }

    private var rulesDict: [String: RevisionCycle] {
        Dictionary(rules.filter { $0.dossierID == dossierID }.map { ($0.accountNumber, $0.cycle) },
                   uniquingKeysWith: { _, last in last })
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
        let existing = rules.first { $0.dossierID == dossierID && $0.accountNumber == number }
        if cycle == auto {
            if let r = existing { modelContext.delete(r) }   // retour au classement auto
        } else if let r = existing {
            r.cycle = cycle
        } else {
            modelContext.insert(AccountCycleRule(dossierID: dossierID, accountNumber: number, cycle: cycle))
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

// MARK: - Selection du dossier (societe) + exercice

struct DossierPickerView: View {
    var onPick: (Exercice) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dossier.ordre) private var dossiers: [Dossier]
    @Query(sort: \Exercice.libelle, order: .reverse) private var exercices: [Exercice]

    @State private var newExerciceDossier: Dossier?
    @State private var showNewDossier = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(dossiers) { dossier in
                    Section(dossier.nom) {
                        let exs = exercices.filter { $0.dossierID == dossier.id }
                        if exs.isEmpty {
                            Text("Aucun exercice — créez-en un")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(exs) { ex in
                            Button { onPick(ex) } label: {
                                HStack {
                                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Exercice \(ex.libelle)").fontWeight(.medium)
                                        Text("Clôture \(ex.dateCloture.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Button { newExerciceDossier = dossier } label: {
                            Label("Nouvel exercice", systemImage: "plus.circle")
                        }
                        .font(.callout)
                    }
                }
            }
            .navigationTitle("Dossier de révision")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewDossier = true } label: {
                        Label("Nouvelle société", systemImage: "building.2.crop.circle.badge.plus")
                    }
                }
            }
            .sheet(item: $newExerciceDossier) { dossier in
                NewExerciceSheet(dossier: dossier)
            }
            .sheet(isPresented: $showNewDossier) {
                NewDossierSheet(nextOrdre: dossiers.count)
            }
        }
        .frame(minWidth: 540, minHeight: 460)
    }
}

struct NewExerciceSheet: View {
    let dossier: Dossier
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var libelle = ""
    @State private var dateCloture = Date()

    private var isValid: Bool { !libelle.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nouvel exercice").font(.headline)
            Text(dossier.nom).font(.subheadline).foregroundStyle(.secondary)
            TextField("Libellé (ex : 2025)", text: $libelle).textFieldStyle(.roundedBorder)
            DatePicker("Date de clôture", selection: $dateCloture, displayedComponents: .date)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Créer") {
                    modelContext.insert(Exercice(dossierID: dossier.id,
                                                 libelle: libelle.trimmingCharacters(in: .whitespaces),
                                                 dateCloture: dateCloture))
                    try? modelContext.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

struct NewDossierSheet: View {
    let nextOrdre: Int
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var nom = ""
    private var isValid: Bool { !nom.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nouvelle société").font(.headline)
            TextField("Nom (ex : Moulin Neuf SARL)", text: $nom).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Créer") {
                    modelContext.insert(Dossier(nom: nom.trimmingCharacters(in: .whitespaces), ordre: nextOrdre))
                    try? modelContext.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Dossier.self, Exercice.self, BalanceAccount.self,
                              ImportLog.self, AccountCycleRule.self, Invoice.self, AuditResult.self],
                        inMemory: true)
}
