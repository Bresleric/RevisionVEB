//
//  ViewsSigCentresProfit.swift
//  RevisionVEB
//
//  Cycle A — soldes intermediaires eclates par centre de profit.
//
//  Le compte de resultat consolide dit ce que gagne la societe ; il ne dit pas
//  lequel des deux restaurants la porte. Trois vues repondent a cela : la
//  synthese de l'exercice, l'evolution d'un centre sur plusieurs exercices, et
//  le parametrage des rattachements.
//

import SwiftUI
import SwiftData

// MARK: - Synthese de l'exercice

struct SigCentresProfitView: View {
    let exerciceID: UUID
    let dossierID: UUID

    @Query(sort: \BalanceAccount.accountNumber) private var tousComptes: [BalanceAccount]
    @Query private var regles: [CentreProfitRule]

    private var comptes: [BalanceAccount] { tousComptes.filter { $0.exerciceID == exerciceID } }
    private var reglesParCompte: [String: CentreProfitRule] {
        Dictionary(regles.filter { $0.dossierID == dossierID }.map { ($0.accountNumber, $0) },
                   uniquingKeysWith: { first, _ in first })
    }
    private var lignes: [SigParCentre.Ligne] {
        SigParCentre.cascade(comptes: comptes, regles: reglesParCompte)
    }
    private var sansRegle: [BalanceAccount] {
        SigParCentre.comptesSansRegle(comptes: comptes, regles: reglesParCompte)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Soldes intermédiaires par centre de profit")
                        .font(.title3).fontWeight(.bold)
                    Text("Les charges communes se répartissent selon leur clé. La rémunération des "
                         + "dirigeants reste à part : elle n'est imputable à aucun des deux restaurants.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if reglesParCompte.isEmpty {
                    CentresProfitVide()
                } else {
                    tableau
                    if !sansRegle.isEmpty {
                        CentresProfitAvertissement(comptes: sansRegle)
                    }
                }
            }
            .padding()
        }
    }

    private var tableau: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("").frame(width: 230, alignment: .leading)
                ForEach(["Freddy", "Liesel", "Dirigeants", "Total"], id: \.self) { t in
                    Text(t).frame(width: 130, alignment: .trailing).padding(.horizontal, 6)
                }
                Spacer()
            }
            .font(.caption).fontWeight(.semibold)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.18))

            Divider()

            ForEach(lignes) { l in
                HStack(spacing: 0) {
                    Text(l.libelle).frame(width: 230, alignment: .leading)
                    montantCentre(l.freddy)
                    montantCentre(l.liesel)
                    montantCentre(l.dirigeants, grise: abs(l.dirigeants) < 0.005)
                    montantCentre(l.total, gras: true)
                    Spacer()
                }
                .font(l.solde ? .callout.weight(.semibold) : .callout)
                .padding(.vertical, 5)
                .background(l.libelle.hasPrefix("= RÉSULTAT") ? Color.green.opacity(0.10)
                            : (l.solde ? Color.gray.opacity(0.07) : Color.clear))
                Divider()
            }
        }
    }
}

// MARK: - Evolution d'un centre sur plusieurs exercices

struct EvolutionCentreView: View {
    let dossierID: UUID

    @Query(sort: \BalanceAccount.accountNumber) private var tousComptes: [BalanceAccount]
    @Query private var regles: [CentreProfitRule]
    @Query private var exercices: [Exercice]

    @State private var centre: CentreProfit? = .freddy   // nil = tous cumules

    /// Exercices du dossier qui portent effectivement une balance, du plus
    /// ancien au plus recent. Un exercice vide n'apporte qu'une colonne de
    /// zeros et brouille la lecture.
    private var exercicesUtiles: [Exercice] {
        exercices
            .filter { ex in
                ex.dossierID == dossierID && tousComptes.contains { $0.exerciceID == ex.id }
            }
            .sorted { $0.libelle < $1.libelle }
    }

