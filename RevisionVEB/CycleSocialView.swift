//
//  CycleSocialView.swift
//  RevisionVEB
//
//  Cycle H — Personnel et social : rapprochement des comptes 641 avec les
//  declarations sociales nominatives.
//
//  La presentation reprend le classeur de rapprochement 641/DSN 2025 : les deux
//  etablissements cote a cote par mois, le retraitement et le commentaire
//  saisissables, la tracabilite des assiettes DSN et la methodologie. Un ecart
//  sans son commentaire n'est pas un controle.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CycleSocialView: View {
    let exerciceID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var reconciliations: [SocialReconciliation]
    @Query private var anomalies: [SocialAnomaly]
    @Query private var dsnAssiettes: [DsnAssiette]
    @Query private var payrollEntries: [SocialPayrollEntry]
    @Query private var pieces: [CyclePiece]
    @Query private var comptes: [BalanceAccount]
    @Query private var justifications: [AccountJustification]

    @State private var selectedTab = 0
    @State private var showImporterFeuille = false
    @State private var pieceAJustifier: CyclePiece?
    @State private var messageJustification: String?

    static let moisNoms = ["", "Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
                           "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"]

    // MARK: - Donnees de l'exercice

    private var exerciceReconciliations: [SocialReconciliation] {
        reconciliations.filter { $0.exerciceID == exerciceID }
    }

    private var exerciceAnomalies: [SocialAnomaly] {
        anomalies.filter { $0.exerciceID == exerciceID }.sorted { $0.montant > $1.montant }
    }

    private var exerciceDsn: [DsnAssiette] {
        dsnAssiettes.filter { $0.exerciceID == exerciceID }
            .sorted { ($0.annee, $0.mois, $0.etablissement) < ($1.annee, $1.mois, $1.etablissement) }
    }

    private var exercicePayroll: [SocialPayrollEntry] {
        payrollEntries.filter { $0.exerciceID == exerciceID }
    }

    private var exercicePieces: [CyclePiece] {
        pieces.filter { $0.exerciceID == exerciceID && $0.cycle == .personnel }
            .sorted { ($0.categorie, $0.ordre, $0.libelle) < ($1.categorie, $1.ordre, $1.libelle) }
    }

    private var feuillesDeTravail: [CyclePiece] {
        exercicePieces.filter { $0.categorie != "Récapitulatif DSN" }
    }

    private var piecesDsn: [CyclePiece] {
        exercicePieces.filter { $0.categorie == "Récapitulatif DSN" }
    }

    /// La piece DSN correspondant a une ligne d'assiette, si elle est au dossier.
    private func pieceDsn(pour dsn: DsnAssiette) -> CyclePiece? {
        piecesDsn.first { $0.mois == dsn.mois && $0.annee == dsn.annee && $0.etablissement == dsn.etablissement }
    }

    /// Les comptes 641 de la balance de l'exercice.
    ///
    /// Le classeur justifie le rapprochement des comptes 641, et eux seuls : les
    /// charges patronales du compte 645 ne sont pas dans son perimetre.
    private var comptes641: [BalanceAccount] {
        comptes.filter { $0.exerciceID == exerciceID && $0.accountNumber.hasPrefix("641") }
            .sorted { $0.accountNumber < $1.accountNumber }
    }

    private var comptes641Justifies: Int {
        let justifiees = justifications.filter {
            $0.exerciceID == exerciceID && !$0.docPath.isEmpty && $0.soldeJustifie != nil
        }
        let numeros = Set(justifiees.map { $0.accountNumber })
        return comptes641.filter { numeros.contains($0.accountNumber) }.count
    }

    /// Une ligne du tableau : un mois, les deux etablissements cote a cote.
    struct LigneMois: Identifiable {
        let id: String
        let annee: Int
        let mois: Int
        let liesel: SocialReconciliation?
        let freddy: SocialReconciliation?

        var toutes: [SocialReconciliation] { [liesel, freddy].compactMap { $0 } }

        /// Statut du mois : OK seulement si les deux etablissements le sont.
        var statut: ReconciliationStatus {
            toutes.contains { $0.statut != .ok } ? .toJustify : .ok
        }

        var commentaire: String {
            toutes.first { !$0.commentaire.isEmpty }?.commentaire ?? ""
        }
    }

    private var lignesParMois: [LigneMois] {
        let groupes = Dictionary(grouping: exerciceReconciliations) { "\($0.annee)-\($0.mois)" }
        return groupes.map { key, recons in
            let premiere = recons[0]
            return LigneMois(
                id: key,
                annee: premiere.annee,
                mois: premiere.mois,
                liesel: recons.first { $0.etablissement == "LIESEL" },
                freddy: recons.first { $0.etablissement == "FREDDY" }
            )
        }
        .sorted { ($0.annee, $0.mois) < ($1.annee, $1.mois) }
    }

    private var nonJustifies: Int {
        exerciceReconciliations.filter { $0.statut != .ok }.count
    }

    // MARK: - Corps

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            Divider()

            switch selectedTab {
            case 0: rapprochementTab
            case 1: ecartsRestantsTab
            case 2: piecesTab
            case 3: sourcesDsnTab
            case 4: detailGlTab
            default: methodologieTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileImporter(isPresented: $showImporterFeuille,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { attacherFeuilles(urls) }
        }
        .confirmationDialog(
            "Justifier les comptes 641 ?",
            isPresented: Binding(get: { pieceAJustifier != nil },
                                 set: { if !$0 { pieceAJustifier = nil } }),
            titleVisibility: .visible
        ) {
            Button("Justifier les \(comptes641.count) comptes") {
                if let piece = pieceAJustifier { justifierComptes641(avec: piece) }
                pieceAJustifier = nil
            }
            Button("Annuler", role: .cancel) { pieceAJustifier = nil }
        } message: {
            Text("Chaque compte 641 sera marqué justifié à hauteur de son solde, "
                 + "avec « \(pieceAJustifier?.docName ?? "") » en pièce. "
                 + "Une justification déjà saisie sur un de ces comptes sera remplacée.")
        }
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.title2).foregroundStyle(.blue)
                Text("Cycle H — Personnel et social")
                    .font(.largeTitle).fontWeight(.bold)
                Spacer()
            }

            Text("Assiette GL = débits des comptes 641 par établissement, hors lignes « AN repas à déduire ». "
                 + "Assiette DSN = base AGIRC-ARRCO T1 (+T2) de janvier à juillet, base CTP 027D d'août à décembre.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                statTile("Écritures GL 641", "\(exercicePayroll.count)",
                         color: exercicePayroll.isEmpty ? .red : .primary)
                statTile("DSN importées", "\(exerciceDsn.count)",
                         color: exerciceDsn.isEmpty ? .red : .primary)
                statTile("Mois rapprochés", "\(lignesParMois.count)")
                statTile("À justifier", "\(nonJustifies)",
                         color: nonJustifies == 0 ? .green : .orange)

                Spacer()

                Button {
                    Task { await calculerRapprochement() }
                } label: {
                    Label(exerciceReconciliations.isEmpty ? "Calculer" : "Recalculer",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(exerciceDsn.isEmpty || exercicePayroll.isEmpty)
                .help(exerciceDsn.isEmpty || exercicePayroll.isEmpty
                      ? "Importe le grand livre 641 et les récapitulatifs DSN"
                      : "Recalcule les assiettes ; le retraitement et les commentaires saisis sont conservés")
            }

            Picker("", selection: $selectedTab) {
                Text("Rapprochement").tag(0)
                Text("Écarts restants").tag(1)
                Text("Pièces (\(exercicePieces.filter { $0.hasDocument }.count))").tag(2)
                Text("Sources DSN").tag(3)
                Text("Détail GL 641").tag(4)
                Text("Méthodologie").tag(5)
            }
            .pickerStyle(.segmented)
            .frame(width: 760)
            .padding(.top, 2)
        }
        .padding()
    }

    // MARK: - Onglet Rapprochement

    private var rapprochementTab: some View {
        Group {
            if lignesParMois.isEmpty {
                etatVide
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        enTeteTableau
                        Divider()
                        ForEach(lignesParMois) { ligne in
                            ligneRapprochement(ligne)
                            Divider()
                        }
                        ligneTotal
                    }
                    .padding()
                }
            }
        }
    }

    // Largeurs partagees entre l'en-tete et les lignes.
    private let wMois: CGFloat = 82
    private let wMontant: CGFloat = 96
    private let wStatut: CGFloat = 96
    private let wCommentaire: CGFloat = 320

    private var enTeteTableau: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("").frame(width: wMois)
                Text("Chez Tante Liesel")
                    .frame(width: wMontant * 3, alignment: .center)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.10))
                Text("Chez l'Oncle Freddy")
                    .frame(width: wMontant * 5, alignment: .center)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.10))
                Text("").frame(width: wStatut + wCommentaire)
            }
            .font(.caption).fontWeight(.semibold)

            HStack(spacing: 0) {
                colonne("Mois", wMois, .leading)
                colonne("GL 641", wMontant, .trailing)
                colonne("DSN", wMontant, .trailing)
                colonne("Écart", wMontant, .trailing)
                colonne("GL 641", wMontant, .trailing)
                colonne("DSN", wMontant, .trailing)
                colonne("Écart", wMontant, .trailing)
                colonne("Retraitement", wMontant, .trailing)
                colonne("Écart résiduel", wMontant, .trailing)
                colonne("Statut", wStatut, .leading)
                colonne("Commentaire", wCommentaire, .leading)
            }
            .font(.caption).fontWeight(.semibold)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.18))
        }
    }

    private func colonne(_ titre: String, _ largeur: CGFloat, _ align: Alignment) -> some View {
        Text(titre).frame(width: largeur, alignment: align).padding(.horizontal, 4)
    }

    private func ligneRapprochement(_ ligne: LigneMois) -> some View {
        HStack(spacing: 0) {
            Text(Self.moisNoms[min(max(ligne.mois, 1), 12)])
                .frame(width: wMois, alignment: .leading).padding(.horizontal, 4)

            montant(ligne.liesel?.soldeGL)
            montant(ligne.liesel?.soldeDisn)
            montantEcart(ligne.liesel?.ecart)

            montant(ligne.freddy?.soldeGL)
            montant(ligne.freddy?.soldeDisn)
            montantEcart(ligne.freddy?.ecart)

            // Retraitement : jugement saisi a la main, conserve au recalcul.
            if let freddy = ligne.freddy {
                TextField("0", value: retraitementBinding(freddy), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(.caption).monospacedDigit()
                    .frame(width: wMontant - 8)
                    .padding(.horizontal, 4)
            } else {
                Text("—").frame(width: wMontant, alignment: .trailing).padding(.horizontal, 4)
            }

            montantEcart(ligne.freddy?.ecartResiduel)

            Label(ligne.statut.rawValue, systemImage: iconeStatut(ligne.statut))
                .foregroundStyle(couleurStatut(ligne.statut))
                .frame(width: wStatut, alignment: .leading).padding(.horizontal, 4)

            TextField("Commentaire", text: commentaireBinding(ligne), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .lineLimit(1...3)
                .frame(width: wCommentaire - 8)
                .padding(.horizontal, 4)
        }
        .font(.caption)
        .padding(.vertical, 4)
        .background(ligne.statut == .ok ? Color.clear : Color.orange.opacity(0.06))
    }

    private var ligneTotal: some View {
        let lieselGL = exerciceReconciliations.filter { $0.etablissement == "LIESEL" }
        let freddyGL = exerciceReconciliations.filter { $0.etablissement == "FREDDY" }

        return HStack(spacing: 0) {
            Text("TOTAL").frame(width: wMois, alignment: .leading).padding(.horizontal, 4)
            montant(lieselGL.reduce(0) { $0 + $1.soldeGL })
            montant(lieselGL.reduce(0) { $0 + $1.soldeDisn })
            montantEcart(lieselGL.reduce(0) { $0 + $1.ecart })
            montant(freddyGL.reduce(0) { $0 + $1.soldeGL })
            montant(freddyGL.reduce(0) { $0 + $1.soldeDisn })
            montantEcart(freddyGL.reduce(0) { $0 + $1.ecart })
            montant(freddyGL.reduce(0) { $0 + $1.retraitement })
            montantEcart(freddyGL.reduce(0) { $0 + $1.ecartResiduel })
            Text("").frame(width: wStatut + wCommentaire)
        }
        .font(.caption).fontWeight(.semibold)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.12))
    }

    private func montant(_ valeur: Double?) -> some View {
        Text(valeur.map { Self.eur($0) } ?? "—")
            .monospacedDigit()
            .frame(width: wMontant, alignment: .trailing)
            .padding(.horizontal, 4)
    }

    private func montantEcart(_ valeur: Double?) -> some View {
        let v = valeur ?? 0
        return Text(valeur.map { Self.eur($0) } ?? "—")
            .monospacedDigit()
            .foregroundStyle(abs(v) < 1.0 ? Color.secondary : Color.orange)
            .frame(width: wMontant, alignment: .trailing)
            .padding(.horizontal, 4)
    }

    private var etatVide: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Aucun rapprochement").font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                checklistRow("Grand livre des comptes 641 importé (CSV)", done: !exercicePayroll.isEmpty)
                checklistRow("Récapitulatifs DSN importés (PDF)", done: !exerciceDsn.isEmpty)
            }
            .padding(12)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(8)

            Text("Les deux imports se font depuis le module Import, puis bouton « Calculer ».")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Onglet Écarts restants

    private var ecartsRestantsTab: some View {
        ScrollView {
            let aJustifier = exerciceReconciliations
                .filter { $0.statut != .ok }
                .sorted { abs($0.ecartResiduel) > abs($1.ecartResiduel) }

            if aJustifier.isEmpty && exerciceAnomalies.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48)).foregroundStyle(.green)
                    Text("Aucun écart à justifier").font(.headline)
                    Text(exerciceReconciliations.isEmpty
                         ? "Lance le rapprochement pour voir les écarts."
                         : "Tous les mois concordent à moins d'un euro.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Écarts restant à justifier")
                        .font(.headline)

                    ForEach(Array(aJustifier.enumerated()), id: \.element.id) { index, recon in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(index + 1).").fontWeight(.semibold)
                                Text("\(Self.moisNoms[min(max(recon.mois, 1), 12)]) — \(recon.etablissement)")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(Self.eur(recon.ecartResiduel) + " €")
                                    .monospacedDigit()
                                    .foregroundStyle(.orange)
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)

                            Text("GL \(Self.eur(recon.soldeGL)) € contre \(Self.eur(recon.soldeDisn)) € d'assiette DSN "
                                 + "(\(recon.posteDsnRetenu)). \(recon.soldeGLDetails).")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if recon.retraitement != 0 {
                                Text("Retraitement appliqué : \(Self.eur(recon.retraitement)) € "
                                     + "(écart initial \(Self.eur(recon.ecart)) €).")
                                    .font(.caption).foregroundStyle(.blue)
                            }

                            TextField("Constat et action proposée…",
                                      text: commentaireReconBinding(recon), axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .lineLimit(1...4)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.06))
                        .cornerRadius(8)
                    }

                    if !exerciceAnomalies.isEmpty {
                        Divider().padding(.vertical, 8)
                        Text("Anomalies détectées automatiquement").font(.headline)

                        ForEach(exerciceAnomalies) { anomaly in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label(anomaly.type.label, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).fontWeight(.semibold).foregroundStyle(.red)
                                    Spacer()
                                    Text("\(anomaly.mois)/\(anomaly.annee) · \(anomaly.etablissement)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(anomaly.titre).font(.caption)
                                Text("Montant : \(Self.eur(anomaly.montant)) €")
                                    .font(.caption).monospacedDigit()
                                if !anomaly.actionProposee.isEmpty {
                                    Text("→ \(anomaly.actionProposee)")
                                        .font(.caption).foregroundStyle(.secondary).italic()
                                }
                            }
                            .padding(8)
                            .background(Color.red.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Onglet Pièces

    private var piecesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Feuilles de travail
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Feuilles de travail").font(.headline)
                            Text("Le classeur de rapprochement et toute pièce justifiant le cycle dans son ensemble.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            showImporterFeuille = true
                        } label: {
                            Label("Ajouter une pièce", systemImage: "plus.circle")
                        }
                    }

                    if feuillesDeTravail.isEmpty {
                        Text("Aucune feuille de travail au dossier.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(feuillesDeTravail) { piece in
                            lignePiece(piece, supprimable: true)
                        }
                    }
                }
                .padding(14)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(10)

                // Materialisation des justifications de compte
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Justification des comptes 641").font(.headline)
                        Text("Porte la feuille de travail en pièce justificative de chaque compte 641, "
                             + "avec son solde. Les comptes apparaissent alors justifiés dans Recap.csv "
                             + "de l'export expert-comptable.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if comptes641.isEmpty {
                        Text("Aucun compte 641 dans la balance de cet exercice.")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        HStack(spacing: 12) {
                            statTile("Comptes 641", "\(comptes641.count)")
                            statTile("Déjà justifiés", "\(comptes641Justifies)",
                                     color: comptes641Justifies == comptes641.count ? .green : .secondary)
                            statTile("Solde total",
                                     Self.eur(comptes641.reduce(0) { $0 + $1.balanceN }) + " €")
                            Spacer()
                        }

                        if feuillesDeTravail.isEmpty {
                            Text("Ajoute d'abord la feuille de travail ci-dessus.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(feuillesDeTravail) { piece in
                                Button {
                                    pieceAJustifier = piece
                                } label: {
                                    Label("Justifier les \(comptes641.count) comptes 641 avec « \(piece.libelle) »",
                                          systemImage: "checkmark.seal")
                                }
                            }
                        }
                    }

                    if let message = messageJustification {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
                .padding(14)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(10)

                // Récapitulatifs DSN
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Récapitulatifs DSN — \(piecesDsn.count) pièce(s)").font(.headline)
                        Text("Archivés automatiquement à l'import du PDF. Chaque assiette déclarée a son document.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if piecesDsn.isEmpty {
                        Text("Aucun récapitulatif DSN au dossier. Importe les PDF depuis le module Import.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(piecesDsn) { piece in
                            lignePiece(piece, supprimable: false)
                        }
                    }
                }
                .padding(14)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(10)
            }
            .padding()
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    private func lignePiece(_ piece: CyclePiece, supprimable: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: piece.hasDocument ? "doc.fill" : "doc")
                .foregroundStyle(piece.hasDocument ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(piece.libelle.isEmpty ? piece.docName : piece.libelle)
                    .font(.subheadline)
                Text(piece.docName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            if !piece.categorie.isEmpty {
                Text(piece.categorie)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(4)
            }

            Button("Ouvrir") {
                openJustificationDocument(path: piece.docPath, bookmark: piece.docBookmark)
            }
            .disabled(!piece.hasDocument)

            if supprimable {
                Button {
                    if !piece.docPath.isEmpty {
                        try? FileManager.default.removeItem(atPath: piece.docPath)
                    }
                    modelContext.delete(piece)
                    try? modelContext.save()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
        .padding(8)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }

    /// Copie les pieces choisies dans le stockage de l'app : le chemin d'origine
    /// (iCloud, OneDrive) n'est pas fiable d'un Mac a l'autre.
    private func attacherFeuilles(_ urls: [URL]) {
        for url in urls {
            guard let copie = JustificatifStore.copyIn(source: url,
                                                       exerciceID: exerciceID,
                                                       accountNumber: "H feuille") else {
                print("⚠️ Pièce non copiée : \(url.lastPathComponent)")
                continue
            }

            let piece = CyclePiece(
                id: CyclePiece.stableID(exerciceID: exerciceID, cycle: .personnel,
                                        categorie: "Feuille de travail",
                                        annee: 0, mois: 0,
                                        etablissement: url.lastPathComponent),
                exerciceID: exerciceID,
                cycle: .personnel,
                categorie: "Feuille de travail",
                libelle: url.deletingPathExtension().lastPathComponent,
                ordre: feuillesDeTravail.count
            )
            piece.docPath = copie.path
            piece.docName = copie.name
            modelContext.insert(piece)
        }
        try? modelContext.save()
    }

    /// Porte la feuille de travail en piece justificative de chaque compte 641.
    ///
    /// Le solde justifie est celui de la balance : l'ecart affiche dans
    /// `Recap.csv` de l'export est donc nul, et la colonne Document porte le nom
    /// du classeur. C'est ce que lit l'expert-comptable.
    private func justifierComptes641(avec piece: CyclePiece) {
        let existantes = Dictionary(
            justifications.filter { $0.exerciceID == exerciceID }.map { ($0.accountNumber, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let note = "Justifié par le rapprochement 641 / DSN — \(piece.libelle)."

        for compte in comptes641 {
            let justification: AccountJustification
            if let existante = existantes[compte.accountNumber] {
                justification = existante
            } else {
                justification = AccountJustification(exerciceID: exerciceID,
                                                     accountNumber: compte.accountNumber)
                modelContext.insert(justification)
            }

            justification.soldeJustifie = compte.balanceN
            justification.docName = piece.docName
            justification.docPath = piece.docPath
            justification.docBookmark = nil
            justification.note = note
            justification.updatedAt = Date()
        }

        do {
            try modelContext.save()
            messageJustification = "\(comptes641.count) comptes 641 justifiés par « \(piece.docName) »."
            print("✅ Justifications 641 : \(comptes641.count) comptes")
        } catch {
            messageJustification = nil
            print("❌ Justifications 641 : \(error.localizedDescription)")
        }
    }

    // MARK: - Onglet Sources DSN

    private var sourcesDsnTab: some View {
        ScrollView([.horizontal, .vertical]) {
            if exerciceDsn.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Aucune DSN importée").font(.headline)
                    Text("Importe les récapitulatifs DSN en PDF depuis le module Import.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Traçabilité des assiettes DSN — un montant, un document")
                        .font(.headline).padding(.bottom, 10)

                    HStack(spacing: 0) {
                        colonne("Mois", wMois, .leading)
                        colonne("Établissement", 110, .leading)
                        colonne("SIRET", 130, .leading)
                        colonne("Assiette (€)", wMontant, .trailing)
                        colonne("Poste DSN retenu", 200, .leading)
                        colonne("Contrôle CTP 100D", 120, .trailing)
                        colonne("Fichier source", 340, .leading)
                    }
                    .font(.caption).fontWeight(.semibold)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.18))

                    Divider()

                    ForEach(exerciceDsn) { dsn in
                        HStack(spacing: 0) {
                            Text(Self.moisNoms[min(max(dsn.mois, 1), 12)])
                                .frame(width: wMois, alignment: .leading).padding(.horizontal, 4)
                            Text(dsn.etablissement)
                                .frame(width: 110, alignment: .leading).padding(.horizontal, 4)
                            Text(dsn.siret).monospacedDigit()
                                .frame(width: 130, alignment: .leading).padding(.horizontal, 4)
                            Text(Self.eur(dsn.assietteBrute)).monospacedDigit()
                                .frame(width: wMontant, alignment: .trailing).padding(.horizontal, 4)
                            Text(dsn.posteRetenu)
                                .frame(width: 200, alignment: .leading).padding(.horizontal, 4)
                            Text(dsn.ctp100d.map { Self.eur($0) } ?? "—").monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .trailing).padding(.horizontal, 4)
                            if let piece = pieceDsn(pour: dsn), piece.hasDocument {
                                Button {
                                    openJustificationDocument(path: piece.docPath, bookmark: piece.docBookmark)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.fill")
                                        Text(dsn.fichierSource).lineLimit(1).underline()
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                                .frame(width: 340, alignment: .leading).padding(.horizontal, 4)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                    Text(dsn.fichierSource).lineLimit(1)
                                }
                                .foregroundStyle(.orange)
                                .help("Le PDF n'est pas au dossier : réimporte-le pour l'archiver.")
                                .frame(width: 340, alignment: .leading).padding(.horizontal, 4)
                            }
                        }
                        .font(.caption)
                        .padding(.vertical, 4)

                        Divider()
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Onglet Détail GL 641

    private var detailGlTab: some View {
        ScrollView([.horizontal, .vertical]) {
            if exercicePayroll.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Aucune écriture 641").font(.headline)
                    Text("Importe le grand livre des comptes 641 en CSV depuis le module Import.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        colonne("Date", 86, .leading)
                        colonne("Compte", 84, .leading)
                        colonne("Libellé", 240, .leading)
                        colonne("Complément", 120, .leading)
                        colonne("Montant (€)", wMontant, .trailing)
                        colonne("Étab.", 76, .leading)
                        colonne("Assiette", 260, .leading)
                    }
                    .font(.caption).fontWeight(.semibold)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.18))

                    Divider()

                    ForEach(payrollTriees) { entry in
                        HStack(spacing: 0) {
                            Text(entry.dateEcriture.formatted(date: .numeric, time: .omitted))
                                .frame(width: 86, alignment: .leading).padding(.horizontal, 4)
                            Text(entry.compte).monospacedDigit()
                                .frame(width: 84, alignment: .leading).padding(.horizontal, 4)
                            Text(entry.libelle.trimmingCharacters(in: .whitespaces)).lineLimit(1)
                                .frame(width: 240, alignment: .leading).padding(.horizontal, 4)
                            Text(entry.complement).lineLimit(1).foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .leading).padding(.horizontal, 4)
                            Text(Self.eur(entry.montant)).monospacedDigit()
                                .frame(width: wMontant, alignment: .trailing).padding(.horizontal, 4)
                            Text(entry.etablissement)
                                .frame(width: 76, alignment: .leading).padding(.horizontal, 4)
                            if entry.retenuDansAssiette {
                                Label("Retenue", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .frame(width: 260, alignment: .leading).padding(.horizontal, 4)
                            } else {
                                Label(entry.motifExclusion.isEmpty ? "Exclue" : entry.motifExclusion,
                                      systemImage: "minus.circle")
                                    .foregroundStyle(.secondary).lineLimit(1)
                                    .frame(width: 260, alignment: .leading).padding(.horizontal, 4)
                            }
                        }
                        .font(.caption)
                        .padding(.vertical, 4)
                        .background(entry.retenuDansAssiette ? Color.clear : Color.gray.opacity(0.06))

                        Divider()
                    }
                }
                .padding()
            }
        }
    }

    private var payrollTriees: [SocialPayrollEntry] {
        exercicePayroll.sorted {
            ($0.dateEcriture, $0.etablissement, $0.compte) < ($1.dateEcriture, $1.etablissement, $1.compte)
        }
    }

    // MARK: - Onglet Méthodologie

    private var methodologieTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Méthodologie du rapprochement 641 / DSN")
                    .font(.title3).fontWeight(.bold)

                bloc("Périmètre",
                     "Comptes 641 du Grand Livre. Groupe 1 (64111000, 64120000, 64130000, 64140000, 64170000) "
                     + "= Chez Tante Liesel. Groupe 2 (64111100, 64120001, 64130001, 64140001, 64170001) "
                     + "= Chez l'Oncle Freddy. Comptes 64115000 à 64116510 (travailleurs non salariés) exclus.")

                bloc("Ce qui est comparé",
                     "Le compte 641 est tenu en brut : il est rapproché de l'assiette brute déclarée en DSN, "
                     + "et non du net versé. Les charges patronales (compte 645) ne sont pas concernées.")

                bloc("Assiette DSN — janvier à juillet",
                     "Base AGIRC-ARRCO Tranche 1 (plus Tranche 2 le cas échéant) des récapitulatifs DSN Payfit : "
                     + "elle est donnée au centime, là où les bases Urssaf sont arrondies à l'euro par la norme DSN.")

                bloc("Assiette DSN — août à décembre",
                     "Les états Arhia « État des cotisations » sont consolidés sur les deux établissements ; ce sont "
                     + "donc les états « DSN cotisations Urssaf », édités en deux exemplaires par mois (un par SIRET), "
                     + "qui sont utilisés. Le CTP 027D est retenu plutôt que le 100D car il couvre l'ensemble des "
                     + "salariés, apprentis compris.")

                bloc("Avantages en nature repas",
                     "Les lignes « AN repas à déduire » sont une déduction du net à payer, pas une réduction du brut : "
                     + "elles sont neutralisées des deux côtés.")

                bloc("Régularisations de périodes antérieures",
                     "Les récapitulatifs DSN utilisés sont les déclarations d'origine, générées au moment du dépôt. "
                     + "Un élément régularisé après coup figure donc dans l'écriture comptable du mois où il est payé, "
                     + "mais reste rattaché par la DSN à son mois d'origine. C'est ce décalage que corrige la colonne "
                     + "« Retraitement », saisie à la main et conservée d'un recalcul à l'autre.")

                bloc("Seuil de concordance",
                     "Un mois est réputé concordant lorsque l'écart résiduel de chaque établissement est inférieur "
                     + "à un euro. Au-delà, il passe « À justifier » et rejoint l'onglet Écarts restants.")
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func bloc(_ titre: String, _ texte: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(titre).font(.subheadline).fontWeight(.semibold)
            Text(texte).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Calcul

    /// Confronte, mois par mois et etablissement par etablissement, l'assiette du
    /// grand livre 641 a l'assiette declaree en DSN.
    ///
    /// Le retraitement et le commentaire sont des jugements saisis a la main : un
    /// recalcul les conserve, il ne recalcule que ce qui vient des fichiers.
    @MainActor
    private func calculerRapprochement() async {
        let dsn = exerciceDsn
        let gl = exercicePayroll.filter { $0.retenuDansAssiette }

        guard !dsn.isEmpty, !gl.isEmpty else {
            print("⚠️ Rapprochement : il manque \(dsn.isEmpty ? "les DSN" : "le grand livre 641")")
            return
        }

        var assietteGL: [String: Double] = [:]
        var lignesGL: [String: Int] = [:]
        for entry in gl {
            let key = "\(entry.annee)-\(entry.mois)-\(entry.etablissement)"
            assietteGL[key, default: 0] += entry.montant
            lignesGL[key, default: 0] += 1
        }

        let existantes = Dictionary(
            exerciceReconciliations.map { ("\($0.annee)-\($0.mois)-\($0.etablissement)", $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var crees = 0, majs = 0

        for d in dsn {
            let key = "\(d.annee)-\(d.mois)-\(d.etablissement)"
            let soldeGL = assietteGL[key] ?? 0

            let recon: SocialReconciliation
            if let existante = existantes[key] {
                recon = existante
                majs += 1
            } else {
                recon = SocialReconciliation(
                    exerciceID: exerciceID,
                    mois: d.mois,
                    annee: d.annee,
                    etablissement: d.etablissement,
                    siret: d.siret
                )
                // Identifiant derive de la cle logique : les deux Macs produisent
                // le meme, et Supabase met a jour au lieu de dupliquer.
                recon.id = SupabaseSync.stableID(
                    exerciceID.uuidString, "\(d.annee)", "\(d.mois)", d.etablissement
                )
                modelContext.insert(recon)
                crees += 1
            }

            recon.soldeGL = soldeGL
            recon.soldeGLDetails = "\(lignesGL[key] ?? 0) écritures 641 retenues"
            recon.soldeDisn = d.assietteBrute
            recon.posteDsnRetenu = d.posteRetenu
            recon.ecart = soldeGL - d.assietteBrute
            recon.ecartResiduel = recon.ecart + recon.retraitement
            recon.statut = abs(recon.ecartResiduel) < 1.0 ? .ok : .toJustify
            recon.dateCalcul = Date()

            if lignesGL[key] == nil && recon.commentaire.isEmpty {
                recon.commentaire = "Aucune écriture 641 pour ce mois dans le grand livre importé."
            }
        }

        do {
            try modelContext.save()
            print("✅ Rapprochement : \(crees) ligne(s) créée(s), \(majs) mise(s) à jour")
        } catch {
            print("❌ Rapprochement : échec de la sauvegarde — \(error.localizedDescription)")
        }
    }

    // MARK: - Liaisons de saisie

    private func retraitementBinding(_ recon: SocialReconciliation) -> Binding<Double> {
        Binding(
            get: { recon.retraitement },
            set: { nouveau in
                recon.retraitement = nouveau
                recon.ecartResiduel = recon.ecart + nouveau
                recon.statut = abs(recon.ecartResiduel) < 1.0 ? .ok : .toJustify
                try? modelContext.save()
            }
        )
    }

    /// Le commentaire est porte par le mois : il est recopie sur les deux
    /// etablissements pour survivre a la synchronisation.
    private func commentaireBinding(_ ligne: LigneMois) -> Binding<String> {
        Binding(
            get: { ligne.commentaire },
            set: { nouveau in
                for recon in ligne.toutes { recon.commentaire = nouveau }
                try? modelContext.save()
            }
        )
    }

    private func commentaireReconBinding(_ recon: SocialReconciliation) -> Binding<String> {
        Binding(
            get: { recon.commentaire },
            set: { nouveau in
                recon.commentaire = nouveau
                try? modelContext.save()
            }
        )
    }

    // MARK: - Presentation

    static func eur(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = " "
        f.decimalSeparator = ","
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    private func couleurStatut(_ statut: ReconciliationStatus) -> Color {
        switch statut {
        case .ok: return .green
        case .toCheck: return .orange
        case .toJustify: return .red
        }
    }

    private func iconeStatut(_ statut: ReconciliationStatus) -> String {
        switch statut {
        case .ok: return "checkmark.circle.fill"
        case .toCheck: return "exclamationmark.circle.fill"
        case .toJustify: return "xmark.circle.fill"
        }
    }

    private func statTile(_ titre: String, _ valeur: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre).font(.caption).foregroundStyle(.secondary)
            Text(valeur).font(.headline).monospacedDigit().foregroundStyle(color)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private func checklistRow(_ texte: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
            Text(texte).font(.caption)
        }
    }
}

#Preview {
    CycleSocialView(exerciceID: UUID())
        .modelContainer(for: SocialReconciliation.self, inMemory: true)
        .frame(width: 1400, height: 800)
}
