//
//  ContentView.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import PDFKit

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

    @Environment(\.modelContext) private var modelContext
    @State private var isExporting = false

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
                Button {
                    isExporting = true
                    DispatchQueue.main.async {
                        DossierExport.export(dossier: dossier, exercice: exercice, context: modelContext)
                        isExporting = false
                    }
                } label: {
                    Label(isExporting ? "Export en cours…" : "Exporter pour l'expert-comptable",
                          systemImage: "square.and.arrow.up.on.square")
                }
                .disabled(isExporting)

                Button {
                    DispatchQueue.main.async { DataBackup.exportFullBackup() }
                } label: {
                    Label("Sauvegarder les données…", systemImage: "externaldrive.badge.timemachine")
                }
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

// MARK: - Sauvegarde des donnees (filet de securite)

enum DataBackup {
    private static func appSupport() -> URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
    }
    private static let storeName = "default.store"

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    /// Copie base + pieces vers un dossier destination.
    private static func copyData(to dir: URL) {
        let fm = FileManager.default
        guard let appSup = appSupport() else { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let src = appSup.appendingPathComponent(storeName + suffix)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: dir.appendingPathComponent(storeName + suffix))
            }
        }
        let pieces = appSup.appendingPathComponent("Pieces")
        if fm.fileExists(atPath: pieces.path) {
            try? fm.copyItem(at: pieces, to: dir.appendingPathComponent("Pieces"))
        }
    }

    /// Instantane automatique au lancement (avant toute migration). Garde les `keep` derniers.
    /// Throttle : pas plus d'un instantane par 20 min.
    static func autoBackup(keep: Int = 7) {
        let fm = FileManager.default
        guard let appSup = appSupport() else { return }
        let store = appSup.appendingPathComponent(storeName)
        guard fm.fileExists(atPath: store.path) else { return }   // 1er lancement : rien a sauvegarder

        let backups = appSup.appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: backups, withIntermediateDirectories: true)

        let dirs = (try? fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: [.creationDateKey]))?
            .filter { $0.lastPathComponent.hasPrefix("auto-") } ?? []
        func created(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }

        if let newest = dirs.map(created).max(), Date().timeIntervalSince(newest) < 20 * 60 {
            return  // un instantane recent existe deja
        }

        copyData(to: backups.appendingPathComponent("auto-\(stamp())", isDirectory: true))

        // Purge : garde les `keep` plus recents
        let all = ((try? fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("auto-") }
            .sorted { created($0) > created($1) }
        for old in all.dropFirst(keep) { try? fm.removeItem(at: old) }
    }

    /// Sauvegarde complete vers un emplacement choisi (ZIP).
    @MainActor
    static func exportFullBackup() {
        let fm = FileManager.default
        let name = "RevisionVEB - Sauvegarde \(stamp())"
        let root = fm.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try? fm.removeItem(at: root)
        copyData(to: root)

        var zipURL: URL?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: root, options: [.forUploading], error: &err) { tmp in
            let z = fm.temporaryDirectory.appendingPathComponent("\(name).zip")
            try? fm.removeItem(at: z)
            try? fm.copyItem(at: tmp, to: z)
            zipURL = z
        }
        guard let zip = zipURL else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).zip"
        panel.allowedContentTypes = [.zip]
        panel.title = "Sauvegarder les données RevisionVEB"
        if panel.runModal() == .OK, let dest = panel.url {
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: zip, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        }
    }
}

// MARK: - Export du dossier (ZIP pour l'expert-comptable)

enum DossierExport {
    @MainActor
    static func export(dossier: Dossier, exercice: Exercice, context: ModelContext) {
        let fm = FileManager.default
        let safeName = "\(dossier.nom) - Exercice \(exercice.libelle)"
            .replacingOccurrences(of: "/", with: "-")
        let root = fm.temporaryDirectory.appendingPathComponent(safeName, isDirectory: true)
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)

        // Donnees de l'exercice
        let accounts = ((try? context.fetch(FetchDescriptor<BalanceAccount>())) ?? [])
            .filter { $0.exerciceID == exercice.id }
            .sorted { $0.accountNumber < $1.accountNumber }
        let justifs = ((try? context.fetch(FetchDescriptor<AccountJustification>())) ?? [])
            .filter { $0.exerciceID == exercice.id }
        let rules = ((try? context.fetch(FetchDescriptor<AccountCycleRule>())) ?? [])
            .filter { $0.dossierID == dossier.id }
        let states = ((try? context.fetch(FetchDescriptor<ControlState>())) ?? [])
            .filter { $0.exerciceID == exercice.id }
        let recons = ((try? context.fetch(FetchDescriptor<BankReconciliation>())) ?? [])
            .filter { $0.exerciceID == exercice.id }
        let reconItems = ((try? context.fetch(FetchDescriptor<ReconItem>())) ?? [])
            .filter { $0.exerciceID == exercice.id }

        let jDict = Dictionary(justifs.map { ($0.accountNumber, $0) }, uniquingKeysWith: { _, l in l })
        let rDict = Dictionary(rules.map { ($0.accountNumber, $0.cycle) }, uniquingKeysWith: { _, l in l })

        func num(_ d: Double?) -> String { d.map { String(format: "%.0f", $0) } ?? "" }

        // Recap.csv
        var csv = "Cycle;Compte;Intitulé;Solde N;Solde justifié;Écart;Document\n"
        for a in accounts {
            let cyc = a.effectiveCycle(rules: rDict)
            let sj = jDict[a.accountNumber]?.soldeJustifie
            let ecart = sj.map { a.balanceN - $0 }
            let label = (a.accountLabel.isEmpty ? a.accountCode : a.accountLabel)
                .replacingOccurrences(of: ";", with: ",")
            let doc = jDict[a.accountNumber]?.docName ?? ""
            csv += "\(cyc.letter);\(a.accountNumber);\(label);\(num(a.balanceN));\(num(sj));\(num(ecart));\(doc)\n"
        }
        try? csv.data(using: .utf8)?.write(to: root.appendingPathComponent("Recap.csv"))

        // Controles.txt
        var ctrl = "Contrôles de révision\n\(dossier.nom) — Exercice \(exercice.libelle)\n\n"
        for cycle in RevisionCycle.allCases where cycle != .nonClasse {
            let cstates = Dictionary(states.filter { $0.cycleRaw == cycle.rawValue }.map { ($0.itemID, $0) },
                                     uniquingKeysWith: { _, l in l })
            ctrl += "=== Cycle \(cycle.rawValue) ===\n"
            for g in RevisionControls.groups(for: cycle) {
                ctrl += "  [\(g.titre)]\n"
                for it in g.items {
                    let st = cstates[it.id]?.statut ?? .aFaire
                    let note = cstates[it.id]?.note ?? ""
                    ctrl += "   - \(it.libelle) : \(st.rawValue)" + (note.isEmpty ? "" : " — \(note)") + "\n"
                }
            }
            if let syn = cstates["__synthese__"]?.note, !syn.isEmpty {
                ctrl += "  Synthèse: \(syn)\n"
            }
            ctrl += "\n"
        }
        try? ctrl.data(using: .utf8)?.write(to: root.appendingPathComponent("Controles.txt"))

