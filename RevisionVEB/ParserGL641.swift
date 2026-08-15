//
//  ParserGL641.swift
//  RevisionVEB
//
//  Cycle H — lecture du Grand Livre des comptes 641 (CSV / TXT).
//
//  Regles de perimetre reprises de la note de methodologie du rapprochement
//  641 / DSN 2025 :
//   - Groupe 1 (64111000, 64120000, 64130000, 64140000, 64170000) = Chez Tante Liesel
//   - Groupe 2 (64111100, 64120001, 64130001, 64140001, 64170001) = Chez l'Oncle Freddy
//   - Comptes 64115000 a 64116510 (travailleurs non salaries) exclus
//   - Lignes « AN repas a deduire » neutralisees : ce sont une deduction du net
//     a payer, pas une reduction du brut.
//

import Foundation

/// Une ecriture du grand livre 641, prete a devenir un `SocialPayrollEntry`.
struct Gl641Line {
    var date: Date
    var mois: Int
    var annee: Int
    var compte: String
    var libelle: String
    var complement: String
    var debit: Double
    var credit: Double
    var etablissement: String      // "LIESEL", "FREDDY" ou "UNKNOWN"
    var retenu: Bool
    var motifExclusion: String

    /// Assiette = debit - credit. Le compte 641 est tenu en brut au debit.
    var montant: Double { debit - credit }
}

enum Gl641Parser {

    // MARK: - Perimetre

    static let comptesLiesel: Set<String> = [
        "64111000", "64120000", "64130000", "64140000", "64170000"
    ]

    static let comptesFreddy: Set<String> = [
        "64111100", "64120001", "64130001", "64140001", "64170001"
    ]

    /// Travailleurs non salaries : hors assiette DSN.
    private static let tnsRange = 64115000...64116510

    static let siretLiesel = "80531846600010"
    static let siretFreddy = "80531846600028"

    static func siret(for etablissement: String) -> String {
        etablissement == "FREDDY" ? siretFreddy : siretLiesel
    }

    // MARK: - Parsing

    /// Analyse le contenu texte d'un grand livre 641.
    ///
    /// Les colonnes sont detectees par leur en-tete, dans n'importe quel ordre.
    /// Si le fichier porte deja les colonnes « Etablissement » et « Retenu dans
    /// l'assiette » (export du classeur de rapprochement), elles font foi :
    /// c'est le travail deja arbitre, on ne le refait pas.
    static func parse(content: String) -> [Gl641Line] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let headerIndex = lines.firstIndex(where: { isHeader($0) }) else {
            print("❌ GL 641 : ligne d'en-tete introuvable (attendu : Date, Compte, Debit, Credit)")
            return []
        }

        let sep = detectSeparator(lines[headerIndex])
        let header = split(lines[headerIndex], sep: sep)
        let cols = detectColumns(header)

        guard cols.compte >= 0 else {
            print("❌ GL 641 : colonne 'Compte' introuvable")
            return []
        }

        var result: [Gl641Line] = []

        for raw in lines[(headerIndex + 1)...] {
            let row = split(raw, sep: sep)
            let compte = value(row, cols.compte)
                .trimmingCharacters(in: .whitespaces)
            guard !compte.isEmpty, compte.hasPrefix("641") else { continue }
            // Lignes de sous-total Cegid
            guard !compte.uppercased().contains("ZZZ") else { continue }

            let libelle = value(row, cols.libelle).trimmingCharacters(in: .whitespaces)
            let complement = value(row, cols.complement).trimmingCharacters(in: .whitespaces)
            let debit = ImportManager.parseFrenchAmount(value(row, cols.debit)) ?? 0
            let credit = ImportManager.parseFrenchAmount(value(row, cols.credit)) ?? 0

            guard let date = parseDate(value(row, cols.date)) else { continue }
            let parts = Calendar.current.dateComponents([.year, .month], from: date)
            guard let annee = parts.year, let mois = parts.month else { continue }

            // Etablissement : colonne du fichier si presente, sinon deduction.
            let etabColonne = value(row, cols.etablissement)
                .trimmingCharacters(in: .whitespaces).uppercased()
            let etablissement = etabColonne.isEmpty
                ? deduireEtablissement(compte: compte, libelle: libelle)
                : etabColonne

            // Retenu dans l'assiette : colonne du fichier si presente, sinon regles.
            var retenu: Bool
            var motif = ""
            let retenuColonne = fold(value(row, cols.retenu))
            if !retenuColonne.isEmpty {
                retenu = !(retenuColonne.hasPrefix("n") || retenuColonne.hasPrefix("f"))
                if !retenu { motif = value(row, cols.motif).trimmingCharacters(in: .whitespaces) }
                if !retenu && motif.isEmpty { motif = "Exclu par le fichier source" }
            } else {
                (retenu, motif) = evaluerExclusion(compte: compte,
                                                   libelle: libelle,
                                                   complement: complement,
                                                   etablissement: etablissement)
            }

            result.append(Gl641Line(
                date: date,
                mois: mois,
                annee: annee,
                compte: compte,
                libelle: libelle,
                complement: complement,
                debit: debit,
                credit: credit,
                etablissement: etablissement,
                retenu: retenu,
                motifExclusion: motif
            ))
        }

