import Foundation
import SwiftData

extension UUID {
    /// Identifiant au format PostgreSQL, en minuscules.
    ///
    /// `uuidString` renvoie des majuscules alors que PostgreSQL stocke et
    /// relit les uuid en minuscules. Comparer les deux directement ne
    /// correspond jamais : chaque enregistrement était donc envoyé en POST au
    /// lieu de PATCH, et rejeté pour clé dupliquée. Aucune mise à jour n'a
    /// jamais pu remonter sur Supabase avant cette correction.
    var pg: String { uuidString.lowercased() }
}

@MainActor
class SupabaseSync {
    static let shared = SupabaseSync()

    let baseURL: String
    let anonKey: String
    private var isSyncing = false
    private var hasFullSyncedThisSession = false

    init() {
        self.baseURL = SupabaseConfig.url
        self.anonKey = SupabaseConfig.anonKey

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Authorization": "Bearer \(SupabaseConfig.anonKey)",
            "apikey": SupabaseConfig.anonKey,
            "Content-Type": "application/json",
            "Prefer": "return=minimal"
        ]
        self.session = URLSession(configuration: config)

        print("📱 Supabase configuré: \(baseURL)")
    }

    /// Session unique et réutilisée.
    ///
    /// C'était auparavant une propriété calculée : chaque requête créait une
    /// URLSession neuve, soit ~700 par synchronisation, chacune ouvrant son
    /// propre pool de connexions sans jamais le refermer. D'où le déluge de
    /// messages nw_connection / tcp_output dans la console.
    let session: URLSession

    // MARK: - Dossiers Sync (Working)

    func syncDossiers(from container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            let dossiers = try context.fetch(FetchDescriptor<Dossier>())

            guard !dossiers.isEmpty else {
                print("ℹ️ Aucun dossier à synchroniser")
                return
            }

            print("📤 Dossiers: \(dossiers.count)")
            await bulkUpsert(tableName: "dossiers", rows: dossiers.map { d in
                [
                    "id": d.id.pg,
                    "nom": d.nom,
                    "ordre": d.ordre
                ]
            })
        } catch {
            print("❌ Erreur fetch: \(error)")
        }
    }

    func syncExercices(from container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            let exercices = try context.fetch(FetchDescriptor<Exercice>())
            guard !exercices.isEmpty else { return }

            print("📤 Exercices: \(exercices.count)")
            await bulkUpsert(tableName: "exercices", rows: exercices.map { e in
                [
                    "id": e.id.pg,
                    "dossier_id": e.dossierID.pg,
                    "libelle": e.libelle,
                    "date_cloture": e.dateCloture.ISO8601Format(),
                    "cree_le": e.creeLe.ISO8601Format()
                ]
            })
        } catch {
            print("❌ Erreur exercices: \(error)")
        }
    }

    func syncBalanceAccounts(from container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            let accounts = try context.fetch(FetchDescriptor<BalanceAccount>())
            guard !accounts.isEmpty else { return }

            print("📤 Balance Accounts: \(accounts.count)")
            await bulkUpsert(tableName: "balance_accounts",
                             onConflict: "exercice_id,account_number",
                             rows: accounts.map { a in
                [
                    "id": a.id.pg,
                    "account_number": a.accountNumber,
                    "account_code": a.accountCode,
                    "account_label": a.accountLabel,
                    "debit": a.debit,
                    "credit": a.credit,
                    "balance_n": a.balanceN,
                    "balance_n_minus_1": a.balanceNMinus1,
                    "restaurant": a.restaurant.rawValue,
                    "exercice_id": a.exerciceID.pg,
                    "source_file": a.sourceFile,
                    "import_date": a.importDate.ISO8601Format()
                ]
            })
        } catch {
            print("❌ Erreur balance_accounts: \(error)")
        }
    }

    func syncImmoAssets(from container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            let assets = try context.fetch(FetchDescriptor<ImmoAsset>())
            guard !assets.isEmpty else { return }

            print("📤 Immo Assets: \(assets.count)")
            await bulkUpsert(tableName: "immo_assets", rows: assets.map { a in
                [
                    "id": a.id.pg,
                    "exercice_id": a.exerciceID.pg,
                    "compte": a.compte,
                    "numero_immo": a.numeroImmo,
                    "libelle": a.libelle,
                    "montant_ht": isValidJSON(a.montantHT) ? a.montantHT : 0.0,
                    "date_acquisition": a.dateAcquisition.ISO8601Format(),
                    "taux_amort": isValidJSON(a.tauxAmort) ? a.tauxAmort : 0.0,
                    "amort_anterieur": isValidJSON(a.amortAnterieur) ? a.amortAnterieur : 0.0,
                    "amort_exercice": isValidJSON(a.amortExercice) ? a.amortExercice : 0.0,
                    "ordre": a.ordre
                ]
            })
        } catch {
            print("❌ Erreur immo_assets: \(error)")
        }
    }

    // MARK: - Points en suspens

    /// Envoie les points en suspens locaux vers Supabase.
    func syncPendingItems(from container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            let items = try context.fetch(FetchDescriptor<PendingItem>())
            guard !items.isEmpty else { return }

            print("📤 Points en suspens: \(items.count)")
            await bulkUpsert(tableName: "points_en_suspens", rows: items.map { p in
                var payload: [String: Any] = [
                    "id": p.id.pg,
                    "exercice_id": p.exerciceID.pg,
                    "cycle_raw": p.cycleRaw,
                    "account_number": p.accountNumber,
                    "titre": p.titre,
                    "detail": p.detail,
                    "type_raw": p.typeRaw,
                    "statut_raw": p.statutRaw,
                    "priorite_raw": p.prioriteRaw,
                    "responsable": p.responsable,
                    "cree_le": p.creeLe.ISO8601Format(),
                    "updated_at": p.updatedAt.ISO8601Format()
                ]
                payload["echeance"] = p.echeance?.ISO8601Format() ?? NSNull()
                return payload
            })
        } catch {
            print("❌ Erreur points en suspens: \(error)")
        }
    }

    /// Charge les points en suspens depuis Supabase. Fusion par id : le plus
    /// récemment modifié (updated_at) gagne, pour que les deux Macs convergent.
    func loadPendingItemsFromSupabase(using context: ModelContext) async {
        do {
            let url = URL(string: "\(baseURL)/rest/v1/points_en_suspens")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            guard http.statusCode == 200 else {
                if http.statusCode == 404 {
                    print("  ℹ️ Table points_en_suspens absente sur Supabase (module local uniquement)")
                } else {
                    print("  ⚠️ Points en suspens: HTTP \(http.statusCode)")
                }
                return
            }
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

            let locals = (try? context.fetch(FetchDescriptor<PendingItem>())) ?? []
            var byID = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            var inserted = 0
            var updated = 0

            for row in jsonArray {
                guard let idStr = row["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let exerciceIdStr = row["exercice_id"] as? String,
                      let exerciceId = UUID(uuidString: exerciceIdStr),
                      let cycleRaw = row["cycle_raw"] as? String else { continue }

                let remoteUpdated = (row["updated_at"] as? String)
                    .flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date.distantPast

                let target: PendingItem
                if let local = byID[id] {
                    // La version locale est plus récente : elle sera repoussée au
                    // prochain envoi, on ne l'écrase pas.
                    guard remoteUpdated > local.updatedAt else { continue }
                    target = local
                    updated += 1
                } else {
                    let fresh = PendingItem(exerciceID: exerciceId, cycleRaw: cycleRaw)
                    fresh.id = id
                    context.insert(fresh)
                    byID[id] = fresh
                    target = fresh
                    inserted += 1
                }

                target.exerciceID = exerciceId
                target.cycleRaw = cycleRaw
                target.accountNumber = row["account_number"] as? String ?? ""
                target.titre = row["titre"] as? String ?? ""
                target.detail = row["detail"] as? String ?? ""
                target.typeRaw = row["type_raw"] as? String ?? PendingKind.commentaire.rawValue
                target.statutRaw = row["statut_raw"] as? String ?? PendingStatus.ouvert.rawValue
                target.prioriteRaw = row["priorite_raw"] as? String ?? PendingPriority.normale.rawValue
                target.responsable = row["responsable"] as? String ?? ""
                target.echeance = (row["echeance"] as? String)
                    .flatMap { ISO8601DateFormatter().date(from: $0) }
                target.creeLe = (row["cree_le"] as? String)
                    .flatMap { ISO8601DateFormatter().date(from: $0) } ?? target.creeLe
                target.updatedAt = remoteUpdated
            }

            if inserted > 0 || updated > 0 {
                try context.save()
            }
            print("  ✅ Points en suspens: \(inserted) ajoutés, \(updated) mis à jour")
        } catch {
            print("  ⚠️ Erreur chargement points_en_suspens: \(error.localizedDescription)")
        }
    }

    /// Supprime un point en suspens sur Supabase (appelé après suppression locale)
    /// afin qu'il ne réapparaisse pas à la synchronisation suivante.
    func deletePendingItemRemote(id: UUID) async {
        do {
            let url = URL(string: "\(baseURL)/rest/v1/points_en_suspens?id=eq.\(id.pg)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               ![200, 204, 404].contains(http.statusCode) {
                print("⚠️ Suppression point en suspens: HTTP \(http.statusCode)")
            }
        } catch {
            print("⚠️ Suppression point en suspens: \(error.localizedDescription)")
        }
    }

    func syncSoldesIntermediales(from container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            let soldes = try context.fetch(FetchDescriptor<SoldesIntermedialres>())
            guard !soldes.isEmpty else { return }

            print("📤 Soldes Intermédiaires: \(soldes.count)")
            // Un exemplaire par exercice : un lot ne peut pas viser deux fois
            // la même clef primaire.
            var seen = Set<UUID>()
            let uniques = soldes.filter { seen.insert($0.exerciceID).inserted }

            await bulkUpsert(tableName: "soldes_intermediares", rows: uniques.map { s in
                [
                    // Un seul jeu de SIG par exercice : identifiant dérivé de
                    // l'exercice, pour que les deux Macs visent la même ligne
                    // au lieu d'en créer chacun une.
                    "id": Self.stableID(s.exerciceID.pg).pg,
                    "exercice_id": s.exerciceID.pg,
                    "marge_brute": s.margeBrute,
                    "production_exercice": s.productionExercice,
                    "valeur_ajoutee": s.valeurAjoutee,
                    "ebe_sig": s.ebeSig,
                    "resultat_exploitation": s.resultatExploitation,
                    "resultat_financier": s.resultatFinancier,
                    "resultat_courant": s.resultatCourant,
                    "resultat_exceptionnel": s.resultatExceptionnel,
                    "resultat_net": s.resultatNet,
                    "marge_brute_n1": s.margeBruteN1,
                    "production_exercice_n1": s.productionExerciceN1,
                    "valeur_ajoutee_n1": s.valeurAjouteeN1,
                    "ebe_sig_n1": s.ebeSigN1,
                    "resultat_exploitation_n1": s.resultatExploitationN1,
                    "resultat_financier_n1": s.resultatFinancierN1,
                    "resultat_courant_n1": s.resultatCourantN1,
                    "resultat_exceptionnel_n1": s.resultatExceptionnelN1,
                    "resultat_net_n1": s.resultatNetN1,
                    "marge_brute_n2": s.margeBruteN2,
                    "production_exercice_n2": s.productionExerciceN2,
                    "valeur_ajoutee_n2": s.valeurAjouteeN2,
                    "ebe_sig_n2": s.ebeSigN2,
                    "resultat_exploitation_n2": s.resultatExploitationN2,
                    "resultat_financier_n2": s.resultatFinancierN2,
                    "resultat_courant_n2": s.resultatCourantN2,
                    "resultat_exceptionnel_n2": s.resultatExceptionnelN2,
                    "resultat_net_n2": s.resultatNetN2,
                    "ca_ht": s.caHT,
                    "couts_directs": s.coutsDirects,
                    "autres_achats": s.autresAchats,
                    "services_externes": s.servicesExternes,
                    "autres_services": s.autresServices,
                    "production_vendue": s.productionVendue,
                    "production_stockee": s.productionStockee,
                    "production_immobilisee": s.productionImmobilisee,
                    "consommations_externes": s.consommationsExternes,
                    "impots_et_taxes": s.impotsEtTaxes,
                    "frais_personnel": s.fraisPersonnel,
                    "autres_charges_exploitation": s.autresChargesExploitation,
                    "produits_divers": s.produitsDivers,
                    "dotations": s.dotations,
                    "reprises": s.reprises,
                    "produits_financiers": s.produitsFinanciers,
                    "charges_financieres": s.chargesFinancieres,
                    "produits_exceptionnels": s.produitsExceptionnels,
                    "charges_exceptionnels": s.chargesExceptionnels,
                    "impot_sur_benefices": s.impotSurBenefices,
                    "ca_ht_n1": s.caHTN1,
                    "couts_directs_n1": s.coutsDirectsN1,
                    "autres_achats_n1": s.autresAchatsN1,
                    "services_externes_n1": s.servicesExternesN1,
                    "autres_services_n1": s.autresServicesN1,
                    "impots_et_taxes_n1": s.impotsEtTaxesN1,
                    "frais_personnel_n1": s.fraisPersonnelN1,
                    "autres_charges_exploitation_n1": s.autresChargesExploitationN1,
                    "produits_divers_n1": s.produitsDiversN1,
                    "dotations_n1": s.dotationsN1,
                    "reprises_n1": s.reprisesN1,
                    "charges_financieres_n1": s.chargesFinanciereN1,
                    "produits_exceptionnels_n1": s.produitsExceptionnelsN1,
                    "charges_exceptionnels_n1": s.chargesExceptionnelsN1
                ]

            })
        } catch {
            print("❌ Erreur soldes_intermediares: \(error)")
        }
    }

    // MARK: - Helpers

    private func isValidJSON(_ value: Double) -> Bool {
        return !value.isNaN && !value.isInfinite
    }

    /// Envoie une collection en quelques requêtes au lieu d'une par ligne.
    ///
    /// PostgREST accepte un tableau d'objets et, avec `resolution=merge-duplicates`,
    /// insère ou met à jour selon la clé primaire. Une balance de 600 comptes
    /// passait par 600 allers-retours séquentiels — d'où les dizaines de secondes
    /// avant que les données n'apparaissent. Elle tient maintenant en une poignée
    /// de requêtes, et le choix POST/PATCH disparaît avec les conflits de clé.
    /// `onConflict` nomme les colonnes de la contrainte d'unicite a viser.
    ///
    /// Par defaut PostgREST resout les conflits sur la cle primaire. Quand une
    /// table porte en plus une cle logique — un compte par exercice, une
    /// assiette par mois et par etablissement — deux lignes peuvent designer le
    /// meme objet sous deux identifiants differents : l'une vient d'un import
    /// ancien, l'autre d'un import recent. L'envoi echouait alors en 23505.
    /// En visant la cle logique, la ligne existante est mise a jour.
    func bulkUpsert(tableName: String, onConflict: String? = nil, rows: [[String: Any]]) async {
        guard !rows.isEmpty else { return }
        let chunkSize = 250

        let suffixe = onConflict.map { "?on_conflict=\($0)" } ?? ""

        for start in stride(from: 0, to: rows.count, by: chunkSize) {
            let chunk = Array(rows[start..<min(start + chunkSize, rows.count)])
            var request = URLRequest(url: URL(string: "\(baseURL)/rest/v1/\(tableName)\(suffixe)")!)
            request.httpMethod = "POST"
            request.setValue("return=minimal,resolution=merge-duplicates",
                             forHTTPHeaderField: "Prefer")
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: chunk)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      ![200, 201, 204].contains(http.statusCode) else { continue }
                SyncDiagnostics.record(table: tableName,
                                       status: http.statusCode,
                                       body: String(data: data, encoding: .utf8) ?? "")
            } catch {
                print("❌ Envoi \(tableName): \(error.localizedDescription)")
            }
        }
    }

    func upsertRecord(tableName: String, record: [String: Any], id: String, existingIds: Set<String>) async {
        let url = URL(string: "\(baseURL)/rest/v1/\(tableName)")!
        var request = URLRequest(url: url)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: record)

            let key = id.lowercased()
            if existingIds.contains(key) {
                request.httpMethod = "PATCH"
                request.url = URL(string: "\(baseURL)/rest/v1/\(tableName)?id=eq.\(key)")!
            } else {
                request.httpMethod = "POST"
            }

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  ![200, 201, 204].contains(httpResponse.statusCode) else { return }

            // Un 409 n'est pas anodin : c'est soit une clé déjà présente
            // (23505), soit une clé étrangère manquante (23503). Le corps de la
            // réponse porte le code PostgreSQL, seul moyen de faire la
            // différence — on le remonte au lieu de masquer l'erreur.
            let detail = String(data: data, encoding: .utf8) ?? ""
            SyncDiagnostics.record(table: tableName,
                                   status: httpResponse.statusCode,
                                   body: detail)
        } catch {
            print("❌ Erreur upsert: \(error.localizedDescription)")
        }
    }

    /// Identifiants déjà présents dans une table, paginés.
    ///
    /// PostgREST plafonne le nombre de lignes par réponse. Sans pagination, une
    /// table de plus de 1000 lignes renverrait une liste tronquée : les
    /// enregistrements manquants seraient alors envoyés en POST au lieu de
    /// PATCH, et rejetés en 409 pour clé dupliquée.
    func getTableIds(tableName: String) async -> Set<String> {
        var ids = Set<String>()
        let pageSize = 1000
        var offset = 0

        while true {
            do {
                let url = URL(string: "\(baseURL)/rest/v1/\(tableName)?select=id&limit=\(pageSize)&offset=\(offset)")!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else { return ids }

                ids.formUnion(rows.compactMap { ($0["id"] as? String)?.lowercased() })
                if rows.count < pageSize { return ids }
                offset += pageSize
            } catch {
                print("⚠️ Erreur fetch IDs \(tableName): \(error.localizedDescription)")
                return ids
            }
        }
    }

    // MARK: - Load from Supabase

    func loadDossiersFromSupabase(to container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            print("📥 Dossiers: chargement...")

            let url = URL(string: "\(baseURL)/rest/v1/dossiers")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    print("  JSON reçu: \(jsonArray.count) dossiers")
                    guard !jsonArray.isEmpty else { return }

                    // Charger les IDs locaux pour éviter les doublons
                    var localIds = Set<UUID>()
                    do {
                        let locals = try context.fetch(FetchDescriptor<Dossier>())
                        localIds = Set(locals.map { $0.id })
                    } catch {
                        print("⚠️ Erreur lecture dossiers locaux: \(error)")
                    }

                    var loaded = 0
                    var failed = 0
                    for (idx, item) in jsonArray.enumerated() {
                        guard let idStr = item["id"] as? String else {
                            print("  ✗ Item \(idx): pas d'id")
                            failed += 1
                            continue
                        }
                        guard let id = UUID(uuidString: idStr) else {
                            print("  ✗ Item \(idx): UUID invalide '\(idStr)'")
                            failed += 1
                            continue
                        }
                        guard let nom = item["nom"] as? String else {
                            print("  ✗ Item \(idx): pas de nom")
                            failed += 1
                            continue
                        }

                        // Passer si déjà local
                        if localIds.contains(id) {
                            print("  ⊘ \(nom) (déjà local)")
                            continue
                        }

                        let ordre = item["ordre"] as? Int ?? 0
                        print("  ✅ + \(nom)")
                        let dossier = Dossier(id: id, nom: nom, ordre: ordre)
                        context.insert(dossier)
                        loaded += 1
                    }
                    if loaded > 0 {
                        print("  Sauvegarde...")
                        try context.save()
                    }
                    print("✅ \(loaded) dossiers chargés (+ \(localIds.count) déjà locaux)")
                }
            }
        } catch {
            print("⚠️ Erreur chargement dossiers: \(error.localizedDescription)")
        }
    }

    func loadExercicesFromSupabase(to container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            print("📥 Exercices: chargement...")

            let url = URL(string: "\(baseURL)/rest/v1/exercices")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    print("  JSON reçu: \(jsonArray.count) exercices")
                    guard !jsonArray.isEmpty else { return }

                    var loaded = 0
                    for (idx, item) in jsonArray.enumerated() {
                        guard let idStr = item["id"] as? String,
                              let id = UUID(uuidString: idStr) else {
                            print("    ✗ Item \(idx): UUID invalide")
                            continue
                        }
                        guard let dossierIdStr = item["dossier_id"] as? String,
                              let dossierId = UUID(uuidString: dossierIdStr) else {
                            print("    ✗ Item \(idx): dossier_id invalide")
                            continue
                        }
                        guard let libelle = item["libelle"] as? String else {
                            print("    ✗ Item \(idx): libelle manquant")
                            continue
                        }

                        let dateCloture = (item["date_cloture"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
                        let creeLe = (item["cree_le"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

                        print("    ✅ \(libelle)")
                        let exercice = Exercice(id: id, dossierID: dossierId, libelle: libelle, dateCloture: dateCloture, creeLe: creeLe)
                        context.insert(exercice)
                        loaded += 1
                    }
                    if loaded > 0 {
                        print("  Sauvegarde \(loaded) exercices...")
                        try context.save()
                    }
                    print("✅ \(loaded) exercices chargés")
                }
            }
        } catch {
            print("❌ Erreur chargement exercices: \(error)")
        }
    }

    /// Lit une table entiere, page par page.
    ///
    /// PostgREST plafonne une reponse a 1000 lignes. Sans pagination, une table
    /// plus grande renvoyait une tranche arbitraire : c'est ainsi qu'un Mac
    /// pouvait recevoir un jeu de comptes incomplet et incoherent.
    func fetchAllRows(_ table: String, label: String) async -> [[String: Any]] {
        var toutes: [[String: Any]] = []
        let taille = 1000
        var offset = 0

        while true {
            do {
                let url = URL(string: "\(baseURL)/rest/v1/\(table)?limit=\(taille)&offset=\(offset)")!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let page = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else { return toutes }

                toutes += page
                if page.count < taille { return toutes }
                offset += taille
            } catch {
                print("  ⚠️ \(label): \(error.localizedDescription)")
                return toutes
            }
        }
    }

    /// Ne garde qu'une ligne par (exercice, compte) : la plus recente.
    ///
    /// A egalite de date d'import, l'identifiant le plus grand tranche, pour que
    /// les deux Macs retiennent la meme.
    private func dedupeRows(_ rows: [[String: Any]]) -> [[String: Any]] {
        var best: [String: [String: Any]] = [:]
        for item in rows {
            guard let compte = item["account_number"] as? String,
                  let exercice = item["exercice_id"] as? String else { continue }
            let key = "\(exercice)|\(compte)"
            guard let courant = best[key] else { best[key] = item; continue }

            let dateNouvelle = (item["import_date"] as? String)
                .flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date.distantPast
            let dateCourante = (courant["import_date"] as? String)
                .flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date.distantPast
            let idNouveau = (item["id"] as? String) ?? ""
            let idCourant = (courant["id"] as? String) ?? ""

            if (dateNouvelle, idNouveau) > (dateCourante, idCourant) { best[key] = item }
        }
        return Array(best.values)
    }

    func loadBalanceAccountsFromSupabase(to container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            print("📥 Balance Accounts: chargement...")

            let toutes = await fetchAllRows("balance_accounts", label: "Balance Accounts")
            guard !toutes.isEmpty else { return }

            // Un compte ne doit exister qu'une fois par exercice, quel que soit
            // le nombre de generations restees sur Supabase.
            let jsonArray = dedupeRows(toutes)
            if toutes.count != jsonArray.count {
                print("  🧹 \(toutes.count - jsonArray.count) doublons distants ignorés")
            }

                    // Charger les IDs locaux
                    var localIds = Set<UUID>()
                    do {
                        let locals = try context.fetch(FetchDescriptor<BalanceAccount>())
                        localIds = Set(locals.map { $0.id })
                    } catch {
                        print("⚠️ Erreur lecture balance_accounts locaux: \(error)")
                    }

                    // Comptes deja presents localement, par cle logique : sans ce
                    // filtre, une ligne distante d'une ancienne generation
                    // reintroduit un doublon sous un autre identifiant.
                    let clesLocales = Set(((try? context.fetch(FetchDescriptor<BalanceAccount>())) ?? [])
                        .map { "\($0.exerciceID.uuidString)|\($0.accountNumber)" })

                    var loaded = 0
                    for item in jsonArray {
                        guard let idStr = item["id"] as? String,
                              let id = UUID(uuidString: idStr),
                              let accountNumber = item["account_number"] as? String,
                              let exerciceIdStr = item["exercice_id"] as? String,
                              let exerciceId = UUID(uuidString: exerciceIdStr) else { continue }

                        if localIds.contains(id) { continue }
                        if clesLocales.contains("\(exerciceIdStr)|\(accountNumber)") { continue }

                        let debit = (item["debit"] as? NSNumber)?.doubleValue ?? 0.0
                        let credit = (item["credit"] as? NSNumber)?.doubleValue ?? 0.0
                        let balanceN = (item["balance_n"] as? NSNumber)?.doubleValue ?? 0.0
                        let balanceNMinus1 = (item["balance_n_minus_1"] as? NSNumber)?.doubleValue ?? 0.0

                        let restaurantStr = item["restaurant"] as? String ?? "Freddy"
                        let restaurant = Restaurant(rawValue: restaurantStr) ?? .freddy

                        let account = BalanceAccount(
                            id: id,
                            accountNumber: accountNumber,
                            accountCode: item["account_code"] as? String ?? "",
                            accountLabel: item["account_label"] as? String ?? "",
                            debit: debit,
                            credit: credit,
                            balanceN: balanceN,
                            balanceNMinus1: balanceNMinus1,
                            restaurant: restaurant,
                            exerciceID: exerciceId,
                            sourceFile: item["source_file"] as? String ?? "",
                            importDate: (item["import_date"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
                        )
                        context.insert(account)
                        loaded += 1
                    }
                    if loaded > 0 {
                        try context.save()
                    }
                    print("✅ \(loaded) balance accounts chargés (+ \(localIds.count) déjà locaux)")
        } catch {
            print("⚠️ Erreur chargement balance_accounts: \(error.localizedDescription)")
        }
    }

    func loadImmoAssetsFromSupabase(to container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            print("📥 Immo Assets: chargement...")

            let url = URL(string: "\(baseURL)/rest/v1/immo_assets")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    guard !jsonArray.isEmpty else { return }

                    // Charger les IDs locaux
                    var localIds = Set<UUID>()
                    do {
                        let locals = try context.fetch(FetchDescriptor<ImmoAsset>())
                        localIds = Set(locals.map { $0.id })
                    } catch {
                        print("⚠️ Erreur lecture immo_assets locaux: \(error)")
                    }

                    var loaded = 0
                    for item in jsonArray {
                        guard let idStr = item["id"] as? String,
                              let id = UUID(uuidString: idStr),
                              let exerciceIdStr = item["exercice_id"] as? String,
                              let exerciceId = UUID(uuidString: exerciceIdStr),
                              let compte = item["compte"] as? String else { continue }

                        if localIds.contains(id) {
                            continue
                        }

                        let dateStr = item["date_acquisition"] as? String
                        let dateAcquisition = dateStr.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

                        let montantHT = (item["montant_ht"] as? NSNumber)?.doubleValue ?? 0.0
                        let tauxAmort = (item["taux_amort"] as? NSNumber)?.doubleValue ?? 0.0
                        let amortAnterieur = (item["amort_anterieur"] as? NSNumber)?.doubleValue ?? 0.0
                        let amortExercice = (item["amort_exercice"] as? NSNumber)?.doubleValue ?? 0.0

                        let asset = ImmoAsset(
                            id: id,
                            exerciceID: exerciceId,
                            compte: compte,
                            numeroImmo: item["numero_immo"] as? String ?? "",
                            libelle: item["libelle"] as? String ?? "",
                            montantHT: montantHT,
                            dateAcquisition: dateAcquisition,
                            tauxAmort: tauxAmort,
                            amortAnterieur: amortAnterieur,
                            amortExercice: amortExercice,
                            ordre: item["ordre"] as? Int ?? 0
                        )
                        context.insert(asset)
                        loaded += 1
                    }
                    if loaded > 0 {
                        try context.save()
                    }
                    print("✅ \(loaded) immo assets chargés (+ \(localIds.count) déjà locaux)")
                }
            }
        } catch {
            print("⚠️ Erreur chargement immo_assets: \(error.localizedDescription)")
        }
    }

    func loadSoldesIntermedialresFromSupabase(using context: ModelContext) async {
        do {
            print("📥 Soldes Intermédiaires: chargement...")

            let url = URL(string: "\(baseURL)/rest/v1/soldes_intermediares")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    guard !jsonArray.isEmpty else { return }

                    // Charger les IDs locaux
                    // Indexé par exercice : les SIG sont recalculés localement depuis
                    // la balance, un exemplaire par exercice suffit.
                    var localExercices = Set<UUID>()
                    do {
                        let locals = try context.fetch(FetchDescriptor<SoldesIntermedialres>())
                        localExercices = Set(locals.map { $0.exerciceID })
                    } catch {
                        print("⚠️ Erreur lecture soldes_intermediares locaux: \(error)")
                    }

                    var loaded = 0
                    for item in jsonArray {
                        guard let idStr = item["id"] as? String,
                              let id = UUID(uuidString: idStr),
                              let exerciceIdStr = item["exercice_id"] as? String,
                              let exerciceId = UUID(uuidString: exerciceIdStr) else { continue }

                        if localExercices.contains(exerciceId) { continue }
                        localExercices.insert(exerciceId)

                        // Extract values in separate steps to avoid compiler type-checking issues
                        let d0 = (item["marge_brute"] as? NSNumber)?.doubleValue ?? 0.0
                        let d1 = (item["production_exercice"] as? NSNumber)?.doubleValue ?? 0.0
                        let d2 = (item["valeur_ajoutee"] as? NSNumber)?.doubleValue ?? 0.0
                        let d3 = (item["ebe_sig"] as? NSNumber)?.doubleValue ?? 0.0
                        let d4 = (item["resultat_exploitation"] as? NSNumber)?.doubleValue ?? 0.0
                        let d5 = (item["resultat_financier"] as? NSNumber)?.doubleValue ?? 0.0
                        let d6 = (item["resultat_courant"] as? NSNumber)?.doubleValue ?? 0.0
                        let d7 = (item["resultat_exceptionnel"] as? NSNumber)?.doubleValue ?? 0.0
                        let d8 = (item["resultat_net"] as? NSNumber)?.doubleValue ?? 0.0
                        let d9 = (item["marge_brute_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d10 = (item["production_exercice_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d11 = (item["valeur_ajoutee_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d12 = (item["ebe_sig_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d13 = (item["resultat_exploitation_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d14 = (item["resultat_financier_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d15 = (item["resultat_courant_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d16 = (item["resultat_exceptionnel_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d17 = (item["resultat_net_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d18 = (item["marge_brute_n2"] as? NSNumber)?.doubleValue ?? 0.0
                        let d19 = (item["production_exercice_n2"] as? NSNumber)?.doubleValue ?? 0.0
                        let d20 = (item["valeur_ajoutee_n2"] as? NSNumber)?.doubleValue ?? 0.0
                        let d21 = (item["ebe_sig_n2"] as? NSNumber)?.doubleValue ?? 0.0
                        let d22 = (item["resultat_exploitation_n2"] as? NSNumber)?.doubleValue ?? 0.0
                        let d23 = (item["resultat_financier_n2"] as? NSNumber)?.doubleValue ?? 0.0
                        let d24 = (item["resultat_courant_n2"] as? NSNumber)?.doubleValue ?? 0.0
                        let d25 = (item["resultat_exceptionnel_n2"] as? NSNumber)?.doubleValue ?? 0.0
                        let d26 = (item["resultat_net_n2"] as? NSNumber)?.doubleValue ?? 0.0
                        let d27 = (item["ca_ht"] as? NSNumber)?.doubleValue ?? 0.0
                        let d28 = (item["couts_directs"] as? NSNumber)?.doubleValue ?? 0.0
                        let d29 = (item["autres_achats"] as? NSNumber)?.doubleValue ?? 0.0
                        let d30 = (item["services_externes"] as? NSNumber)?.doubleValue ?? 0.0
                        let d31 = (item["autres_services"] as? NSNumber)?.doubleValue ?? 0.0
                        let d32 = (item["production_vendue"] as? NSNumber)?.doubleValue ?? 0.0
                        let d33 = (item["production_stockee"] as? NSNumber)?.doubleValue ?? 0.0
                        let d34 = (item["production_immobilisee"] as? NSNumber)?.doubleValue ?? 0.0
                        let d35 = (item["consommations_externes"] as? NSNumber)?.doubleValue ?? 0.0
                        let d36 = (item["impots_et_taxes"] as? NSNumber)?.doubleValue ?? 0.0
                        let d37 = (item["frais_personnel"] as? NSNumber)?.doubleValue ?? 0.0
                        let d38 = (item["autres_charges_exploitation"] as? NSNumber)?.doubleValue ?? 0.0
                        let d39 = (item["produits_divers"] as? NSNumber)?.doubleValue ?? 0.0
                        let d40 = (item["dotations"] as? NSNumber)?.doubleValue ?? 0.0
                        let d41 = (item["reprises"] as? NSNumber)?.doubleValue ?? 0.0
                        let d42 = (item["produits_financiers"] as? NSNumber)?.doubleValue ?? 0.0
                        let d43 = (item["charges_financieres"] as? NSNumber)?.doubleValue ?? 0.0
                        let d44 = (item["produits_exceptionnels"] as? NSNumber)?.doubleValue ?? 0.0
                        let d45 = (item["charges_exceptionnels"] as? NSNumber)?.doubleValue ?? 0.0
                        let d46 = (item["impot_sur_benefices"] as? NSNumber)?.doubleValue ?? 0.0
                        let d47 = (item["ca_ht_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d48 = (item["couts_directs_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d49 = (item["autres_achats_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d50 = (item["services_externes_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d51 = (item["autres_services_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d52 = (item["impots_et_taxes_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d53 = (item["frais_personnel_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d54 = (item["autres_charges_exploitation_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d55 = (item["produits_divers_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d56 = (item["dotations_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d57 = (item["reprises_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d58 = (item["charges_financieres_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d59 = (item["produits_exceptionnels_n1"] as? NSNumber)?.doubleValue ?? 0.0
                        let d60 = (item["charges_exceptionnels_n1"] as? NSNumber)?.doubleValue ?? 0.0

                        let solde = SoldesIntermedialres(exerciceID: exerciceId)
                        solde.id = id
                        solde.margeBrute = d0
                        solde.productionExercice = d1
                        solde.valeurAjoutee = d2
                        solde.ebeSig = d3
                        solde.resultatExploitation = d4
                        solde.resultatFinancier = d5
                        solde.resultatCourant = d6
                        solde.resultatExceptionnel = d7
                        solde.resultatNet = d8
                        solde.margeBruteN1 = d9
                        solde.productionExerciceN1 = d10
                        solde.valeurAjouteeN1 = d11
                        solde.ebeSigN1 = d12
                        solde.resultatExploitationN1 = d13
                        solde.resultatFinancierN1 = d14
                        solde.resultatCourantN1 = d15
                        solde.resultatExceptionnelN1 = d16
                        solde.resultatNetN1 = d17
                        solde.margeBruteN2 = d18
                        solde.productionExerciceN2 = d19
                        solde.valeurAjouteeN2 = d20
                        solde.ebeSigN2 = d21
                        solde.resultatExploitationN2 = d22
                        solde.resultatFinancierN2 = d23
                        solde.resultatCourantN2 = d24
                        solde.resultatExceptionnelN2 = d25
                        solde.resultatNetN2 = d26
                        solde.caHT = d27
                        solde.coutsDirects = d28
                        solde.autresAchats = d29
                        solde.servicesExternes = d30
                        solde.autresServices = d31
                        solde.productionVendue = d32
                        solde.productionStockee = d33
                        solde.productionImmobilisee = d34
                        solde.consommationsExternes = d35
                        solde.impotsEtTaxes = d36
                        solde.fraisPersonnel = d37
                        solde.autresChargesExploitation = d38
                        solde.produitsDivers = d39
                        solde.dotations = d40
                        solde.reprises = d41
                        solde.produitsFinanciers = d42
                        solde.chargesFinancieres = d43
                        solde.produitsExceptionnels = d44
                        solde.chargesExceptionnels = d45
                        solde.impotSurBenefices = d46
                        solde.caHTN1 = d47
                        solde.coutsDirectsN1 = d48
                        solde.autresAchatsN1 = d49
                        solde.servicesExternesN1 = d50
                        solde.autresServicesN1 = d51
                        solde.impotsEtTaxesN1 = d52
                        solde.fraisPersonnelN1 = d53
                        solde.autresChargesExploitationN1 = d54
                        solde.produitsDiversN1 = d55
                        solde.dotationsN1 = d56
                        solde.reprisesN1 = d57
                        solde.chargesFinanciereN1 = d58
                        solde.produitsExceptionnelsN1 = d59
                        solde.chargesExceptionnelsN1 = d60
                        context.insert(solde)
                        loaded += 1
                    }
                    if loaded > 0 {
                        try context.save()
                    }
                    print("✅ \(loaded) soldes intermédiaires chargés (+ \(localExercices.count) exercices déjà locaux)")
                }
            }
        } catch {
            print("⚠️ Erreur chargement soldes_intermediares: \(error.localizedDescription)")
        }
    }

    // MARK: - Full Sync

    func fullSync(from container: ModelContainer) async {
        guard !hasFullSyncedThisSession else {
            print("⏳ Synchronisation déjà effectuée cette session, appel ignoré")
            return
        }
        guard !isSyncing else {
            print("⏳ Synchronisation déjà en cours, appel ignoré")
            return
        }
        isSyncing = true
        defer { isSyncing = false; hasFullSyncedThisSession = true }

        print("🚀 Début synchronisation Supabase...")
        print("   URL: \(baseURL)")
        SyncDiagnostics.reset()

        // PHASE 1: Charger TOUT avec un SEUL context
        let context = ModelContext(container)

        // ÉTAPE 1: ENVOYER les données locales vers Supabase (d'abord!)
        print("\n📤 ÉTAPE 1: Envoi données locales → Supabase")
        await dedupeDossiers(from: container)
        await dedupeBalanceAccounts(from: container)
        await dedupeSoldesIntermediaires(from: container)
        await dedupeDsnAssiettes(from: container)
        await syncDossiers(from: container)
        await syncExercices(from: container)
        await syncBalanceAccounts(from: container)
        await syncSoldesIntermediales(from: container)
        await syncImmoAssets(from: container)
        await syncPendingItems(from: container)
        await syncAuditWork(from: container)
        await syncJustificatifs(from: container)

        // ÉTAPE 2: CHARGER depuis Supabase (pour les autres Macs)
        print("\n📥 ÉTAPE 2: Chargement Supabase → local")
        await loadAllFromSupabase(using: context)

        SyncDiagnostics.report()
        print("\n✅ Synchronisation complétée!")
    }

    private func loadAllFromSupabase(using context: ModelContext) async {
        print("📥 Chargement depuis Supabase...")

        // Seules les données importées (dossiers, exercices, balance) sont
        // rechargées à neuf. Le travail d'audit n'est jamais vidé : il est
        // fusionné par identifiant plus bas, via loadAuditWork.

        // Vider les tables de DATA (pas les contrôles).
        // IMPORTANT: ne PAS sauvegarder après la suppression — cela créerait un
        // "trou" où BalanceAccount serait vide, déclenchant une re-refresh de @Query
        // et un écran blanc. Tout doit être une seule transaction.
        do {
            try context.delete(model: Dossier.self)
            try context.delete(model: Exercice.self)
            try context.delete(model: BalanceAccount.self)
            print("  Tables de données vidées (pas encore sauvegardées)")
        } catch {
            print("  ⚠️  Erreur vidage tables: \(error)")
        }

        // 1. DOSSIERS
        do {
            let url = URL(string: "\(baseURL)/rest/v1/dossiers")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                print("  Dossiers: \(jsonArray.count) trouvés")
                for item in jsonArray {
                    guard let idStr = item["id"] as? String,
                          let id = UUID(uuidString: idStr),
                          let nom = item["nom"] as? String else { continue }
                    let dossier = Dossier(id: id, nom: nom, ordre: item["ordre"] as? Int ?? 0)
                    context.insert(dossier)
                    print("    ✅ \(nom)")
                }
            }
        } catch {
            print("  ❌ Erreur dossiers: \(error)")
        }

        // 2. EXERCICES
        do {
            let url = URL(string: "\(baseURL)/rest/v1/exercices")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            print("  📡 Appel API exercices...")
            let (data, response) = try await session.data(for: request)
            print("  📊 Réponse reçue")

            if let httpResponse = response as? HTTPURLResponse {
                print("    HTTP Status: \(httpResponse.statusCode)")
                if httpResponse.statusCode == 200 {
                    if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        print("  ✅ JSON parsé: \(jsonArray.count) exercices")

                        var loaded = 0
                        var failed = 0

                        for (idx, item) in jsonArray.enumerated() {
                            print("    Item \(idx): \(item.keys.joined(separator: ", "))")

                            guard let idStr = item["id"] as? String else {
                                print("      ✗ Pas d'ID")
                                failed += 1
                                continue
                            }
                            guard let id = UUID(uuidString: idStr) else {
                                print("      ✗ ID invalide: \(idStr)")
                                failed += 1
                                continue
                            }
                            guard let dossierIdStr = item["dossier_id"] as? String else {
                                print("      ✗ Pas de dossier_id")
                                failed += 1
                                continue
                            }
                            guard let dossierId = UUID(uuidString: dossierIdStr) else {
                                print("      ✗ dossier_id invalide")
                                failed += 1
                                continue
                            }
                            guard let libelle = item["libelle"] as? String else {
                                print("      ✗ Pas de libelle")
                                failed += 1
                                continue
                            }

                            let dateCloture = (item["date_cloture"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
                            let creeLe = (item["cree_le"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
                            let exercice = Exercice(id: id, dossierID: dossierId, libelle: libelle, dateCloture: dateCloture, creeLe: creeLe)
                            context.insert(exercice)
                            loaded += 1
                            print("      ✅ \(libelle)")
                        }
                        print("  📊 Exercices: \(loaded) insérés, \(failed) échoués")
                    } else {
                        print("  ✗ JSON non parsable")
                    }
                } else {
                    print("    ✗ HTTP Error: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("  ❌ Erreur exercices: \(error)")
            print("     \(error.localizedDescription)")
        }

        // 3. BALANCE ACCOUNTS (DEDUPLICATE avant d'insérer)
        do {
            // Lecture paginee : la table a pu accumuler plusieurs generations de
            // lignes, bien au-dela des 1000 que PostgREST renvoie par defaut.
            let jsonArray = await fetchAllRows("balance_accounts", label: "Balance Accounts")
            if !jsonArray.isEmpty {
                print("  Balance Accounts: \(jsonArray.count) trouvés")

                let uniques = dedupeRows(jsonArray)
                var best: [String: [String: Any]] = [:]
                for item in uniques {
                    guard let compte = item["account_number"] as? String,
                          let exercice = item["exercice_id"] as? String else { continue }
                    best["\(exercice)|\(compte)"] = item
                }

                print("    🧹 \(jsonArray.count - best.count) doublons filtrés avant insertion")

                // Insérer uniquement les comptes uniques
                for item in best.values {
                    guard let idStr = item["id"] as? String,
                          let id = UUID(uuidString: idStr),
                          let accountNumber = item["account_number"] as? String,
                          let exerciceIdStr = item["exercice_id"] as? String,
                          let exerciceId = UUID(uuidString: exerciceIdStr) else { continue }
                    let debit = (item["debit"] as? NSNumber)?.doubleValue ?? 0.0
                    let credit = (item["credit"] as? NSNumber)?.doubleValue ?? 0.0
                    let restaurant = Restaurant(rawValue: item["restaurant"] as? String ?? "Freddy") ?? .freddy
                    let account = BalanceAccount(
                        id: id, accountNumber: accountNumber, accountCode: item["account_code"] as? String ?? "",
                        accountLabel: item["account_label"] as? String ?? "", debit: debit, credit: credit,
                        balanceN: (item["balance_n"] as? NSNumber)?.doubleValue ?? 0.0,
                        balanceNMinus1: (item["balance_n_minus_1"] as? NSNumber)?.doubleValue ?? 0.0,
                        restaurant: restaurant, exerciceID: exerciceId,
                        sourceFile: item["source_file"] as? String ?? "",
                        importDate: (item["import_date"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
                    )
                    context.insert(account)
                }
                print("    ✅ \(best.count) uniques insérés")
            }
        } catch {
            print("  ❌ Erreur balance_accounts: \(error)")
        }

        // 4. POINTS EN SUSPENS (fusion, jamais vidés localement)
        await loadPendingItemsFromSupabase(using: context)

        // 5. SOLDES INTERMÉDIAIRES (fusion)
        await loadSoldesIntermedialresFromSupabase(using: context)

        // 6. TRAVAIL D'AUDIT : contrôles, justifications, TVA, rapprochements,
        //    immobilisations, règles de cycle (fusion, jamais vidés localement)
        await loadAuditWork(using: context)

        // Sauvegarde unique des données Supabase
        print("\n💾 Sauvegarde données Supabase...")
        do {
            try context.save()
            print("✅ Données Supabase sauvegardées")
        } catch {
            print("❌ Erreur sauvegarde: \(error)")
        }

    }
}
