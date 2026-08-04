//
//  ViewsDocumentsView.swift
//  RevisionVEB
//
//  Inventaire des pieces justificatives d'un exercice.
//
//  Les pieces sont rattachees a des endroits differents — un compte, un element
//  de rapprochement, une facture d'immobilisation, une declaration de TVA — et
//  n'etaient visibles qu'une par une, depuis le cycle concerne. Cette vue les
//  reunit pour repondre a une question simple : qu'est-ce que j'ai deja au
//  dossier, et qu'est-ce qui manque.
//

import SwiftUI
import SwiftData
import AppKit

/// Origine d'une piece, pour la retrouver dans l'application.
enum DocumentOrigine: String, CaseIterable {
    case justification = "Justification de compte"
    case rapprochement = "Élément de rapprochement"
    case factureImmo   = "Facture d'investissement"
    case declarationTva = "Déclaration de TVA"

    var icon: String {
        switch self {
        case .justification:  return "doc.text"
        case .rapprochement:  return "building.columns"
        case .factureImmo:    return "wrench.and.screwdriver"
        case .declarationTva: return "percent"
        }
    }

    var color: Color {
        switch self {
        case .justification:  return .blue
        case .rapprochement:  return .teal
        case .factureImmo:    return .purple
        case .declarationTva: return .orange
        }
    }
}

/// Une piece du dossier, quelle que soit sa provenance.
struct DocumentRow: Identifiable {
    let id = UUID()
    let cycle: RevisionCycle
    let rattachement: String     // numero de compte ou periode
    let libelle: String          // intitule du compte / de la piece
    let nom: String              // nom du fichier
    let chemin: String
    let origine: DocumentOrigine

    /// Le fichier est-il presente sur cette machine ?
    var estLocal: Bool { FileManager.default.fileExists(atPath: chemin) }
}

struct DocumentsView: View {
    let exerciceID: UUID
    let dossierID: UUID

    @Query private var justifications: [AccountJustification]
    @Query private var reconItems: [ReconItem]
    @Query private var immoInvoices: [ImmoInvoice]
    @Query private var ca3Periods: [Ca3Period]
    @Query private var rules: [AccountCycleRule]
    @Query(sort: \BalanceAccount.accountNumber) private var accounts: [BalanceAccount]

    @State private var filtre: DocumentOrigine?
    @State private var recherche = ""
    @State private var enCours: Set<String> = []

    // MARK: - Assemblage

    private var rulesDict: [String: RevisionCycle] {
        Dictionary(rules.filter { $0.dossierID == dossierID }.map { ($0.accountNumber, $0.cycle) },
                   uniquingKeysWith: { _, last in last })
    }

    private var libelles: [String: String] {
        Dictionary(accounts.filter { $0.exerciceID == exerciceID }
                           .map { ($0.accountNumber, $0.accountLabel.isEmpty ? $0.accountCode : $0.accountLabel) },
                   uniquingKeysWith: { _, last in last })
    }

    private func cycle(_ compte: String) -> RevisionCycle {
        rulesDict[compte] ?? RevisionCycle.forAccount(compte)
    }

    private var tous: [DocumentRow] {
        var rows: [DocumentRow] = []

        for j in justifications where j.exerciceID == exerciceID && !j.docPath.isEmpty {
            rows.append(DocumentRow(cycle: cycle(j.accountNumber),
                                    rattachement: j.accountNumber,
                                    libelle: libelles[j.accountNumber] ?? "",
                                    nom: j.docName.isEmpty ? URL(fileURLWithPath: j.docPath).lastPathComponent : j.docName,
                                    chemin: j.docPath,
                                    origine: .justification))
        }

        for i in reconItems where i.exerciceID == exerciceID && !i.docPath.isEmpty {
            rows.append(DocumentRow(cycle: cycle(i.accountNumber),
                                    rattachement: i.accountNumber,
                                    libelle: i.libelle,
                                    nom: i.docName.isEmpty ? URL(fileURLWithPath: i.docPath).lastPathComponent : i.docName,
                                    chemin: i.docPath,
                                    origine: .rapprochement))
        }

        for f in immoInvoices where f.exerciceID == exerciceID && !f.docPath.isEmpty {
            rows.append(DocumentRow(cycle: .immobilisations,
                                    rattachement: f.compte,
                                    libelle: f.designation,
                                    nom: f.docName.isEmpty ? URL(fileURLWithPath: f.docPath).lastPathComponent : f.docName,
                                    chemin: f.docPath,
                                    origine: .factureImmo))
        }

        for p in ca3Periods where p.exerciceID == exerciceID && !p.docPath.isEmpty {
            rows.append(DocumentRow(cycle: .fiscal,
                                    rattachement: p.periode,
                                    libelle: "Déclaration CA3",
                                    nom: p.docName.isEmpty ? URL(fileURLWithPath: p.docPath).lastPathComponent : p.docName,
                                    chemin: p.docPath,
                                    origine: .declarationTva))
        }

        return rows.sorted {
            ($0.cycle.letter, $0.rattachement, $0.nom) < ($1.cycle.letter, $1.rattachement, $1.nom)
        }
    }