        return result
    }

    // MARK: - Regles de perimetre

    /// Rattache une ecriture a un etablissement.
    ///
    /// Le numero de compte tranche d'abord : les deux groupes sont disjoints.
    /// A defaut (compte 641 hors des deux listes), on se rabat sur le libelle,
    /// qui porte le nom de l'etablissement dans les OD de paie Cegid
    /// (« Paie Freddy 2025 01 »).
    static func deduireEtablissement(compte: String, libelle: String) -> String {
        if comptesFreddy.contains(compte) { return "FREDDY" }
        if comptesLiesel.contains(compte) { return "LIESEL" }

        let l = fold(libelle)
        if l.contains("freddy") { return "FREDDY" }
        if l.contains("liesel") || l.contains("bonbao") { return "LIESEL" }

        return "UNKNOWN"
    }

    /// Determine si la ligne entre dans l'assiette rapprochee de la DSN.
    private static func evaluerExclusion(compte: String,
                                         libelle: String,
                                         complement: String,
                                         etablissement: String) -> (Bool, String) {
        // Travailleurs non salaries : pas de DSN.
        if let n = Int(compte), tnsRange.contains(n) {
            return (false, "Travailleur non salarie (compte \(compte))")
        }

        // Avantage en nature repas : deduction du net a payer, pas du brut.
        let texte = fold(libelle) + " " + fold(complement)
        if texte.contains("an repas") || texte.contains("avantage en nature repas") {
            return (false, "AN repas : deduction du net, neutralisee des deux cotes")
        }

        if etablissement == "UNKNOWN" {
            return (false, "Etablissement non identifie")
        }

        return (true, "")
    }

    // MARK: - Outils de lecture

    private struct Columns {
        var date = -1, compte = -1, libelle = -1, complement = -1
        var debit = -1, credit = -1
        var etablissement = -1, retenu = -1, motif = -1
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isHeader(_ line: String) -> Bool {
        let f = fold(line)
        return f.contains("compte") && (f.contains("debit") || f.contains("credit"))
    }

    private static func detectSeparator(_ headerLine: String) -> String {
        if headerLine.contains("\t") { return "\t" }
        if headerLine.contains(";") { return ";" }
        if headerLine.contains(",") { return "," }
        return ";"
    }

    /// Decoupe une ligne CSV en respectant les guillemets : un libelle exporte
    /// par Excel peut contenir le separateur.
    private static func split(_ line: String, sep: String) -> [String] {
        guard let sepChar = sep.first else { return [line] }
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == sepChar && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func detectColumns(_ header: [String]) -> Columns {
        var m = Columns()
        for (i, raw) in header.enumerated() {
            let c = fold(raw)
            if c.contains("date") && m.date < 0 { m.date = i }
            else if c.contains("compte") && m.compte < 0 { m.compte = i }
            else if (c.contains("libell") || c.contains("intitul")) && m.libelle < 0 { m.libelle = i }
            else if c.contains("complement") && m.complement < 0 { m.complement = i }
            else if c.contains("debit") && m.debit < 0 { m.debit = i }
            else if c.contains("credit") && m.credit < 0 { m.credit = i }
            else if c.contains("etablissement") && m.etablissement < 0 { m.etablissement = i }
            else if c.contains("retenu") && m.retenu < 0 { m.retenu = i }
            else if c.contains("motif") && m.motif < 0 { m.motif = i }
        }
        return m
    }

    private static func value(_ row: [String], _ idx: Int) -> String {
        (idx >= 0 && idx < row.count) ? row[idx] : ""
    }

    /// Accepte les formats rencontres a l'export : ISO (avec ou sans heure) et
    /// jj/mm/aaaa.
    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "dd/MM/yyyy", "dd/MM/yy", "dd-MM-yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = TimeZone.current
        for f in formats {
            formatter.dateFormat = f
            if let d = formatter.date(from: s) { return d }
        }
        return nil
    }
}
