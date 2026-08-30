//
//  ServicesPdfDetailCompte.swift
//  RevisionVEB
//
//  Edition PDF du detail d'un compte : factures non parvenues, charges
//  constatees d'avance, elements de rapprochement.
//
//  L'ecran sert a saisir, le PDF sert a transmettre. C'est la piece que
//  reclame l'expert-comptable sur un compte de regularisation : le solde seul
//  ne justifie rien, c'est la liste des factures qui le compose qui fait foi.
//

import Foundation
import AppKit

enum PdfDetailCompte {

    /// Genere le PDF et renvoie son emplacement, ou `nil` si l'ecriture echoue.
    ///
    /// Format paysage : la ventilation comptable (charge, HT, taux, TVA, TTC)
    /// ne tient pas en portrait sans comprimer les libelles au point de les
    /// rendre illisibles.
    static func generer(compte: BalanceAccount,
                        lignes: [ReconItem],
                        cycle: RevisionCycle,
                        exercice: String,
                        dossier: String,
                        ventile: Bool) -> URL? {

        let page = CGRect(x: 0, y: 0, width: 842, height: 595)   // A4 paysage
        let marge: CGFloat = 40

        let dossierSortie = FileManager.default.temporaryDirectory
        let nom = "Detail \(compte.accountNumber) - \(exercice).pdf"
            .replacingOccurrences(of: "/", with: "-")
        let url = dossierSortie.appendingPathComponent(nom)

        var boite = page
        guard let contexte = CGContext(url as CFURL, mediaBox: &boite, nil) else { return nil }

        let colonnes = ventile ? colonnesVentilees : colonnesSimples
        let hauteurLigne: CGFloat = 18
        let hautTableau = page.height - marge - 118      // sous l'en-tete
        let basTableau = marge + 34                      // au-dessus du pied
        let parPage = max(Int((hautTableau - basTableau) / hauteurLigne), 1)
        let pages = max(Int(ceil(Double(lignes.count) / Double(parPage))), 1)

        for numeroPage in 0..<pages {
            contexte.beginPDFPage(nil)
            let graphique = NSGraphicsContext(cgContext: contexte, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphique

            dessinerEntete(compte: compte, lignes: lignes, cycle: cycle,
                           exercice: exercice, dossier: dossier,
                           page: page, marge: marge)

            var y = hautTableau
            dessinerLigneEntete(colonnes: colonnes, x: marge, y: y, largeur: page.width - 2 * marge)
            y -= hauteurLigne

            let debut = numeroPage * parPage
            let fin = min(debut + parPage, lignes.count)
            if debut < fin {
                for ligne in lignes[debut..<fin] {
                    dessinerLigne(ligne, colonnes: colonnes, x: marge, y: y, ventile: ventile)
                    y -= hauteurLigne
                }
            }

            // Le total ne figure que sur la derniere page : repete a chaque
            // page, il se lirait comme un sous-total et induirait en erreur.
            if numeroPage == pages - 1 {
                y -= 4
                dessinerTotal(lignes: lignes, colonnes: colonnes,
                              x: marge, y: y, largeur: page.width - 2 * marge, ventile: ventile)
            }

            dessinerPied(page: page, marge: marge, numero: numeroPage + 1, total: pages)

            NSGraphicsContext.restoreGraphicsState()
            contexte.endPDFPage()
        }

        contexte.closePDF()
        return url
    }

    // MARK: - Colonnes

    private struct Colonne {
        let titre: String
        let largeur: CGFloat
        let aDroite: Bool
    }

    private static let colonnesVentilees: [Colonne] = [
        Colonne(titre: "Libellé / fournisseur", largeur: 200, aDroite: false),
        Colonne(titre: "Compte de charge",      largeur: 110, aDroite: false),
        Colonne(titre: "HT",                    largeur: 90,  aDroite: true),
        Colonne(titre: "Taux",                  largeur: 50,  aDroite: true),
        Colonne(titre: "TVA",                   largeur: 90,  aDroite: true),
        Colonne(titre: "TTC",                   largeur: 90,  aDroite: true),
        Colonne(titre: "Pièce justificative",   largeur: 132, aDroite: false)
    ]

    private static let colonnesSimples: [Colonne] = [
        Colonne(titre: "Libellé",               largeur: 380, aDroite: false),
        Colonne(titre: "Montant",               largeur: 120, aDroite: true),
        Colonne(titre: "Pièce justificative",   largeur: 262, aDroite: false)
    ]

    // MARK: - Dessin

    private static func dessinerEntete(compte: BalanceAccount, lignes: [ReconItem],
                                       cycle: RevisionCycle, exercice: String, dossier: String,
                                       page: CGRect, marge: CGFloat) {
        let intitule = compte.accountLabel.isEmpty ? compte.accountCode : compte.accountLabel
        var y = page.height - marge - 16

        texte("\(dossier) — Exercice \(exercice)", x: marge, y: y, taille: 10, gris: true)
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "dd/MM/yyyy"
        texte("Édité le \(df.string(from: Date()))",
              x: page.width - marge - 120, y: y, taille: 10, gris: true, largeur: 120, aDroite: true)
        y -= 26

        texte("Détail du compte \(compte.accountNumber)", x: marge, y: y, taille: 16, gras: true)
        y -= 18
        texte(intitule, x: marge, y: y, taille: 12)
        y -= 14
        texte("Cycle \(cycle.letter) — \(cycle.shortName)", x: marge, y: y, taille: 10, gris: true)
        y -= 24

        // Bandeau de synthese : c'est ce que le lecteur regarde en premier.
        let total = lignes.reduce(0) { $0 + $1.montant }
        let ecart = compte.balanceN - total
        let concordant = abs(ecart) < 0.5

        chiffre("Solde en balance", formatEuro(compte.balanceN), x: marge, y: y)
        chiffre("Total détaillé", formatEuro(total), x: marge + 180, y: y)
        chiffre("Écart", formatEuroSigned(ecart), x: marge + 360, y: y,
                couleur: concordant ? NSColor.systemGreen : NSColor.systemRed)
        chiffre("Lignes", "\(lignes.count)", x: marge + 540, y: y)
    }

    private static func dessinerLigneEntete(colonnes: [Colonne], x: CGFloat, y: CGFloat, largeur: CGFloat) {
        NSColor(white: 0.90, alpha: 1).setFill()
        NSRect(x: x, y: y - 3, width: largeur, height: 16).fill()

        var curseur = x + 3
        for c in colonnes {
            texte(c.titre, x: curseur, y: y, taille: 8, gras: true,
                  largeur: c.largeur - 6, aDroite: c.aDroite)
            curseur += c.largeur
        }
    }

    private static func dessinerLigne(_ ligne: ReconItem, colonnes: [Colonne],
                                      x: CGFloat, y: CGFloat, ventile: Bool) {
        let valeurs: [String] = ventile
            ? [ligne.libelle,
               ligne.compteCharge,
               formatEuro(ligne.montantHT),
               ligne.tauxTva == 0 ? "—" : String(format: "%g %%", ligne.tauxTva),
               formatEuro(ligne.montantTva),
               formatEuro(ligne.montant),
               ligne.docName]
            : [ligne.libelle,
               formatEuro(ligne.montant),
               ligne.docName]

        var curseur = x + 3
        for (i, c) in colonnes.enumerated() {
            // Une ligne sans pièce se signale d'elle-même : c'est le premier
            // point que relèvera l'expert-comptable.
            let manquante = c.titre.hasPrefix("Pièce") && valeurs[i].isEmpty
            texte(manquante ? "— absente —" : valeurs[i],
                  x: curseur, y: y, taille: 8,
                  gris: manquante,
                  largeur: c.largeur - 6, aDroite: c.aDroite)
            curseur += c.largeur
        }
    }

    private static func dessinerTotal(lignes: [ReconItem], colonnes: [Colonne],
                                      x: CGFloat, y: CGFloat, largeur: CGFloat, ventile: Bool) {
        NSColor(white: 0.35, alpha: 1).setFill()
        NSRect(x: x, y: y + 14, width: largeur, height: 0.8).fill()

        let valeurs: [String] = ventile
            ? ["TOTAL", "",
               formatEuro(lignes.reduce(0) { $0 + $1.montantHT }),
               "",
               formatEuro(lignes.reduce(0) { $0 + $1.montantTva }),
               formatEuro(lignes.reduce(0) { $0 + $1.montant }),
               ""]
            : ["TOTAL",
               formatEuro(lignes.reduce(0) { $0 + $1.montant }),
               ""]

        var curseur = x + 3
        for (i, c) in colonnes.enumerated() {
            texte(valeurs[i], x: curseur, y: y, taille: 9, gras: true,
                  largeur: c.largeur - 6, aDroite: c.aDroite)
            curseur += c.largeur
        }
    }

    private static func dessinerPied(page: CGRect, marge: CGFloat, numero: Int, total: Int) {
        texte("RevisionVEB — pièce de révision", x: marge, y: marge - 6, taille: 8, gris: true)
        texte("Page \(numero) / \(total)",
              x: page.width - marge - 100, y: marge - 6, taille: 8, gris: true,
              largeur: 100, aDroite: true)
    }

    // MARK: - Primitives

    private static func texte(_ contenu: String, x: CGFloat, y: CGFloat,
                              taille: CGFloat, gras: Bool = false, gris: Bool = false,
                              largeur: CGFloat? = nil, aDroite: Bool = false) {
        let paragraphe = NSMutableParagraphStyle()
        paragraphe.alignment = aDroite ? .right : .left
        paragraphe.lineBreakMode = .byTruncatingTail

        let attributs: [NSAttributedString.Key: Any] = [
            .font: gras ? NSFont.boldSystemFont(ofSize: taille) : NSFont.systemFont(ofSize: taille),
            .foregroundColor: gris ? NSColor(white: 0.45, alpha: 1) : NSColor.black,
            .paragraphStyle: paragraphe
        ]
        let cadre = NSRect(x: x, y: y, width: largeur ?? 400, height: taille + 5)
        (contenu as NSString).draw(in: cadre, withAttributes: attributs)
    }

    private static func chiffre(_ libelle: String, _ valeur: String, x: CGFloat, y: CGFloat,
                                couleur: NSColor = .black) {
        texte(libelle, x: x, y: y + 12, taille: 8, gris: true, largeur: 170)
        let paragraphe = NSMutableParagraphStyle()
        paragraphe.lineBreakMode = .byTruncatingTail
        let attributs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: couleur,
            .paragraphStyle: paragraphe
        ]
        (valeur as NSString).draw(in: NSRect(x: x, y: y - 2, width: 170, height: 17),
                                  withAttributes: attributs)
    }
}