    private var affiches: [DocumentRow] {
        var rows = tous
        if let f = filtre { rows = rows.filter { $0.origine == f } }
        let q = recherche.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            rows = rows.filter {
                $0.nom.lowercased().contains(q)
                    || $0.rattachement.lowercased().contains(q)
                    || $0.libelle.lowercased().contains(q)
            }
        }
        return rows
    }

    private var aRecuperer: Int { tous.filter { !$0.estLocal }.count }

    // MARK: - Vue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            Divider()

            if tous.isEmpty {
                PlaceholderView(
                    title: "Aucune pièce au dossier",
                    message: "Rattache des justificatifs depuis les cycles : ils apparaîtront tous ici."
                )
            } else if affiches.isEmpty {
                PlaceholderView(title: "Aucun résultat",
                                message: "Aucune pièce ne correspond à cette recherche.")
            } else {
                table
            }
        }
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.person.crop")
                    .font(.title2).foregroundStyle(.blue)
                Text("Pièces du dossier")
                    .font(.largeTitle).fontWeight(.bold)
                Spacer()
            }

            HStack(spacing: 16) {
                chip(label: "Pièces", value: "\(tous.count)")
                ForEach(DocumentOrigine.allCases, id: \.self) { o in
                    let n = tous.filter { $0.origine == o }.count
                    if n > 0 { chip(label: o.rawValue, value: "\(n)", color: o.color) }
                }
                if aRecuperer > 0 {
                    chip(label: "À récupérer", value: "\(aRecuperer)", color: .orange)
                }
            }

            HStack(spacing: 10) {
                Picker("", selection: $filtre) {
                    Text("Toutes").tag(DocumentOrigine?.none)
                    ForEach(DocumentOrigine.allCases, id: \.self) { o in
                        Text(o.rawValue).tag(DocumentOrigine?.some(o))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)

                TextField("Rechercher un document, un compte…", text: $recherche)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                Spacer()

                if aRecuperer > 0 {
                    Text("\(aRecuperer) pièce\(aRecuperer > 1 ? "s" : "") sera téléchargée depuis Supabase à l'ouverture")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    private var table: some View {
        Table(affiches) {
            TableColumn("Cycle") { d in
                Label("\(d.cycle.letter)", systemImage: d.cycle.icon)
                    .help(d.cycle.rawValue)
            }
            .width(60)

            TableColumn("Rattaché à") { d in
                Text(d.rattachement).monospaced()
            }
            .width(100)

            TableColumn("Intitulé") { d in
                Text(d.libelle).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 140, ideal: 200)

            TableColumn("Document") { d in
                HStack(spacing: 6) {
                    Image(systemName: d.origine.icon)
                        .font(.caption).foregroundStyle(d.origine.color)
                    Text(d.nom).lineLimit(1).help(d.nom)
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn("Origine") { d in
                Text(d.origine.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            .width(160)

            TableColumn("") { d in
                HStack(spacing: 8) {
                    if !d.estLocal {
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundStyle(.orange)
                            .help("Absente de cette machine — sera récupérée depuis Supabase")
                    }
                    Button("Ouvrir") {
                        openJustificationDocument(path: d.chemin, bookmark: nil)
                    }
                    .buttonStyle(.borderless)

                    if d.estLocal {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: d.chemin)])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Révéler dans le Finder")
                    }
                }
            }
            .width(120)
        }
    }

    private func chip(label: String, value: String, color: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }
}
