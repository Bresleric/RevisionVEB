//
//  ServicesSigParCentre.swift
//  RevisionVEB
//
//  Cascade des soldes intermediaires, ventilee par centre de profit.
//
//  Le calcul est isole ici parce que trois vues s'en servent : la synthese de
//  l'exercice, l'evolution pluriannuelle et le controle de parametrage. Les
//  laisser recalculer chacune de leur cote garantirait qu'elles divergent.
//

import Foundation

enum SigParCentre {

    /// Une ligne de la cascade, ventilee.
    struct Ligne: Identifiable {
        let id = UUID()
        let libelle: String
        let freddy: Double
        let liesel: Double
        let dirigeants: Double
        /// Ligne de solde intermediaire, par opposition a un simple poste.
        let solde: Bool

        var total: Double { freddy + liesel + dirigeants }

        /// Montant du centre demande. Le total inclut les dirigeants, qui
        /// n'appartiennent a aucun etablissement mais pesent sur le resultat.
        func montant(_ centre: CentreProfit?) -> Double {
            switch centre {
            case .freddy:     return freddy
            case .liesel:     return liesel
            case .dirigeants: return dirigeants
            default:          return total
            }
        }
    }

    /// Postes de la cascade : libelle, prefixes de comptes, sens.
    ///
    /// Les produits sont crediteurs, donc negatifs en balance : `inverse` les
    /// remet a l'endroit pour qu'ils s'ajoutent au lieu de se retrancher.
    private static let matieres  = ["601", "602", "603", "607", "608", "609"]
    private static let services  = ["611", "612", "613", "614", "615", "616", "617", "618"]
    private static let autresSrv = ["621", "622", "623", "624", "625", "626", "627", "628"]
    private static let impots    = ["631", "632", "633", "634", "635", "636", "637", "638"]
    private static let personnel = ["641", "642", "643", "644", "645", "646", "647", "648"]
    private static let autresChg = ["651", "652", "653", "654", "655", "656", "657", "658"]
    private static let divers    = ["751", "752", "753", "754", "755", "756", "757", "758"]
    private static let dotations = ["681", "682", "683", "684", "685"]
    private static let reprises  = ["791", "792", "793", "794", "795", "796", "797", "798"]
    private static let financier = ["661", "662", "663", "664", "665"]
    private static let prodExcep = ["771", "772", "773", "774", "775", "776", "777", "778"]
    private static let chgExcep  = ["671", "672", "673", "674", "675"]

    private struct Triplet {
        var f = 0.0, l = 0.0, d = 0.0
        static func - (a: Triplet, b: Triplet) -> Triplet { Triplet(f: a.f - b.f, l: a.l - b.l, d: a.d - b.d) }
        static func + (a: Triplet, b: Triplet) -> Triplet { Triplet(f: a.f + b.f, l: a.l + b.l, d: a.d + b.d) }
    }