        // Justificatifs (classes par cycle)
        let pieces = root.appendingPathComponent("Justificatifs", isDirectory: true)
        try? fm.createDirectory(at: pieces, withIntermediateDirectories: true)
        for j in justifs where !j.docPath.isEmpty {
            let src = URL(fileURLWithPath: j.docPath)
            let cyc = (rDict[j.accountNumber] ?? RevisionCycle.forAccount(j.accountNumber)).letter
            let dest = pieces.appendingPathComponent("\(cyc) - \(src.lastPathComponent)")
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: src, to: dest)
        }
        // Pieces des elements de rapprochement
        for it in reconItems where !it.docPath.isEmpty {
            let src = URL(fileURLWithPath: it.docPath)
            let dest = pieces.appendingPathComponent("B (rappro) - \(src.lastPathComponent)")
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: src, to: dest)
        }

        // Rapprochements.txt
        if !recons.isEmpty {
            var rap = "Rapprochements bancaires\n\(dossier.nom) — Exercice \(exercice.libelle)\n\n"
            let accByNum = Dictionary(accounts.map { ($0.accountNumber, $0) }, uniquingKeysWith: { _, l in l })
            for rec in recons.sorted(by: { $0.accountNumber < $1.accountNumber }) {
                let a = accByNum[rec.accountNumber]
                let comptable = a?.balanceN ?? 0
                let items = reconItems.filter { $0.accountNumber == rec.accountNumber }.sorted { $0.ordre < $1.ordre }
                let totalItems = items.reduce(0) { $0 + $1.montant }
                let residuel = (rec.soldeExtrait ?? comptable) + totalItems - comptable
                rap += "Compte \(rec.accountNumber) \(a?.accountLabel ?? "")\n"
                rap += "  Solde comptable : \(num(comptable))\n"
                rap += "  Solde extrait   : \(num(rec.soldeExtrait))\n"
                for it in items {
                    rap += "   - \(it.libelle) : \(num(it.montant))" + (it.docName.isEmpty ? "" : " [\(it.docName)]") + "\n"
                }
                rap += "  Écart résiduel  : \(num(residuel))" + (abs(residuel) < 0.5 ? " (rapproché)" : "") + "\n\n"
            }
            try? rap.data(using: .utf8)?.write(to: root.appendingPathComponent("Rapprochements.txt"))
        }

        // Zip (NSFileCoordinator .forUploading)
        var zipURL: URL?
        var coordErr: NSError?
        NSFileCoordinator().coordinate(readingItemAt: root, options: [.forUploading], error: &coordErr) { tmp in
            let z = fm.temporaryDirectory.appendingPathComponent("\(safeName).zip")
            try? fm.removeItem(at: z)
            try? fm.copyItem(at: tmp, to: z)
            zipURL = z
        }
        guard let zip = zipURL else { return }

        // Enregistrement choisi par l'utilisateur
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeName).zip"
        panel.allowedContentTypes = [.zip]
        panel.title = "Exporter le dossier de révision"
        if panel.runModal() == .OK, let dest = panel.url {
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: zip, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
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

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BalanceAccount.accountNumber) private var allAccounts: [BalanceAccount]
    @Query private var rules: [AccountCycleRule]
    @Query private var justifications: [AccountJustification]
    @Query private var recons: [BankReconciliation]
    @Query private var reconItems: [ReconItem]

    @State private var pendingAccount: String?
    @State private var showDocImporter = false

    private var rulesDict: [String: RevisionCycle] {
        Dictionary(rules.filter { $0.dossierID == dossierID }.map { ($0.accountNumber, $0.cycle) },
                   uniquingKeysWith: { _, last in last })
    }

    private var justifDict: [String: AccountJustification] {
        Dictionary(justifications.filter { $0.exerciceID == exerciceID }.map { ($0.accountNumber, $0) },
                   uniquingKeysWith: { _, last in last })
    }

    private var reconDict: [String: BankReconciliation] {
        Dictionary(recons.filter { $0.exerciceID == exerciceID }.map { ($0.accountNumber, $0) },
                   uniquingKeysWith: { _, last in last })
    }

    private func reconItemsTotal(_ acct: String) -> Double {
        reconItems.filter { $0.exerciceID == exerciceID && $0.accountNumber == acct }
            .reduce(0) { $0 + $1.montant }
    }

    /// Vrai si un rapprochement bancaire avec solde extrait existe pour ce compte.
    private func isReconciled(_ a: BalanceAccount) -> Bool {
        reconDict[a.accountNumber]?.soldeExtrait != nil
    }

    /// Solde justifie effectif : issu du rapprochement bancaire si present, sinon la saisie manuelle.
    private func justifiedValue(_ a: BalanceAccount) -> Double? {
        if let rec = reconDict[a.accountNumber], let ext = rec.soldeExtrait {
            return ext + reconItemsTotal(a.accountNumber)
        }
        return justifDict[a.accountNumber]?.soldeJustifie
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
                    if cycle == .tresorerie { Text("Rapprochements").tag(1) }
                    if cycle == .fiscal { Text("TVA").tag(3) }
                    Text("Contrôles").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: (cycle == .tresorerie || cycle == .fiscal) ? 380 : 280)
                .padding(.top, 4)
            }
            .padding()

            Divider()

            if tab == 2 {
                CycleControlsView(cycle: cycle, exerciceID: exerciceID)
            } else if tab == 1 && cycle == .tresorerie {
                CycleReconciliationView(exerciceID: exerciceID,
                                        bankAccounts: accounts.filter { $0.accountNumber.hasPrefix("51") })
            } else if tab == 3 && cycle == .fiscal {
                TvaControlView(exerciceID: exerciceID)
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
                    TableColumn("Solde justifié") { acc in
                        if isReconciled(acc) {
                            HStack(spacing: 4) {
                                Image(systemName: "building.columns").font(.caption2).foregroundStyle(.blue)
                                Text(formatEuro(justifiedValue(acc) ?? 0)).monospacedDigit()
                            }
                            .help("Issu du rapprochement bancaire")
                        } else {
                            JustifSoldeCell(value: justifDict[acc.accountNumber]?.soldeJustifie,
                                            onCommit: { setSolde(acc.accountNumber, $0) })
                        }
                    }
                    .width(130)
                    TableColumn("Écart") { acc in
                        if let jv = justifiedValue(acc) {
                            let ecart = acc.balanceN - jv
                            Text(formatEuroSigned(ecart)).monospacedDigit()
                                .foregroundStyle(abs(ecart) < 0.5 ? .green : .red)
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                    .width(105)
                    TableColumn("Réf.") { acc in
                        RefCell(justif: justifDict[acc.accountNumber],
                                onOpen: { openDoc(acc.accountNumber) },
                                onLink: { pendingAccount = acc.accountNumber; showDocImporter = true },
                                onRemove: { removeDoc(acc.accountNumber) })
                    }
                    .width(150)
                }
                .fileImporter(isPresented: $showDocImporter,
                              allowedContentTypes: [.item],
                              allowsMultipleSelection: false) { result in
                    if case .success(let urls) = result, let url = urls.first, let acc = pendingAccount {
                        attachDoc(acc, url)
                    }
                    pendingAccount = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Justification (cross-ref)

    private func justif(for accountNumber: String) -> AccountJustification {
        if let j = justifDict[accountNumber] { return j }
        let j = AccountJustification(exerciceID: exerciceID, accountNumber: accountNumber)
        modelContext.insert(j)
        return j
    }

    private func setSolde(_ accountNumber: String, _ value: Double?) {
        let j = justif(for: accountNumber)
        j.soldeJustifie = value
        j.updatedAt = Date()
        try? modelContext.save()
    }

    private func attachDoc(_ accountNumber: String, _ url: URL) {
        guard let copied = JustificatifStore.copyIn(source: url, exerciceID: exerciceID, accountNumber: accountNumber) else { return }
        let j = justif(for: accountNumber)
        j.docPath = copied.path
        j.docName = copied.name
        j.docBookmark = nil
        j.updatedAt = Date()
        try? modelContext.save()
    }

    private func removeDoc(_ accountNumber: String) {
        guard let j = justifDict[accountNumber] else { return }
        if !j.docPath.isEmpty { try? FileManager.default.removeItem(atPath: j.docPath) }
        j.docPath = ""; j.docName = ""; j.docBookmark = nil; j.updatedAt = Date()
        try? modelContext.save()
    }

    private func openDoc(_ accountNumber: String) {
        guard let j = justifDict[accountNumber] else { return }
        openJustificationDocument(path: j.docPath, bookmark: j.docBookmark)
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

// MARK: - Cellules cross-ref (solde justifie + reference document)

private struct JustifSoldeCell: View {
    let value: Double?
    let onCommit: (Double?) -> Void
    @State private var text: String = ""

    var body: some View {
        TextField("—", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .onSubmit(commit)
            .onAppear { text = Self.format(value) }
    }

    private func commit() {
        let cleaned = text
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { onCommit(nil) }
        else if let d = Double(cleaned) { onCommit(d) }
    }

    private static func format(_ v: Double?) -> String {
        guard let v else { return "" }
        return String(format: "%.0f", v)
    }
}

private struct RefCell: View {
    let hasDocument: Bool
    let docName: String
    let onOpen: () -> Void
    let onLink: () -> Void
    let onRemove: () -> Void

    init(hasDocument: Bool, docName: String,
         onOpen: @escaping () -> Void, onLink: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.hasDocument = hasDocument
        self.docName = docName
        self.onOpen = onOpen; self.onLink = onLink; self.onRemove = onRemove
    }

    init(justif: AccountJustification?,
         onOpen: @escaping () -> Void, onLink: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.init(hasDocument: justif?.hasDocument ?? false, docName: justif?.docName ?? "",
                  onOpen: onOpen, onLink: onLink, onRemove: onRemove)
    }

    init(reconItem: ReconItem,
         onOpen: @escaping () -> Void, onLink: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.init(hasDocument: reconItem.hasDocument, docName: reconItem.docName,
                  onOpen: onOpen, onLink: onLink, onRemove: onRemove)
    }

    var body: some View {
        if hasDocument {
            HStack(spacing: 4) {
                Button(action: onOpen) {
                    Label(docName.isEmpty ? "Ouvrir" : docName, systemImage: "doc.text.magnifyingglass")
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                Menu {
                    Button("Changer le document…", action: onLink)
                    Button("Retirer le lien", role: .destructive, action: onRemove)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } else {
            Button(action: onLink) {
                Label("Lier", systemImage: "paperclip")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}

/// Stockage local des pieces justificatives (dans le conteneur de l'app),
/// organise par exercice. L'app en est proprietaire -> ouverture fiable + export.
enum JustificatifStore {
    static func baseDir() -> URL {
        let fm = FileManager.default
        let appSup = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                  appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let dir = appSup.appendingPathComponent("Pieces", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func dir(forExercice id: UUID) -> URL {
        let d = baseDir().appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Copie la piece choisie dans le stockage de l'app. Retourne (chemin, nom d'origine).
    static func copyIn(source: URL, exerciceID: UUID, accountNumber: String) -> (path: String, name: String)? {
        let fm = FileManager.default
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let dest = dir(forExercice: exerciceID)
            .appendingPathComponent("\(accountNumber) - \(source.lastPathComponent)")
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: source, to: dest)
            return (dest.path, source.lastPathComponent)
        } catch {
            return nil
        }
    }
}

/// Ouvre la piece justificative : via bookmark securise si possible, sinon par le chemin.
func openJustificationDocument(path: String, bookmark: Data?) {
    if let data = bookmark {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                              relativeTo: nil, bookmarkDataIsStale: &stale) {
            if url.startAccessingSecurityScopedResource() {
                NSWorkspace.shared.open(url)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    url.stopAccessingSecurityScopedResource()
                }
                return
            }
        }
    }
    if !path.isEmpty {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
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

// MARK: - Rapprochements bancaires (cycle B)

struct CycleReconciliationView: View {
    let exerciceID: UUID
    let bankAccounts: [BalanceAccount]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if bankAccounts.isEmpty {
                    PlaceholderView(title: "Aucun compte bancaire",
                                    message: "Les comptes 51x de cet exercice apparaîtront ici pour le rapprochement.")
                } else {
                    ForEach(bankAccounts) { acc in
                        ReconciliationCard(account: acc, exerciceID: exerciceID)
                    }
                }
            }
            .padding()
        }
    }
}

private struct ReconciliationCard: View {
    let account: BalanceAccount
    let exerciceID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var allRecons: [BankReconciliation]
    @Query private var allItems: [ReconItem]

    @State private var soldeExtraitText = ""
    @State private var pendingItem: ReconItem?
    @State private var showItemImporter = false

    private var recon: BankReconciliation? {
        allRecons.first { $0.exerciceID == exerciceID && $0.accountNumber == account.accountNumber }
    }
    private var items: [ReconItem] {
        allItems.filter { $0.exerciceID == exerciceID && $0.accountNumber == account.accountNumber }
            .sorted { $0.ordre < $1.ordre }
    }

    private var soldeComptable: Double { account.balanceN }
    private var soldeExtrait: Double? { recon?.soldeExtrait }
    private var totalItems: Double { items.reduce(0) { $0 + $1.montant } }
    private var ecartBrut: Double? { soldeExtrait.map { soldeComptable - $0 } }
    private var residuel: Double? { ecartBrut.map { $0 - totalItems } }
    private var rapproche: Bool { (residuel.map { abs($0) < 0.5 }) ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // En-tete compte
            HStack {
                Text(account.accountNumber).monospaced()
                Text(account.accountLabel.isEmpty ? account.accountCode : account.accountLabel)
                    .fontWeight(.semibold)
                Spacer()
                if soldeExtrait != nil {
                    Label(rapproche ? "Rapproché" : "Écart résiduel",
                          systemImage: rapproche ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(rapproche ? .green : .orange)
                }
            }

            // Soldes
            HStack(spacing: 24) {
                labeled("Solde comptable", formatEuro(soldeComptable))
                HStack(spacing: 6) {
                    Text("Solde extrait").font(.caption).foregroundStyle(.secondary)
                    TextField("—", text: $soldeExtraitText)
                        .textFieldStyle(.roundedBorder).frame(width: 120)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .onSubmit(commitExtrait)
                }
                if let e = ecartBrut {
                    labeled("Écart à expliquer", formatEuroSigned(e))
                }
            }

            Divider()

            // Elements de rapprochement
            Text("Éléments de rapprochement").font(.subheadline).fontWeight(.medium)
            ForEach(items) { item in
                ReconItemRow(item: item,
                             onCommit: { try? modelContext.save() },
                             onDelete: { removeItemDoc(item); modelContext.delete(item); try? modelContext.save() },
                             onLink: { pendingItem = item; showItemImporter = true },
                             onOpen: { openJustificationDocument(path: item.docPath, bookmark: item.docBookmark) },
                             onRemoveDoc: { removeItemDoc(item); try? modelContext.save() })
            }
            Button {
                modelContext.insert(ReconItem(exerciceID: exerciceID, accountNumber: account.accountNumber,
                                              ordre: items.count))
                try? modelContext.save()
            } label: { Label("Ajouter un élément", systemImage: "plus.circle") }
                .buttonStyle(.borderless).font(.callout)

            Divider()

            // Synthese
            HStack(spacing: 24) {
                labeled("Total éléments", formatEuroSigned(totalItems))
                if let r = residuel {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Écart résiduel").font(.caption).foregroundStyle(.secondary)
                        Text(formatEuroSigned(r)).font(.headline).monospacedDigit()
                            .foregroundStyle(abs(r) < 0.5 ? .green : .red)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(10)
        .onAppear {
            soldeExtraitText = recon?.soldeExtrait.map { String(format: "%.0f", $0) } ?? ""
        }
        .fileImporter(isPresented: $showItemImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first, let item = pendingItem {
                attachItemDoc(item, url)
            }
            pendingItem = nil
        }
    }

    private func attachItemDoc(_ item: ReconItem, _ url: URL) {
        let label = "\(account.accountNumber) rappro"
        guard let copied = JustificatifStore.copyIn(source: url, exerciceID: exerciceID, accountNumber: label) else { return }
        item.docPath = copied.path
        item.docName = copied.name
        item.docBookmark = nil
        try? modelContext.save()
    }

    private func removeItemDoc(_ item: ReconItem) {
        if !item.docPath.isEmpty { try? FileManager.default.removeItem(atPath: item.docPath) }
        item.docPath = ""; item.docName = ""; item.docBookmark = nil
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private func commitExtrait() {
        let cleaned = soldeExtraitText
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        let r = recon ?? {
            let new = BankReconciliation(exerciceID: exerciceID, accountNumber: account.accountNumber)
            modelContext.insert(new)
            return new
        }()
        r.soldeExtrait = cleaned.isEmpty ? nil : Double(cleaned)
        r.updatedAt = Date()
        try? modelContext.save()
    }
}

private struct ReconItemRow: View {
    @Bindable var item: ReconItem
    var onCommit: () -> Void
    var onDelete: () -> Void
    var onLink: () -> Void
    var onOpen: () -> Void
    var onRemoveDoc: () -> Void
    @State private var montantText = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("Libellé (ex : chèque non débité, virement en cours…)", text: $item.libelle)
                .textFieldStyle(.roundedBorder)
                .onChange(of: item.libelle) { _, _ in onCommit() }
            TextField("± montant", text: $montantText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110).multilineTextAlignment(.trailing).monospacedDigit()
                .onSubmit(commit)
            RefCell(reconItem: item, onOpen: onOpen, onLink: onLink, onRemove: onRemoveDoc)
                .frame(width: 150, alignment: .leading)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .onAppear { montantText = item.montant == 0 ? "" : String(format: "%.0f", item.montant) }
    }

    private func commit() {
        let c = montantText
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        item.montant = Double(c) ?? 0
        onCommit()
    }
}

// MARK: - Extraction CA3 (PDF 3310-CA3 -> lignes de déclaration)

enum CA3Import {
    struct Line { let taux: String; let base: Double; let taxe: Double }
    struct Result { let periode: String; let lines: [Line]; let deductible: Double; let creditM1: Double; let caHT: Double }

    private static let frMonths: [String: Int] = [
        "janvier": 1, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6,
        "juillet": 7, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "decembre": 12
    ]

    private static func matches(_ pattern: String, _ s: String, group: Int = 0) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.range(at: group).location != NSNotFound ? ns.substring(with: $0.range(at: group)) : nil
        }
    }

    private static func tauxStr(_ r: Double) -> String {
        r == r.rounded() ? String(Int(r)) : String(r)
    }

    /// Parse un PDF 3310-CA3. Logique validée sur 11 déclarations PlanB 2025.
    static func parse(_ url: URL) -> Result? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url) else { return nil }
        var raw = ""
        for i in 0..<doc.pageCount { raw += (doc.page(at: i)?.string ?? "") + "\n" }

        // Période
        var periode = ""
        if let r = raw.range(of: "période :") {
            let after = String(raw[r.upperBound...]).prefix(40)
                .replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            let folded = after.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr")).lowercased()
            if let y = matches("(20[0-9]{2})", folded).first {
                for (name, num) in frMonths where folded.contains(name) {
                    periode = "\(y)-\(String(format: "%02d", num))"
                }
            }
        }

        // Zone utile (on retire entêtes/pieds + lignes de hash d'URL)
        func isHashLine(_ s: String) -> Bool {
            s.range(of: "[0-9a-f]{12,}", options: .regularExpression) != nil
        }
        var body = raw.components(separatedBy: .newlines)
            .filter { !$0.contains("impots.gouv.fr") && !$0.contains("://")
                && !$0.contains("Visualisation de la") && !isHashLine($0) }
            .joined(separator: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        if let r = body.range(of: "OPÉRATIONS TAXÉES") { body = String(body[r.lowerBound...]) }
        for stop in ["MENTION EXPRESSE", "CADRE RÉSERVÉ"] {
            if let r = body.range(of: stop) { body = String(body[..<r.lowerBound]) }
        }

        // Taux présents (ordre), AVANT de retirer les %
        let rates = matches("Taux\\s+\\S+\\s+(\\d+(?:[.,]\\d+)?)\\s*%", body, group: 1)
            .compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }

        for pat in ["\\([^)]*\\)", "\\d{2}/\\d{2}/\\d{4}", "\\d{1,2}:\\d{2}", "\\d+(?:[.,]\\d+)? ?%"] {
            body = body.replacingOccurrences(of: pat, with: " ", options: .regularExpression)
        }

        let nums = matches("\\d{1,3}(?: \\d{3})+|\\d+", body)
            .compactMap { Double($0.replacingOccurrences(of: " ", with: "")) }
            .filter { $0 >= 100 }

        guard !nums.isEmpty, !rates.isEmpty, !periode.isEmpty else { return nil }
        let a1 = nums[0]
        func taxe(_ base: Double, _ rate: Double) -> Double { (base * rate / 100).rounded() }

        var lines: [Line] = []
        if rates.count == 1 {
            lines = [Line(taux: tauxStr(rates[0]), base: a1, taxe: taxe(a1, rates[0]))]
        } else if rates.count == 2 {
            // base du 1er taux = 1er montant après A1 (fiable) ; le 2e se déduit de A1
            let b0 = nums.count > 1 ? nums[1] : 0
            let b1 = a1 - b0
            lines = [
                Line(taux: tauxStr(rates[0]), base: b0, taxe: taxe(b0, rates[0])),
                Line(taux: tauxStr(rates[1]), base: b1, taxe: taxe(b1, rates[1]))
            ]
        } else {
            for (i, r) in rates.enumerated() {
                let bi = 1 + 2 * i
                if bi < nums.count { lines.append(Line(taux: tauxStr(r), base: nums[bi], taxe: taxe(nums[bi], r))) }
            }
        }

        // TVA déductible : brute fiable -> on cherche d (total déductible) tel que |brute - d| réapparaisse plus loin (= net)
        let brute = lines.reduce(0.0) { $0 + $1.taxe }
        let hasReport = raw.contains("Report du crédit")
        var totalDed = 0.0, report = 0.0
        if let idxBrute = nums.firstIndex(where: { abs($0 - brute) < 1 }) {
            var idxD = -1
            for j in (idxBrute + 1)..<nums.count {
                if nums[(j + 1)...].contains(where: { abs($0 - abs(brute - nums[j])) < 1 }) {
                    totalDed = nums[j]; idxD = j; break
                }
            }
            if idxD > idxBrute {
                // sous-totaux déductibles entre la brute et le total ; on scinde un éventuel nombre collé
                var subs = Array(nums[(idxBrute + 1)..<idxD])
                if abs(subs.reduce(0, +) - totalDed) >= 1, let big = subs.firstIndex(where: { $0 > totalDed }) {
                    let others = subs.enumerated().filter { $0.offset != big }.map { $0.element }.reduce(0, +)
                    let target = totalDed - others
                    let s = String(Int(subs[big]))
                    for k in 1..<s.count {
                        if let a = Double(s.prefix(k)), let b = Double(s.dropFirst(k)), abs(a + b - target) < 1 {
                            subs.remove(at: big); subs.append(a); subs.append(b); break
                        }
                    }
                }
                // ligne 22 (report) = dernier sous-total si la déclaration mentionne un report
                report = hasReport ? (subs.last ?? 0) : 0
            }
        }
        return Result(periode: periode, lines: lines, deductible: totalDed - report, creditM1: report, caHT: a1)
    }
}

// MARK: - Contrôle TVA (Cycle I) : config taux + déclarations CA3 (I-1) + rapprochement (I-2)

struct TvaControlView: View {
    let exerciceID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BalanceAccount.accountNumber) private var allAccounts: [BalanceAccount]
    @Query private var tauxConfig: [TvaCompteTaux]
    @Query private var ca3: [Ca3Entry]
    @Query private var ca3Periods: [Ca3Period]

    @State private var sub = 0   // 0 = Taux, 1 = Déclarations (I-1), 2 = Rapprochement (I-2)
    @State private var showCA3Importer = false
    @State private var importMessage: String?

    private var ventes: [BalanceAccount] {
        allAccounts.filter { $0.exerciceID == exerciceID && $0.accountNumber.hasPrefix("70") }
    }
    private var tauxDict: [String: String] {
        Dictionary(tauxConfig.filter { $0.exerciceID == exerciceID }.map { ($0.compte, $0.taux) },
                   uniquingKeysWith: { _, l in l })
    }
    private var entries: [Ca3Entry] {
        ca3.filter { $0.exerciceID == exerciceID }
            .sorted { ($0.periode, $0.taux) < ($1.periode, $1.taux) }
    }
    private var deductDict: [String: Double] {
        Dictionary(ca3Periods.filter { $0.exerciceID == exerciceID }.map { ($0.periode, $0.tvaDeductible) },
                   uniquingKeysWith: { _, l in l })
    }
    private var creditM1Dict: [String: Double] {
        Dictionary(ca3Periods.filter { $0.exerciceID == exerciceID }.map { ($0.periode, $0.creditM1) },
                   uniquingKeysWith: { _, l in l })
    }
    private var caHTDict: [String: Double] {
        Dictionary(ca3Periods.filter { $0.exerciceID == exerciceID }.map { ($0.periode, $0.caHT) },
                   uniquingKeysWith: { _, l in l })
    }
    /// Synthèse par période : collectée (Σ taxe), déductible (CA3), à payer (= collectée − déductible).
    private var periodSummary: [(periode: String, collectee: Double, deductible: Double, net: Double)] {
        let periodes = Set(entries.map { $0.periode }).union(deductDict.keys).filter { !$0.isEmpty }
        return periodes.sorted().map { p in
            let coll = entries.filter { $0.periode == p }.reduce(0.0) { $0 + $1.tva }
            let ded = deductDict[p] ?? 0
            return (p, coll, ded, coll - ded)
        }
    }

    /// Taux effectif d'un compte : config manuelle si présente, sinon détecté du libellé.
    private func taux(for acc: BalanceAccount) -> String {
        if let t = tauxDict[acc.accountNumber], !t.isEmpty { return t }
        return TvaHelper.detectTaux(from: acc.accountLabel)
    }

    private func tauxLabel(_ t: String) -> String {
        if t.isEmpty || t == "—" { return "—" }
        if t == "Exo" { return "Exonéré" }
        return "\(t)%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $sub) {
                Text("Taux").tag(0)
                Text("Collectée").tag(3)
                Text("Déclarations").tag(1)
                Text("Cohérence").tag(4)
                Text("Rapprochement").tag(2)
            }
            .pickerStyle(.segmented).frame(width: 640).padding()

            Divider()

            if ventes.isEmpty {
                PlaceholderView(title: "Aucune vente importée",
                                message: "Importe la balance : les comptes 70x serviront de base au contrôle TVA.")
            } else {
                switch sub {
                case 0: configView
                case 1: declarationsView
                case 2: rapprochementView
                case 4: coherenceView
                default: collecteeView   // 3
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileImporter(isPresented: $showCA3Importer,
                      allowedContentTypes: [.pdf],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importCA3(urls) }
        }
    }

    private func importCA3(_ urls: [URL]) {
        var imported = 0, failed = 0
        for url in urls {
            guard let res = CA3Import.parse(url) else { failed += 1; continue }
            // Remplace les lignes existantes de cette période (évite les doublons)
            for e in ca3 where e.exerciceID == exerciceID && e.periode == res.periode {
                modelContext.delete(e)
            }
            for p in ca3Periods where p.exerciceID == exerciceID && p.periode == res.periode {
                modelContext.delete(p)
            }
            for (i, line) in res.lines.enumerated() {
                modelContext.insert(Ca3Entry(exerciceID: exerciceID, periode: res.periode,
                                             taux: line.taux, base: line.base, tva: line.taxe, ordre: i))
            }
            modelContext.insert(Ca3Period(exerciceID: exerciceID, periode: res.periode,
                                          tvaDeductible: res.deductible, creditM1: res.creditM1, caHT: res.caHT))
            imported += 1
        }
        try? modelContext.save()
        importMessage = "\(imported) CA3 importé\(imported > 1 ? "s" : "")"
            + (failed > 0 ? " · \(failed) échec\(failed > 1 ? "s" : "")" : "")
    }

    // MARK: Sous-vue Taux (config)

    private var configView: some View {
        List {
            HStack {
                Text("Compte").frame(width: 90, alignment: .leading)
                Text("Intitulé").frame(maxWidth: .infinity, alignment: .leading)
                Text("Base HT (compta)").frame(width: 130, alignment: .trailing)
                Text("Taux TVA").frame(width: 120, alignment: .leading)
            }
            .font(.caption).foregroundStyle(.secondary)

            ForEach(ventes) { acc in
                HStack {
                    Text(acc.accountNumber).monospaced().frame(width: 90, alignment: .leading)
                    Text(acc.accountLabel.isEmpty ? acc.accountCode : acc.accountLabel)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatEuro(-acc.balanceN)).monospacedDigit().frame(width: 130, alignment: .trailing)
                    Picker("", selection: Binding(get: { taux(for: acc) }, set: { setTaux(acc.accountNumber, $0) })) {
                        ForEach(TvaHelper.presets, id: \.self) { Text(tauxLabel($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: 120)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Sous-vue Collectée (cohérence CA × taux vs TVA comptabilisée — format Excel)

    private func caHT(forTaux t: String) -> Double {
        ventes.filter { taux(for: $0) == t }.reduce(0.0) { $0 + (-$1.balanceN) }
    }

    private var collecteeView: some View {
        let tvaAccounts = allAccounts
            .filter { $0.exerciceID == exerciceID && $0.accountNumber.hasPrefix("44571") }
            .sorted { $0.accountNumber < $1.accountNumber }
        let totalCA = ventes.reduce(0.0) { $0 + (-$1.balanceN) }

        return List {
            // Bloc Ventes (CA HT)
            Section("Ventes — CA HT (classe 70)") {
                HStack {
                    Text("Compte").frame(width: 90, alignment: .leading)
                    Text("Intitulé").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Taux").frame(width: 60, alignment: .leading)
                    Text("CA HT").frame(width: 130, alignment: .trailing)
                }
                .font(.caption).foregroundStyle(.secondary)

                ForEach(ventes) { acc in
                    HStack {
                        Text(acc.accountNumber).monospaced().frame(width: 90, alignment: .leading)
                        Text(acc.accountLabel.isEmpty ? acc.accountCode : acc.accountLabel)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(tauxLabel(taux(for: acc))).font(.caption).frame(width: 60, alignment: .leading)
                        Text(formatEuro(-acc.balanceN)).monospacedDigit().frame(width: 130, alignment: .trailing)
                    }
                }
                HStack {
                    Text("Total CA HT").fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatEuro(totalCA)).fontWeight(.semibold).monospacedDigit().frame(width: 130, alignment: .trailing)
                }
            }

            // Bloc TVA collectée (comptabilisée vs calculée)
            Section("TVA collectée (comptes 44571) — comptabilisée vs calculée") {
                HStack {
                    Text("Compte").frame(width: 90, alignment: .leading)
                    Text("Intitulé").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Taux").frame(width: 50, alignment: .leading)
                    Text("Comptabilisée").frame(width: 120, alignment: .trailing)
                    Text("Calculée").frame(width: 110, alignment: .trailing)
                    Text("Écart").frame(width: 110, alignment: .trailing)
                }
                .font(.caption).foregroundStyle(.secondary)

                ForEach(tvaAccounts) { acc in
                    let t = TvaHelper.detectTaux(from: acc.accountLabel)
                    let rate = TvaHelper.rate(t) ?? 0
                    let compta = -acc.balanceN
                    let calc = (caHT(forTaux: t) * rate / 100).rounded()
                    let ecart = compta - calc
                    let seuil = max(calc * 0.005, 2)
                    HStack {
                        Text(acc.accountNumber).monospaced().frame(width: 90, alignment: .leading)
                        Text(acc.accountLabel.isEmpty ? acc.accountCode : acc.accountLabel)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(tauxLabel(t)).font(.caption).frame(width: 50, alignment: .leading)
                        Text(formatEuro(compta)).monospacedDigit().frame(width: 120, alignment: .trailing)
                        Text(formatEuro(calc)).monospacedDigit().foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
                        Text(formatEuroSigned(ecart)).monospacedDigit().frame(width: 110, alignment: .trailing)
                            .foregroundStyle(abs(ecart) <= seuil ? .green : .red)
                    }
                }
            }
        }
    }

    // MARK: Sous-vue Déclarations (I-1)

    private var declTotals: [(taux: String, base: Double, tva: Double)] {
        Dictionary(grouping: entries, by: { $0.taux }).map { (k, v) in
            (k, v.reduce(0) { $0 + $1.base }, v.reduce(0) { $0 + $1.tva })
        }.sorted { $0.taux < $1.taux }
    }

    private func netLabel(_ net: Double) -> String {
        net < -0.5 ? "\(formatEuro(-net)) (crédit)" : formatEuro(net)
    }

    private func decCell(_ s: String, w: CGFloat, align: Alignment = .trailing,
                         bold: Bool = false, color: Color = .primary) -> some View {
        Text(s)
            .font(.callout).fontWeight(bold ? .semibold : .regular)
            .monospacedDigit().foregroundStyle(color)
            .lineLimit(1)
            .frame(width: w, alignment: align)
            .padding(.vertical, 4).padding(.horizontal, 4)
    }

    /// Tableau croisé I-1 : une ligne par mois, colonnes Base + TVA par taux.
    private var declarationsView: some View {
        let rates = Array(Set(entries.map { $0.taux }).filter { !$0.isEmpty && $0 != "—" })
            .sorted { (TvaHelper.rate($0) ?? 999) < (TvaHelper.rate($1) ?? 999) }
        let periodes = Set(entries.map { $0.periode }).union(deductDict.keys)
            .filter { !$0.isEmpty }.sorted()

        func vals(_ p: String, _ t: String) -> (base: Double, taxe: Double) {
            let es = entries.filter { $0.periode == p && $0.taux == t }
            return (es.reduce(0) { $0 + $1.base }, es.reduce(0) { $0 + $1.tva })
        }
        func coll(_ p: String) -> Double { rates.reduce(0.0) { $0 + vals(p, $1).taxe } }
        func net(_ p: String) -> Double { coll(p) - (deductDict[p] ?? 0) - (creditM1Dict[p] ?? 0) }
        func credit(_ p: String) -> Double { max(-net(p), 0) }
        // report attendu = crédit du mois précédent (vérification de la chaîne)
        func expectedReport(_ p: String) -> Double {
            guard let i = periodes.firstIndex(of: p), i > 0 else { return 0 }
            return credit(periodes[i - 1])
        }
        let totColl = periodes.reduce(0.0) { $0 + coll($1) }
        let totDed  = periodes.reduce(0.0) { $0 + (deductDict[$1] ?? 0) }
        let totM1   = periodes.reduce(0.0) { $0 + (creditM1Dict[$1] ?? 0) }
        let totPayer  = periodes.reduce(0.0) { $0 + max(net($1), 0) }
        let totCredit = periodes.reduce(0.0) { $0 + max(-net($1), 0) }
        let cw: CGFloat = 100

        return VStack(alignment: .leading, spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    // En-tête
                    HStack(spacing: 0) {
                        decCell("Période", w: 80, align: .leading, bold: true)
                        ForEach(rates, id: \.self) { r in
                            decCell("Base \(tauxLabel(r))", w: cw, bold: true)
                            decCell("TVA \(tauxLabel(r))", w: cw, bold: true)
                        }
                        decCell("Collectée", w: cw, bold: true)
                        decCell("Déductible", w: cw, bold: true)
                        decCell("Crédit M-1", w: cw, bold: true)
                        decCell("TVA à payer", w: 115, bold: true)
                        decCell("Crédit reporté", w: 115, bold: true)
                    }
                    .background(Color.gray.opacity(0.10))
                    Divider()

                    // Une ligne par mois
                    ForEach(periodes, id: \.self) { p in
                        let n = net(p)
                        let muted = Color(nsColor: .tertiaryLabelColor)
                        HStack(spacing: 0) {
                            decCell(p, w: 80, align: .leading)
                            ForEach(rates, id: \.self) { r in
                                let c = vals(p, r)
                                decCell(c.base == 0 ? "—" : formatEuro(c.base), w: cw,
                                        color: c.base == 0 ? muted : .primary)
                                decCell(c.taxe == 0 ? "—" : formatEuro(c.taxe), w: cw,
                                        color: c.taxe == 0 ? muted : .secondary)
                            }
                            decCell(formatEuro(coll(p)), w: cw)
                            decCell(formatEuro(deductDict[p] ?? 0), w: cw, color: .secondary)
                            // Crédit M-1 (report) : rouge si ≠ crédit du mois précédent (anomalie de report)
                            let m1 = creditM1Dict[p] ?? 0
                            let anomalie = abs(m1 - expectedReport(p)) > 1
                            decCell(m1 > 0.5 ? formatEuro(m1) : "—", w: cw,
                                    color: m1 > 0.5 ? (anomalie ? .red : .green) : muted)
                            decCell(n > 0.5 ? formatEuro(n) : "—", w: 115, color: n > 0.5 ? .primary : muted)
                            decCell(n < -0.5 ? formatEuro(-n) : "—", w: 115, color: n < -0.5 ? .blue : muted)
                        }
                        Divider()
                    }

                    // Total
                    HStack(spacing: 0) {
                        decCell("Total", w: 80, align: .leading, bold: true)
                        ForEach(rates, id: \.self) { r in
                            decCell(formatEuro(periodes.reduce(0.0) { $0 + vals($1, r).base }), w: cw, bold: true)
                            decCell(formatEuro(periodes.reduce(0.0) { $0 + vals($1, r).taxe }), w: cw, bold: true)
                        }
                        decCell(formatEuro(totColl), w: cw, bold: true)
                        decCell(formatEuro(totDed), w: cw, bold: true)
                        decCell(totM1 > 0.5 ? formatEuro(totM1) : "—", w: cw, bold: true)
                        decCell(totPayer > 0.5 ? formatEuro(totPayer) : "—", w: 115, bold: true)
                        decCell(totCredit > 0.5 ? formatEuro(totCredit) : "—", w: 115, bold: true,
                                color: totCredit > 0.5 ? .blue : .primary)
                    }
                    .background(Color.gray.opacity(0.10))
                }
                .padding()
            }

            Divider()
            HStack(spacing: 16) {
                Button { showCA3Importer = true } label: {
                    Label("Importer des CA3 (PDF)…", systemImage: "doc.text.viewfinder")
                }
                if let m = importMessage { Text(m).font(.caption).foregroundStyle(.green) }
                Spacer()
            }
            .font(.callout).padding()
        }
    }

    // MARK: Sous-vue Cohérence (contrôles de calcul)

    private func statutCell(ok: Bool, w: CGFloat = 70) -> some View {
        Text(ok ? "✓" : "✗")
            .fontWeight(.bold).foregroundStyle(ok ? .green : .red)
            .frame(width: w, alignment: .center)
            .padding(.vertical, 4)
    }

    private var coherenceView: some View {
        let periodes = Set(entries.map { $0.periode }).union(caHTDict.keys)
            .filter { !$0.isEmpty }.sorted()
        func sumBase(_ p: String) -> Double { entries.filter { $0.periode == p }.reduce(0) { $0 + $1.base } }
        func sumTaxe(_ p: String) -> Double { entries.filter { $0.periode == p }.reduce(0) { $0 + $1.tva } }
        func recalcTaxe(_ p: String) -> Double {
            entries.filter { $0.periode == p }.reduce(0.0) { $0 + (($1.base * (TvaHelper.rate($1.taux) ?? 0) / 100).rounded()) }
        }
        func coll(_ p: String) -> Double { sumTaxe(p) }
        func net(_ p: String) -> Double { coll(p) - (deductDict[p] ?? 0) - (creditM1Dict[p] ?? 0) }
        let cw: CGFloat = 105

        return ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 22) {

                // Contrôle 1 : bases (Σ = A1) et taxes (= base × taux)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Contrôle 1 — Calcul des taxes & bases")
                        .font(.headline).padding(.bottom, 6)
                    HStack(spacing: 0) {
                        decCell("Période", w: 80, align: .leading, bold: true)
                        decCell("Σ Bases", w: cw, bold: true)
                        decCell("CA HT (A1)", w: cw, bold: true)
                        decCell("Écart", w: 90, bold: true)
                        decCell("TVA = Σ base×taux", w: 140, bold: true)
                        decCell("Collectée", w: cw, bold: true)
                        decCell("Écart", w: 90, bold: true)
                        statutCell(ok: true).hidden().overlay(Text("Statut").font(.callout.bold()))
                    }
                    .background(Color.gray.opacity(0.10))
                    Divider()
                    ForEach(periodes, id: \.self) { p in
                        let a1 = caHTDict[p] ?? 0
                        let eBase = sumBase(p) - a1
                        let eTaxe = recalcTaxe(p) - coll(p)
                        let ok = abs(eBase) < 1 && abs(eTaxe) < 1
                        HStack(spacing: 0) {
                            decCell(p, w: 80, align: .leading)
                            decCell(formatEuro(sumBase(p)), w: cw)
                            decCell(a1 == 0 ? "—" : formatEuro(a1), w: cw, color: .secondary)
                            decCell(formatEuroSigned(eBase), w: 90, color: abs(eBase) < 1 ? .green : .red)
                            decCell(formatEuro(recalcTaxe(p)), w: 140)
                            decCell(formatEuro(coll(p)), w: cw, color: .secondary)
                            decCell(formatEuroSigned(eTaxe), w: 90, color: abs(eTaxe) < 1 ? .green : .red)
                            statutCell(ok: ok)
                        }
                        Divider()
                    }
                }

                // Contrôle 2 : Collectée − Déductible − Crédit M-1 = À payer / Crédit reporté
                VStack(alignment: .leading, spacing: 0) {
                    Text("Contrôle 2 — Cohérence du décompte (Collectée − Déductible − Crédit M-1)")
                        .font(.headline).padding(.bottom, 6)
                    HStack(spacing: 0) {
                        decCell("Période", w: 80, align: .leading, bold: true)
                        decCell("Collectée", w: cw, bold: true)
                        decCell("− Déductible", w: cw, bold: true)
                        decCell("− Crédit M-1", w: cw, bold: true)
                        decCell("= Net calculé", w: cw, bold: true)
                        decCell("À payer / Crédit", w: 130, bold: true)
                        decCell("Écart", w: 90, bold: true)
                        statutCell(ok: true).hidden().overlay(Text("Statut").font(.callout.bold()))
                    }
                    .background(Color.gray.opacity(0.10))
                    Divider()
                    ForEach(periodes, id: \.self) { p in
                        let n = net(p)
                        let declared = n >= 0 ? n : -(-n)   // à payer (n>0) ou -crédit (n<0)
                        let ecart = n - declared            // cohérence interne
                        let ok = abs(ecart) < 1
                        HStack(spacing: 0) {
                            decCell(p, w: 80, align: .leading)
                            decCell(formatEuro(coll(p)), w: cw)
                            decCell(formatEuro(deductDict[p] ?? 0), w: cw, color: .secondary)
                            decCell(formatEuro(creditM1Dict[p] ?? 0), w: cw, color: .secondary)
                            decCell(formatEuroSigned(n), w: cw, bold: true)
                            decCell(n >= 0 ? "à payer \(formatEuro(n))" : "crédit \(formatEuro(-n))",
                                    w: 130, color: n < 0 ? .blue : .primary)
                            decCell(formatEuroSigned(ecart), w: 90, color: ok ? .green : .red)
                            statutCell(ok: ok)
                        }
                        Divider()
                    }
                }
            }
            .padding()
        }
    }

    // MARK: Sous-vue Rapprochement (I-2)

    private var rapprochementView: some View {
        let tauxSet = Set(ventes.map { taux(for: $0) }.filter { !$0.isEmpty && $0 != "—" })
            .union(Set(entries.map { $0.taux }.filter { !$0.isEmpty && $0 != "—" }))
        let rows = tauxSet.sorted()

        return List {
            HStack {
                Text("Taux").frame(width: 80, alignment: .leading)
                Text("Base comptable").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Base déclarée").frame(width: 130, alignment: .trailing)
                Text("Écart").frame(width: 110, alignment: .trailing)
                Text("Écart %").frame(width: 90, alignment: .trailing)
                Text("Statut").frame(width: 90, alignment: .center)
            }
            .font(.caption).foregroundStyle(.secondary)

            ForEach(rows, id: \.self) { t in
                let bc = ventes.filter { taux(for: $0) == t }.reduce(0.0) { $0 + (-$1.balanceN) }
                let bd = entries.filter { $0.taux == t }.reduce(0.0) { $0 + $1.base }
                let ecart = bc - bd
                let pct = bc != 0 ? (ecart / bc) * 100 : (bd == 0 ? 0 : 100)
                let green = abs(pct) <= 0.05
                HStack {
                    Text(tauxLabel(t)).frame(width: 80, alignment: .leading)
                    Text(formatEuro(bc)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                    Text(formatEuro(bd)).monospacedDigit().frame(width: 130, alignment: .trailing)
                    Text(formatEuroSigned(ecart)).monospacedDigit().frame(width: 110, alignment: .trailing)
                        .foregroundStyle(green ? .green : .red)
                    Text(String(format: "%.3f %%", pct)).monospacedDigit().frame(width: 90, alignment: .trailing)
                        .foregroundStyle(green ? .green : .red)
                    Label(green ? "OK" : "À voir", systemImage: green ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly).foregroundStyle(green ? .green : .red)
                        .frame(width: 90, alignment: .center)
                }
                .padding(.vertical, 2)
            }

            if rows.isEmpty {
                Text("Configure les taux et saisis au moins une déclaration pour voir le rapprochement.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    private func setTaux(_ compte: String, _ taux: String) {
        let existing = tauxConfig.first { $0.exerciceID == exerciceID && $0.compte == compte }
        if taux == "—" || taux.isEmpty {
            if let e = existing { modelContext.delete(e) }   // revient à l'auto-détection
        } else if let e = existing {
            e.taux = taux
        } else {
            modelContext.insert(TvaCompteTaux(exerciceID: exerciceID, compte: compte, taux: taux))
        }
        try? modelContext.save()
    }
}

private struct Ca3EntryRow: View {
    @Bindable var entry: Ca3Entry
    var onCommit: () -> Void
    var onDelete: () -> Void
    @State private var baseText = ""
    @State private var tvaText = ""

    var body: some View {
        HStack {
            TextField("2025-01", text: $entry.periode)
                .textFieldStyle(.roundedBorder).frame(width: 90)
                .onChange(of: entry.periode) { _, _ in onCommit() }
            Picker("", selection: $entry.taux) {
                ForEach(TvaHelper.presets, id: \.self) { Text($0 == "Exo" ? "Exo" : ($0 == "—" ? "—" : "\($0)%")).tag($0) }
            }
            .labelsHidden().frame(width: 90)
            .onChange(of: entry.taux) { _, _ in onCommit() }
            TextField("base HT", text: $baseText)
                .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                .multilineTextAlignment(.trailing).monospacedDigit()
                .onSubmit { entry.base = parse(baseText); onCommit() }
            TextField("TVA", text: $tvaText)
                .textFieldStyle(.roundedBorder).frame(width: 140)
                .multilineTextAlignment(.trailing).monospacedDigit()
                .onSubmit { entry.tva = parse(tvaText); onCommit() }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless).frame(width: 30)
        }
        .padding(.vertical, 2)
        .onAppear {
            if baseText.isEmpty { baseText = entry.base == 0 ? "" : String(format: "%.0f", entry.base) }
            if tvaText.isEmpty { tvaText = entry.tva == 0 ? "" : String(format: "%.0f", entry.tva) }
        }
    }

    private func parse(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)) ?? 0
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