    private var reglesParCompte: [String: CentreProfitRule] {
        Dictionary(regles.filter { $0.dossierID == dossierID }.map { ($0.accountNumber, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Cascade par exercice, dans l'ordre chronologique.
    private var cascades: [(exercice: Exercice, lignes: [SigParCentre.Ligne])] {
        exercicesUtiles.map { ex in
            (ex, SigParCentre.cascade(
                comptes: tousComptes.filter { $0.exerciceID == ex.id },
                regles: reglesParCompte))
        }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 16) {
                entete

                if reglesParCompte.isEmpty {
                    CentresProfitVide()
                } else if exercicesUtiles.count < 2 {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Un seul exercice comporte une balance").font(.headline)
                        Text("L'évolution demande au moins deux exercices renseignés. "
                             + "Importe la balance d'un exercice antérieur pour comparer.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 440)
                    }
                    .frame(maxWidth: .infinity).padding(40)
                } else {
                    tableau
                }
            }
            .padding()
        }
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Évolution par centre de profit")
                    .font(.title3).fontWeight(.bold)
                Text("Le même paramétrage s'applique à tous les exercices : c'est ce qui rend la "
                     + "comparaison possible. La variation confronte le dernier exercice au précédent.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("", selection: $centre) {
                Text("Freddy").tag(CentreProfit?.some(.freddy))
                Text("Liesel").tag(CentreProfit?.some(.liesel))
                Text("Dirigeants").tag(CentreProfit?.some(.dirigeants))
                Text("Ensemble").tag(CentreProfit?.none)
            }
            .pickerStyle(.segmented)
            .frame(width: 460)
        }
    }

    private var tableau: some View {
        let colonnes = cascades
        let nbLignes = colonnes.first?.lignes.count ?? 0

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("").frame(width: 230, alignment: .leading)
                ForEach(colonnes, id: \.exercice.id) { c in
                    Text(c.exercice.libelle)
                        .frame(width: 130, alignment: .trailing).padding(.horizontal, 6)
                }
                Text("Variation").frame(width: 130, alignment: .trailing).padding(.horizontal, 6)
                Spacer()
            }
            .font(.caption).fontWeight(.semibold)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.18))

            Divider()

            ForEach(0..<nbLignes, id: \.self) { i in
                let modele = colonnes[0].lignes[i]
                let valeurs = colonnes.map { $0.lignes[i].montant(centre) }
                let variation = valeurs.count >= 2 ? valeurs[valeurs.count - 1] - valeurs[valeurs.count - 2] : 0

                HStack(spacing: 0) {
                    Text(modele.libelle).frame(width: 230, alignment: .leading)
                    ForEach(Array(valeurs.enumerated()), id: \.offset) { _, v in
                        montantCentre(v)
                    }
                    Text(valeurs.count >= 2 ? formatEuroSigned(variation) : "—")
                        .monospacedDigit()
                        .foregroundStyle(variationCouleur(modele.libelle, variation))
                        .frame(width: 130, alignment: .trailing).padding(.horizontal, 6)
                    Spacer()
                }
                .font(modele.solde ? .callout.weight(.semibold) : .callout)
                .padding(.vertical, 5)
                .background(modele.libelle.hasPrefix("= RÉSULTAT") ? Color.green.opacity(0.10)
                            : (modele.solde ? Color.gray.opacity(0.07) : Color.clear))
                Divider()
            }
        }
    }

    /// Une hausse n'est pas toujours une bonne nouvelle : elle est favorable
    /// sur un solde ou un produit, defavorable sur une charge. Le signe seul
    /// induirait en erreur, donc on ne colore que ce dont le sens est sur.
    private func variationCouleur(_ libelle: String, _ variation: Double) -> Color {
        guard abs(variation) > 0.5 else { return .secondary }
        let favorableSiHausse = libelle.hasPrefix("=") || libelle.hasPrefix("+") || libelle == "Ventes"
        let favorable = favorableSiHausse ? variation > 0 : variation < 0
        return favorable ? .green : .red
    }
}

// MARK: - Parametrage des rattachements