    /// Construit la cascade a partir des comptes d'un exercice et des regles de
    /// rattachement du dossier.
    ///
    /// Un compte sans regle n'est impute nulle part : l'affecter arbitrairement
    /// donnerait un total credible mais faux. `comptesSansRegle` permet de le
    /// signaler a l'utilisateur.
    static func cascade(comptes: [BalanceAccount],
                        regles: [String: CentreProfitRule]) -> [Ligne] {

        func poste(_ prefixes: [String], inverse: Bool = false) -> Triplet {
            var t = Triplet()
            for compte in comptes where prefixes.contains(where: { compte.accountNumber.hasPrefix($0) }) {
                guard let regle = regles[compte.accountNumber] else { continue }
                let solde = inverse ? -compte.balanceN : compte.balanceN
                if regle.centre == .dirigeants {
                    t.d += solde
                } else {
                    let part = regle.ventile(solde)
                    t.f += part.freddy
                    t.l += part.liesel
                }
            }
            return t
        }

        let ventes  = poste(["70"], inverse: true)
        let mat     = poste(matieres)
        let ach606  = poste(["606"])
        let srv     = poste(services)
        let asrv    = poste(autresSrv)
        let imp     = poste(impots)
        let pers    = poste(personnel)
        let achg    = poste(autresChg)
        let div     = poste(divers, inverse: true)
        let dot     = poste(dotations)
        let rep     = poste(reprises, inverse: true)
        let fin     = poste(financier)
        let pExcep  = poste(prodExcep, inverse: true)
        let cExcep  = poste(chgExcep)

        let marge   = ventes - mat
        let va      = marge - ach606 - srv - asrv
        let ebe     = va - imp - pers - achg
        let expl    = ebe + div - dot + rep
        let courant = expl - fin
        let excep   = pExcep - cExcep
        let net     = courant + excep

        func l(_ libelle: String, _ t: Triplet, solde: Bool = false) -> Ligne {
            Ligne(libelle: libelle, freddy: t.f, liesel: t.l, dirigeants: t.d, solde: solde)
        }

        return [
            l("Ventes", ventes),
            l("– Matières premières", mat),
            l("= Marge brute", marge, solde: true),
            l("– Autres achats (606)", ach606),
            l("– Services externes", srv),
            l("– Autres services", asrv),
            l("= Valeur ajoutée", va, solde: true),
            l("– Impôts et taxes", imp),
            l("– Personnel", pers),
            l("– Autres charges", achg),
            l("= EBE", ebe, solde: true),
            l("+ Produits divers", div),
            l("– Dotations amort.", dot),
            l("+ Reprises amort./prov.", rep),
            l("= Résultat d'exploitation", expl, solde: true),
            l("– Charges financières", fin),
            l("= Résultat courant", courant, solde: true),
            l("= Résultat exceptionnel", excep, solde: true),
            l("= RÉSULTAT NET", net, solde: true)
        ]
    }

    /// Cle de repartition deduite du chiffre d'affaires.
    ///
    /// Une charge commune profite aux deux restaurants a proportion de leur
    /// activite : la part du CA est donc une cle plus defendable qu'un
    /// forfait. Elle se recalcule d'un exercice a l'autre, ce qui la rend
    /// aussi plus fidele qu'une valeur figee une fois pour toutes.
    ///
    /// Seuls les comptes de vente **directement rattaches** a Freddy ou Liesel
    /// entrent dans le calcul. Inclure les ventes communes le rendrait
    /// circulaire : la cle servirait a ventiler ce qui sert a l'etablir.
    ///
    /// Renvoie `nil` si aucune vente n'est rattachee, ou si le total est nul :
    /// mieux vaut pas de cle qu'une cle arbitraire.
    static func cleChiffreAffaires(comptes: [BalanceAccount],
                                   regles: [String: CentreProfitRule])
        -> (partLiesel: Double, caFreddy: Double, caLiesel: Double)? {

        var caF = 0.0, caL = 0.0
        for compte in comptes where compte.accountNumber.hasPrefix("70") {
            guard let regle = regles[compte.accountNumber] else { continue }
            let vente = -compte.balanceN          // les ventes sont crediteuses
            switch regle.centre {
            case .freddy: caF += vente
            case .liesel: caL += vente
            default: break                        // communs et dirigeants exclus
            }
        }

        let total = caF + caL
        guard abs(total) > 0.005 else { return nil }
        return (caL / total * 100, caF, caL)
    }

    /// Comptes de charge ou de produit qu'aucune regle ne rattache.
    static func comptesSansRegle(comptes: [BalanceAccount],
                                 regles: [String: CentreProfitRule]) -> [BalanceAccount] {
        comptes.filter {
            regles[$0.accountNumber] == nil
                && ($0.accountNumber.hasPrefix("6") || $0.accountNumber.hasPrefix("7"))
                && abs($0.balanceN) > 0.005
        }
        .sorted { $0.accountNumber < $1.accountNumber }
    }
}