struct ParametrageCentresView: View {
    let exerciceID: UUID
    let dossierID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BalanceAccount.accountNumber) private var tousComptes: [BalanceAccount]
    @Query private var regles: [CentreProfitRule]

    @State private var recherche = ""
    @State private var masquerRattaches = false

    /// Comptes de charge et de produit : les seuls qui entrent dans les SIG.
    private var comptes: [BalanceAccount] {
        tousComptes.filter {
            $0.exerciceID == exerciceID
                && ($0.accountNumber.hasPrefix("6") || $0.accountNumber.hasPrefix("7"))
        }
    }

    private var reglesParCompte: [String: CentreProfitRule] {
        Dictionary(regles.filter { $0.dossierID == dossierID }.map { ($0.accountNumber, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    private var filtres: [BalanceAccount] {
        let r = reglesParCompte
        let q = recherche.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR")).lowercased()
        return comptes.filter { c in
            if masquerRattaches && r[c.accountNumber] != nil { return false }
            guard !q.isEmpty else { return true }
            let texte = (c.accountNumber + " " + c.accountLabel + " " + c.accountCode)
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR")).lowercased()
            return texte.contains(q)
        }
    }

    private var nbRattaches: Int { comptes.filter { reglesParCompte[$0.accountNumber] != nil }.count }

    /// Clé déduite du chiffre d'affaires de l'exercice affiché.
    private var cleCA: (partLiesel: Double, caFreddy: Double, caLiesel: Double)? {
        SigParCentre.cleChiffreAffaires(
            comptes: tousComptes.filter { $0.exerciceID == exerciceID },
            regles: reglesParCompte)
    }

    private var comptesCommuns: [CentreProfitRule] {
        let numeros = Set(comptes.map { $0.accountNumber })
        return regles.filter {
            $0.dossierID == dossierID && $0.centre == .commun && numeros.contains($0.accountNumber)
        }
    }

    var body: some View {
        // `GeometryReader` impose la taille reellement disponible au lieu de
        // laisser le contenu la reclamer. C'est le seul moyen sur : borner la
        // liste ne suffisait pas, car l'en-tete et la pile continuaient de
        // demander plus de hauteur que la fenetre, si bien que le haut de la
        // vue — selecteur d'onglets compris — remontait sous la barre de titre.
        // Ici la pile ne peut pas depasser, et le defilement se fait a
        // l'interieur de la place restante.
        GeometryReader { geo in
            contenu
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipped()
        }
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            Divider()

            if comptes.isEmpty {
                PlaceholderView(title: "Aucun compte de charge ou de produit",
                                message: "Importe la balance de cet exercice pour paramétrer les centres de profit.")
            } else {
                enTeteColonnes
                Divider()

                // La liste occupe toute la place restante sous l'en-tete, sans
                // jamais la depasser : c'est le GeometryReader qui la borne.
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtres) { compte in
                            LigneParametrage(
                                compte: compte,
                                regle: reglesParCompte[compte.accountNumber],
                                onCentre: { definir(compte, centre: $0) },
                                onPart: { definirPart(compte, $0) }
                            )
                            .padding(.horizontal, 12)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                Divider()
                HStack {
                    Text("\(filtres.count) compte(s) affiché(s)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
    }

    /// En-tete de colonnes fixe, hors de la zone qui defile.
    private var enTeteColonnes: some View {
        HStack {
            Text("Compte").frame(width: 90, alignment: .leading)
            Text("Intitulé").frame(maxWidth: .infinity, alignment: .leading)
            Text("Solde").frame(width: 110, alignment: .trailing)
            Text("Centre de profit").frame(width: 190, alignment: .leading)
            Text("Part Liesel").frame(width: 110, alignment: .leading)
        }
        .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.gray.opacity(0.12))
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Paramétrage des centres de profit")
                    .font(.title3).fontWeight(.bold)
                Text("Le rattachement vaut pour le dossier, pas pour un exercice : c'est ce qui permet "
                     + "de comparer les années entre elles, et il survit aux réimports de balance.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                TextField("Rechercher un compte ou un intitulé…", text: $recherche)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                Toggle("Masquer les comptes déjà rattachés", isOn: $masquerRattaches)
                    .toggleStyle(.switch).controlSize(.small)

                Spacer()

                Text("\(nbRattaches) / \(comptes.count) rattachés")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(nbRattaches == comptes.count ? .green : .orange)
            }

            bandeauCleCA
        }
        .padding()
    }

    /// Clé de répartition déduite du chiffre d'affaires.
    @ViewBuilder
    private var bandeauCleCA: some View {
        if let cle = cleCA {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clé déduite du chiffre d'affaires")
                        .font(.caption).fontWeight(.semibold)
                    Text("Freddy \(formatEuro(cle.caFreddy)) · Liesel \(formatEuro(cle.caLiesel))")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }

                Text(String(format: "Liesel %.2f %%   ·   Freddy %.2f %%",
                            cle.partLiesel, 100 - cle.partLiesel))
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(6)

                Spacer()

                Button {
                    appliquerCleCA(cle.partLiesel)
                } label: {
                    Label("Appliquer aux \(comptesCommuns.count) comptes communs",
                          systemImage: "arrow.triangle.branch")
                }
                .disabled(comptesCommuns.isEmpty)
                .help("Remplace la clé de chaque charge commune par la part du chiffre d'affaires")
            }
            .padding(10)
            .background(Color.blue.opacity(0.06))
            .cornerRadius(8)
        } else {
            Label("Clé du chiffre d'affaires indisponible : aucun compte de vente n'est encore "
                  + "rattaché à Freddy ou Liesel.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func regle(pour compte: BalanceAccount) -> CentreProfitRule {
        if let existante = reglesParCompte[compte.accountNumber] { return existante }
        let nouvelle = CentreProfitRule(
            id: CentreProfitRule.stableID(dossierID: dossierID, accountNumber: compte.accountNumber),
            dossierID: dossierID, accountNumber: compte.accountNumber
        )
        modelContext.insert(nouvelle)
        return nouvelle
    }

    private func definir(_ compte: BalanceAccount, centre: CentreProfit) {
        let r = regle(pour: compte)
        r.centre = centre
        // Un compte que l'on passe en commun prend la clé du chiffre
        // d'affaires : c'est la répartition la plus défendable, et elle évite
        // qu'un forfait hérité s'applique sans qu'on y pense.
        if centre == .commun, let cle = cleCA {
            r.partLiesel = cle.partLiesel
        }
        r.touch()
        try? modelContext.save()
    }

    /// Reporte la clé du chiffre d'affaires sur toutes les charges communes.
    private func appliquerCleCA(_ part: Double) {
        for regle in comptesCommuns {
            regle.partLiesel = part
            regle.touch()
        }
        try? modelContext.save()
        print(String(format: "🔑 Clé du CA appliquée à %d compte(s) commun(s) : Liesel %.2f %%",
                     comptesCommuns.count, part))
    }

    private func definirPart(_ compte: BalanceAccount, _ part: Double) {
        let r = regle(pour: compte)
        r.partLiesel = max(0, min(100, part))
        r.touch()
        try? modelContext.save()
    }
}

private struct LigneParametrage: View {
    let compte: BalanceAccount
    let regle: CentreProfitRule?
    var onCentre: (CentreProfit) -> Void
    var onPart: (Double) -> Void

    @State private var partTexte = ""

    var body: some View {
        HStack {
            Text(compte.accountNumber).monospaced().frame(width: 90, alignment: .leading)
            Text(compte.accountLabel.isEmpty ? compte.accountCode : compte.accountLabel)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(formatEuro(compte.balanceN)).monospacedDigit()
                .frame(width: 110, alignment: .trailing)

            Picker("", selection: Binding(
                get: { regle?.centre ?? CentreProfit.commun },
                set: { onCentre($0) }
            )) {
                ForEach(CentreProfit.allCases) { c in
                    Text(c.libelle).tag(c)
                }
            }
            .labelsHidden()
            .frame(width: 190)
            // Un compte non rattache se signale : il sort des totaux.
            .tint(regle == nil ? .orange : .secondary)

            // La cle ne concerne que les charges communes.
            if regle?.centre == .commun {
                HStack(spacing: 2) {
                    TextField("16,67", text: $partTexte)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 62)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .onSubmit {
                            if let v = ImportManager.parseFrenchAmount(partTexte) { onPart(v) }
                        }
                    Text("%").font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 110, alignment: .leading)
            } else {
                Text("—").foregroundStyle(.tertiary).frame(width: 110, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            if let p = regle?.partLiesel { partTexte = String(format: "%g", p) }
        }
    }
}

// MARK: - Elements partages

/// Montant d'une colonne de centre.
@ViewBuilder
private func montantCentre(_ v: Double, gras: Bool = false, grise: Bool = false) -> some View {
    Text(formatEuro(v))
        .monospacedDigit()
        .fontWeight(gras ? .semibold : .regular)
        .foregroundStyle(grise ? Color.secondary.opacity(0.5) : (v < 0 ? Color.red : Color.primary))
        .frame(width: 130, alignment: .trailing)
        .padding(.horizontal, 6)
}

private struct CentresProfitVide: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.split.2x1")
                .font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Aucun compte rattaché").font(.headline)
            Text("Va dans l'onglet Paramétrage pour rattacher les comptes, ou importe la table "
                 + "depuis le module Import : un CSV dont le nom contient « centre ».")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity).padding(40)
    }
}

/// Un compte de charge ou de produit sans rattachement disparait du tableau :
/// mieux vaut le dire que de laisser croire a un total complet.
private struct CentresProfitAvertissement: View {
    let comptes: [BalanceAccount]

    var body: some View {
        let total = comptes.reduce(0) { $0 + abs($1.balanceN) }
        VStack(alignment: .leading, spacing: 6) {
            Label("\(comptes.count) compte(s) sans centre de profit — \(formatEuro(total)) hors tableau",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.orange)

            Text("Ces comptes ne sont imputés à aucune colonne : les totaux ci-dessus sont donc "
                 + "incomplets. Complète-les dans l'onglet Paramétrage.")
                .font(.caption2).foregroundStyle(.secondary)

            ForEach(comptes.prefix(12)) { c in
                Text("\(c.accountNumber)  \(c.accountLabel.isEmpty ? c.accountCode : c.accountLabel)  —  \(formatEuro(c.balanceN))")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            if comptes.count > 12 {
                Text("… et \(comptes.count - 12) autre(s)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.07))
        .cornerRadius(8)
    }
}
