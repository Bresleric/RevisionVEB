//
//  SupabaseSyncModels.swift
//  RevisionVEB
//
//  Synchronisation Supabase du travail d'audit : controles, justifications,
//  TVA, rapprochements, immobilisations et regles de cycle.
//
//  Ces modeles completent la synchro de base (dossiers / exercices / balance)
//  definie dans SupabaseSync.swift.
//

import Foundation
import SwiftData
import CryptoKit

/// Regroupe les echecs d'ecriture d'une synchronisation.
///
/// Une balance de 659 comptes qui echoue produisait 659 lignes identiques dans
/// la console. On agrege par (table, code PostgreSQL) pour n'afficher qu'une
/// ligne par cause reelle, avec le message d'origine.
@MainActor
enum SyncDiagnostics {
    private struct Key: Hashable { let table: String; let code: String }
    private static var failures: [Key: (count: Int, message: String)] = [:]

    static func reset() { failures.removeAll() }

    static func record(table: String, status: Int, body: String) {
        var code = "HTTP \(status)"
        var message = body

        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            code = json["code"] as? String ?? code
            message = json["message"] as? String ?? body
            if let details = json["details"] as? String, !details.isEmpty {
                message += " — \(details)"
            }
        }

        let key = Key(table: table, code: code)
        let previous = failures[key]?.count ?? 0
        failures[key] = (previous + 1, message)
    }

    /// Affiche le bilan des echecs, avec une explication des codes courants.
    static func report() {
        guard !failures.isEmpty else {
            print("✅ Aucune erreur d'écriture")
            return
        }

        print("\n⚠️ Échecs d'écriture Supabase :")
        for (key, value) in failures.sorted(by: { $0.value.count > $1.value.count }) {
            print("   \(key.table) — \(value.count) ligne\(value.count > 1 ? "s" : "") — \(key.code)")
            print("      \(value.message)")
            switch key.code {
            case "23503":
                print("      → clé étrangère manquante : l'exercice ou le dossier parent n'est pas sur Supabase")
            case "23505":
                print("      → identifiant déjà présent : l'enregistrement aurait dû être mis à jour, pas créé")
            case "PGRST204":
                print("      → colonne absente : exécuter supabase_schema.sql dans Supabase Studio")
            case "PGRST205":
                print("      → table absente : exécuter supabase_schema.sql dans Supabase Studio")
            case "42501":
                print("      → refusé par RLS : vérifier la policy de la table")
            default:
                break
            }
        }
    }
}

extension SupabaseSync {

    // MARK: - Outils

    /// Identifiant stable derive d'une cle logique.
    ///
    /// Plusieurs modeles n'ont pas d'`id` propre : leur identite est composite
    /// (exercice + numero de compte, par exemple). On derive donc un UUID
    /// deterministe de cette cle, pour que les deux Macs produisent le meme
    /// identifiant pour la meme donnee — sans quoi chaque machine creerait des
    /// doublons a chaque synchronisation.
    static func stableID(_ parts: String...) -> UUID {
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        var bytes = Array(digest.prefix(16))
        // Marque les bits de version (5) et de variante, comme un UUID nomme.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Nombre exploitable en JSON (protege des NaN / infinis).
    private func safe(_ v: Double) -> Double { (v.isNaN || v.isInfinite) ? 0 : v }

    /// Envoi generique d'une collection vers une table Supabase.
    ///
    /// `id` sert a dedoublonner avant l'envoi : deux enregistrements locaux
    /// partageant la meme cle logique produiraient la meme ligne, et PostgREST
    /// refuse un lot qui vise deux fois la meme clef primaire.
    private func push<T>(_ table: String,
                         _ rows: [T],
                         label: String,
                         id: (T) -> UUID,
                         payload: (T) -> [String: Any]) async {
        guard !rows.isEmpty else { return }

        var seen = Set<UUID>()
        var batch: [[String: Any]] = []
        for row in rows where seen.insert(id(row)).inserted {
            batch.append(payload(row))
        }

        print("📤 \(label): \(batch.count)")
        await bulkUpsert(tableName: table, rows: batch)
    }

    /// Lecture generique d'une table Supabase.
    ///
    /// Renvoie `nil` si la table est absente ou inaccessible, pour que l'appelant
    /// puisse simplement ne rien faire au lieu de vider des donnees locales.
    private func fetchRows(_ table: String, label: String) async -> [[String: Any]]? {
        do {
            let url = URL(string: "\(baseURL)/rest/v1/\(table)")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard http.statusCode == 200 else {
                if http.statusCode == 404 {
                    print("  ℹ️ \(label): table absente sur Supabase")
                } else {
                    print("  ⚠️ \(label): HTTP \(http.statusCode)")
                }
                return nil
            }
            return try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        } catch {
            print("  ⚠️ \(label): \(error.localizedDescription)")
            return nil
        }
    }

    private func date(_ any: Any?) -> Date? {
        (any as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    private func dbl(_ any: Any?) -> Double { (any as? NSNumber)?.doubleValue ?? 0 }
    private func str(_ any: Any?) -> String { any as? String ?? "" }
    private func int(_ any: Any?) -> Int { (any as? NSNumber)?.intValue ?? 0 }
    private func uuid(_ any: Any?) -> UUID? { (any as? String).flatMap { UUID(uuidString: $0) } }

    // MARK: - Dédoublonnage

    /// Supprime les comptes de balance en double avant tout envoi.
    ///
    /// Tant que les identifiants étaient comparés en majuscules d'un côté et en
    /// minuscules de l'autre, aucune correspondance n'était trouvée : chaque
    /// machine créait sa propre ligne pour le même compte. La base distante a
    /// ainsi accumulé deux exemplaires de nombreux comptes, rapatriés ensuite
    /// en local. On ne garde qu'une ligne par (exercice, compte).
    ///
    /// Règle de conservation : la ligne du dernier import. Réimporter une
    /// balance remplace la précédente, c'est donc la plus récente qui fait foi.
    func dedupeBalanceAccounts(from container: ModelContainer) async {
        let context = ModelContext(container)
        guard let accounts = try? context.fetch(FetchDescriptor<BalanceAccount>()) else { return }

        var best: [String: BalanceAccount] = [:]
        var doomed: [BalanceAccount] = []

        for account in accounts {
            let key = "\(account.exerciceID.pg)|\(account.accountNumber)"
            guard let current = best[key] else {
                best[key] = account
                continue
            }
            // Import le plus récent ; à égalité, identifiant le plus petit pour
            // que les deux Macs retiennent la même ligne.
            let keepsNew = (account.importDate, account.id.pg) > (current.importDate, current.id.pg)
            best[key] = keepsNew ? account : current
            doomed.append(keepsNew ? current : account)
        }

        guard !doomed.isEmpty else { return }
        for account in doomed { context.delete(account) }
        do {
            try context.save()
            print("🧹 Balance: \(doomed.count) doublons supprimés localement")
        } catch {
            print("⚠️ Dédoublonnage balance: \(error.localizedDescription)")
        }
    }

    /// Ne conserve qu'un jeu de soldes intermédiaires par exercice.
    ///
    /// La vue SIG retient le premier enregistrement trouvé pour l'exercice :
    /// avec plusieurs exemplaires, elle pouvait afficher un calcul périmé.
    /// On garde le plus récemment mis à jour.
    func dedupeSoldesIntermediaires(from container: ModelContainer) async {
        let context = ModelContext(container)
        guard let soldes = try? context.fetch(FetchDescriptor<SoldesIntermedialres>()) else { return }

        var best: [UUID: SoldesIntermedialres] = [:]
        var doomed: [SoldesIntermedialres] = []

        for solde in soldes {
            guard let current = best[solde.exerciceID] else {
                best[solde.exerciceID] = solde
                continue
            }
            let keepsNew = (solde.updatedAt, solde.id.pg) > (current.updatedAt, current.id.pg)
            best[solde.exerciceID] = keepsNew ? solde : current
            doomed.append(keepsNew ? current : solde)
        }

        guard !doomed.isEmpty else { return }
        for solde in doomed { context.delete(solde) }
        do {
            try context.save()
            print("🧹 SIG: \(doomed.count) doublons supprimés localement")
        } catch {
            print("⚠️ Dédoublonnage SIG: \(error.localizedDescription)")
        }
    }


    // MARK: - Envoi (local → Supabase)

    /// Envoie tout le travail d'audit vers Supabase.
    func syncAuditWork(from container: ModelContainer) async {
        let context = ModelContext(container)

        func all<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }

        // Controles de revision (cle : exercice + cycle + item)
        await push("control_states", all(ControlState.self), label: "Contrôles",
                   id: { Self.stableID($0.exerciceID.pg, $0.cycleRaw, $0.itemID) }) { c in
            [
                "id": Self.stableID(c.exerciceID.pg, c.cycleRaw, c.itemID).pg,
                "exercice_id": c.exerciceID.pg,
                "cycle_raw": c.cycleRaw,
                "item_id": c.itemID,
                "status_raw": c.statutRaw,
                "notes": c.note,
                "updated_at": c.updatedAt.ISO8601Format()
            ]
        }

        // Justifications de comptes (cle : exercice + compte)
        await push("account_justifications", all(AccountJustification.self), label: "Justifications",
                   id: { Self.stableID($0.exerciceID.pg, $0.accountNumber) }) { j in
            var p: [String: Any] = [
                "id": Self.stableID(j.exerciceID.pg, j.accountNumber).pg,
                "exercice_id": j.exerciceID.pg,
                "account_number": j.accountNumber,
                "file_name": j.docName,
                "file_path": j.docPath,
                "notes": j.note,
                "updated_at": j.updatedAt.ISO8601Format()
            ]
            p["solde_justifie"] = j.soldeJustifie.map { self.safe($0) } ?? NSNull()
            return p
        }

        // Taux de TVA par compte (cle : exercice + compte)
        await push("tva_compte_taux", all(TvaCompteTaux.self), label: "Taux TVA",
                   id: { Self.stableID($0.exerciceID.pg, $0.compte) }) { t in
            [
                "id": Self.stableID(t.exerciceID.pg, t.compte).pg,
                "exercice_id": t.exerciceID.pg,
                "compte": t.compte,
                "taux_raw": t.taux
            ]
        }

        // Rapprochements bancaires (cle : exercice + compte).
        //
        // Les elements de rapprochement pointent vers un rapprochement parent
        // via une cle etrangere. Un element saisi sur un compte sans entete de
        // rapprochement ferait donc echouer l'envoi : on complete la liste avec
        // les parents manquants avant d'envoyer.
        let reconItems = all(ReconItem.self)
        let reconciliations = all(BankReconciliation.self)
        var reconKeys = Set(reconciliations.map { Self.stableID($0.exerciceID.pg, $0.accountNumber) })

        var reconPayloads: [(id: UUID, body: [String: Any])] = reconciliations.map { r in
            let rid = Self.stableID(r.exerciceID.pg, r.accountNumber)
            var p: [String: Any] = [
                "id": rid.pg,
                "exercice_id": r.exerciceID.pg,
                "compte_51": r.accountNumber,
                "note": r.note,
                "updated_at": r.updatedAt.ISO8601Format()
            ]
            p["solde_banque"] = r.soldeExtrait.map { self.safe($0) } ?? NSNull()
            return (rid, p)
        }

        for item in reconItems {
            let rid = Self.stableID(item.exerciceID.pg, item.accountNumber)
            guard !reconKeys.contains(rid) else { continue }
            reconKeys.insert(rid)
            reconPayloads.append((rid, [
                "id": rid.pg,
                "exercice_id": item.exerciceID.pg,
                "compte_51": item.accountNumber,
                "note": "",
                "solde_banque": NSNull(),
                "updated_at": Date().ISO8601Format()
            ]))
        }

        await push("bank_reconciliations", reconPayloads, label: "Rapprochements",
                   id: { $0.id }) { $0.body }

        // Elements de rapprochement (id propre, rattaches a leur rapprochement)
        await push("recon_items", reconItems, label: "Éléments de rapprochement",
                   id: { $0.id }) { i in
            [
                "id": i.id.pg,
                "recon_id": Self.stableID(i.exerciceID.pg, i.accountNumber).pg,
                "exercice_id": i.exerciceID.pg,
                "account_number": i.accountNumber,
                "libelle": i.libelle,
                "montant": self.safe(i.montant),
                "ordre": i.ordre,
                "doc_name": i.docName,
                "doc_path": i.docPath
            ]
        }

        // Declarations de TVA : lignes (id propre)
        await push("ca3_entries", all(Ca3Entry.self), label: "TVA — lignes", id: { $0.id }) { e in
            [
                "id": e.id.pg,
                "exercice_id": e.exerciceID.pg,
                "periode": e.periode,
                "taux": e.taux,
                "base": self.safe(e.base),
                "tva": self.safe(e.tva),
                "ordre": e.ordre
            ]
        }

        // Declarations de TVA : periodes (cle : exercice + periode)
        await push("ca3_periods", all(Ca3Period.self), label: "TVA — périodes",
                   id: { Self.stableID($0.exerciceID.pg, $0.periode) }) { p in
            [
                "id": Self.stableID(p.exerciceID.pg, p.periode).pg,
                "exercice_id": p.exerciceID.pg,
                "periode": p.periode,
                "tva_deductible": self.safe(p.tvaDeductible),
                "credit_m1": self.safe(p.creditM1),
                "ca_ht": self.safe(p.caHT),
                "ligne16": self.safe(p.ligne16),
                "ligne19": self.safe(p.ligne19),
                "ligne20": self.safe(p.ligne20),
                "doc_name": p.docName,
                "doc_path": p.docPath
            ]
        }

        // Factures d'investissement (id propre)
        await push("immo_invoices", all(ImmoInvoice.self), label: "Factures immo", id: { $0.id }) { f in
            [
                "id": f.id.pg,
                "exercice_id": f.exerciceID.pg,
                "date": f.date.ISO8601Format(),
                "compte": f.compte,
                "designation": f.designation,
                "montant": self.safe(f.montant),
                "doc_name": f.docName,
                "doc_path": f.docPath,
                "ordre": f.ordre
            ]
        }

        // Mouvements de classe 2 (id propre)
        await push("class2_movements", all(Class2Movement.self), label: "Mouvements classe 2", id: { $0.id }) { m in
            [
                "id": m.id.pg,
                "exercice_id": m.exerciceID.pg,
                "date": m.date.ISO8601Format(),
                "compte": m.compte,
                "libelle": m.libelle,
                "complement": m.complement,
                "debit": self.safe(m.debit),
                "credit": self.safe(m.credit),
                "ordre": m.ordre
            ]
        }

        // Regles de cycle par compte (cle : dossier + compte)
        await push("account_cycle_rules", all(AccountCycleRule.self), label: "Règles de cycle",
                   id: { Self.stableID($0.dossierID.pg, $0.accountNumber) }) { r in
            [
                "id": Self.stableID(r.dossierID.pg, r.accountNumber).pg,
                "dossier_id": r.dossierID.pg,
                "account_number": r.accountNumber,
                "cycle_raw": r.cycleRaw
            ]
        }
    }

    // MARK: - Pièces justificatives

    /// Dépose sur Supabase les pièces présentes en local et absentes du bucket.
    ///
    /// La base ne transporte que le chemin du fichier, propre à la machine qui
    /// a rattaché la pièce. Sans le fichier lui-même sur le serveur, l'autre Mac
    /// affiche bien la référence mais ne peut rien ouvrir.
    func syncJustificatifs(from container: ModelContainer) async {
        let context = ModelContext(container)

        func paths<T: PersistentModel>(_ type: T.Type, _ extract: (T) -> (String, UUID)) -> [(String, UUID)] {
            ((try? context.fetch(FetchDescriptor<T>())) ?? []).map(extract).filter { !$0.0.isEmpty }
        }

        var docs: [(path: String, exercice: UUID)] = []
        docs += paths(AccountJustification.self) { ($0.docPath, $0.exerciceID) }
        docs += paths(ReconItem.self) { ($0.docPath, $0.exerciceID) }
        docs += paths(ImmoInvoice.self) { ($0.docPath, $0.exerciceID) }
        docs += paths(Ca3Period.self) { ($0.docPath, $0.exerciceID) }

        // Seuls les fichiers réellement présents sur cette machine sont candidats.
        let local = docs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !local.isEmpty else { return }

        var known: [UUID: Set<String>] = [:]
        var sent = 0

        for doc in local {
            guard let remote = SupabaseStorage.remotePath(forLocalPath: doc.path) else { continue }
            if known[doc.exercice] == nil {
                known[doc.exercice] = await SupabaseStorage.existingPaths(exerciceID: doc.exercice)
            }
            if known[doc.exercice]?.contains(remote) == true { continue }
            if await SupabaseStorage.upload(localPath: doc.path, remotePath: remote) {
                known[doc.exercice]?.insert(remote)
                sent += 1
            }
        }

        print("📎 Pièces justificatives: \(sent) envoyée\(sent > 1 ? "s" : "") (\(local.count) en local)")
    }

    // MARK: - Chargement (Supabase → local)

    /// Recupere le travail d'audit depuis Supabase et le fusionne avec le local.
    ///
    /// Aucune table n'est videe : on fusionne par identifiant. Quand les deux
    /// cotes portent une date de modification, le plus recent l'emporte.
    func loadAuditWork(using context: ModelContext) async {
        await loadControlStates(using: context)
        await loadJustifications(using: context)
        await loadTvaTaux(using: context)
        await loadReconciliations(using: context)
        await loadReconItems(using: context)
        await loadCa3Entries(using: context)
        await loadCa3Periods(using: context)
        await loadImmoInvoices(using: context)
        await loadImmoAssetsMerged(using: context)
        await loadClass2Movements(using: context)
        await loadCycleRules(using: context)

        do {
            try context.save()
        } catch {
            print("  ⚠️ Sauvegarde travail d'audit: \(error.localizedDescription)")
        }
    }

    private func loadControlStates(using context: ModelContext) async {
        guard let rows = await fetchRows("control_states", label: "Contrôles") else { return }
        let locals = (try? context.fetch(FetchDescriptor<ControlState>())) ?? []
        var byKey = Dictionary(locals.map {
            (Self.stableID($0.exerciceID.pg, $0.cycleRaw, $0.itemID), $0)
        }, uniquingKeysWith: { first, _ in first })

        var added = 0, merged = 0
        for r in rows {
            guard let id = uuid(r["id"]),
                  let exID = uuid(r["exercice_id"]) else { continue }
            let remote = date(r["updated_at"]) ?? .distantPast
            if let local = byKey[id] {
                guard remote > local.updatedAt else { continue }
                local.statutRaw = str(r["status_raw"])
                local.note = str(r["notes"])
                local.updatedAt = remote
                merged += 1
            } else {
                let c = ControlState(exerciceID: exID,
                                     cycleRaw: str(r["cycle_raw"]),
                                     itemID: str(r["item_id"]),
                                     statut: ControlStatus(rawValue: str(r["status_raw"])) ?? .aFaire,
                                     note: str(r["notes"]),
                                     updatedAt: remote)
                context.insert(c)
                byKey[id] = c
                added += 1
            }
        }
        print("  ✅ Contrôles: \(added) ajoutés, \(merged) mis à jour")
    }

    private func loadJustifications(using context: ModelContext) async {
        guard let rows = await fetchRows("account_justifications", label: "Justifications") else { return }
        let locals = (try? context.fetch(FetchDescriptor<AccountJustification>())) ?? []
        var byKey = Dictionary(locals.map {
            (Self.stableID($0.exerciceID.pg, $0.accountNumber), $0)
        }, uniquingKeysWith: { first, _ in first })

        var added = 0, merged = 0
        for r in rows {
            guard let id = uuid(r["id"]), let exID = uuid(r["exercice_id"]) else { continue }
            let remote = date(r["updated_at"]) ?? .distantPast
            let solde = r["solde_justifie"] is NSNull ? nil : (r["solde_justifie"] as? NSNumber)?.doubleValue
            if let local = byKey[id] {
                guard remote > local.updatedAt else { continue }
                local.soldeJustifie = solde
                local.note = str(r["notes"])
                // Les chemins de pieces sont propres a chaque Mac : on ne remplace
                // un chemin local existant que s'il est vide.
                if local.docPath.isEmpty {
                    local.docName = str(r["file_name"])
                    local.docPath = str(r["file_path"])
                }
                local.updatedAt = remote
                merged += 1
            } else {
                let j = AccountJustification(exerciceID: exID, accountNumber: str(r["account_number"]))
                j.soldeJustifie = solde
                j.docName = str(r["file_name"])
                j.docPath = str(r["file_path"])
                j.note = str(r["notes"])
                j.updatedAt = remote
                context.insert(j)
                byKey[id] = j
                added += 1
            }
        }
        print("  ✅ Justifications: \(added) ajoutées, \(merged) mises à jour")
    }

    private func loadTvaTaux(using context: ModelContext) async {
        guard let rows = await fetchRows("tva_compte_taux", label: "Taux TVA") else { return }
        let locals = (try? context.fetch(FetchDescriptor<TvaCompteTaux>())) ?? []
        var byKey = Dictionary(locals.map {
            (Self.stableID($0.exerciceID.pg, $0.compte), $0)
        }, uniquingKeysWith: { first, _ in first })

        var added = 0
        for r in rows {
            guard let id = uuid(r["id"]), let exID = uuid(r["exercice_id"]) else { continue }
            if let local = byKey[id] {
                local.taux = str(r["taux_raw"])
            } else {
                let t = TvaCompteTaux(exerciceID: exID, compte: str(r["compte"]), taux: str(r["taux_raw"]))
                context.insert(t)
                byKey[id] = t
                added += 1
            }
        }
        print("  ✅ Taux TVA: \(added) ajoutés")
    }

    private func loadReconciliations(using context: ModelContext) async {
        guard let rows = await fetchRows("bank_reconciliations", label: "Rapprochements") else { return }
        let locals = (try? context.fetch(FetchDescriptor<BankReconciliation>())) ?? []
        var byKey = Dictionary(locals.map {
            (Self.stableID($0.exerciceID.pg, $0.accountNumber), $0)
        }, uniquingKeysWith: { first, _ in first })

        var added = 0, merged = 0
        for r in rows {
            guard let id = uuid(r["id"]), let exID = uuid(r["exercice_id"]) else { continue }
            let remote = date(r["updated_at"]) ?? .distantPast
            let solde = r["solde_banque"] is NSNull ? nil : (r["solde_banque"] as? NSNumber)?.doubleValue
            if let local = byKey[id] {
                guard remote > local.updatedAt else { continue }
                local.soldeExtrait = solde
                local.note = str(r["note"])
                local.updatedAt = remote
                merged += 1
            } else {
                let b = BankReconciliation(exerciceID: exID, accountNumber: str(r["compte_51"]))
                b.soldeExtrait = solde
                b.note = str(r["note"])
                b.updatedAt = remote
                context.insert(b)
                byKey[id] = b
                added += 1
            }
        }
        print("  ✅ Rapprochements: \(added) ajoutés, \(merged) mis à jour")
    }

    private func loadReconItems(using context: ModelContext) async {
        guard let rows = await fetchRows("recon_items", label: "Éléments de rapprochement") else { return }
        let locals = (try? context.fetch(FetchDescriptor<ReconItem>())) ?? []
        var byID = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var added = 0
        for r in rows {
            guard let id = uuid(r["id"]), let exID = uuid(r["exercice_id"]) else { continue }
            let target: ReconItem
            if let local = byID[id] {
                target = local
            } else {
                let i = ReconItem(exerciceID: exID, accountNumber: str(r["account_number"]))
                i.id = id
                context.insert(i)
                byID[id] = i
                target = i
                added += 1
            }
            target.accountNumber = str(r["account_number"])
            target.libelle = str(r["libelle"])
            target.montant = dbl(r["montant"])
            target.ordre = int(r["ordre"])
            if target.docPath.isEmpty {
                target.docName = str(r["doc_name"])
                target.docPath = str(r["doc_path"])
            }
        }
        print("  ✅ Éléments de rapprochement: \(added) ajoutés")
    }

    private func loadCa3Entries(using context: ModelContext) async {
        guard let rows = await fetchRows("ca3_entries", label: "TVA — lignes") else { return }
        let locals = (try? context.fetch(FetchDescriptor<Ca3Entry>())) ?? []
        var byID = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var added = 0
        for r in rows {
            guard let id = uuid(r["id"]), let exID = uuid(r["exercice_id"]) else { continue }
            let target: Ca3Entry
            if let local = byID[id] {
                target = local
            } else {
                let e = Ca3Entry(exerciceID: exID, periode: str(r["periode"]), taux: str(r["taux"]))
                e.id = id
                context.insert(e)
                byID[id] = e
                target = e
                added += 1
            }
            target.periode = str(r["periode"])
            target.taux = str(r["taux"])
            target.base = dbl(r["base"])
            target.tva = dbl(r["tva"])
            target.ordre = int(r["ordre"])
        }
        print("  ✅ TVA lignes: \(added) ajoutées")
    }

    private func loadCa3Periods(using context: ModelContext) async {
        guard let rows = await fetchRows("ca3_periods", label: "TVA — périodes") else { return }
        let locals = (try? context.fetch(FetchDescriptor<Ca3Period>())) ?? []
        var byKey = Dictionary(locals.map {
            (Self.stableID($0.exerciceID.pg, $0.periode), $0)
        }, uniquingKeysWith: { first, _ in first })

        var added = 0
        for r in rows {
            guard let id = uuid(r["id"]), let exID = uuid(r["exercice_id"]) else { continue }
            let target: Ca3Period
            if let local = byKey[id] {
                target = local
            } else {
                let p = Ca3Period(exerciceID: exID, periode: str(r["periode"]))
                context.insert(p)
                byKey[id] = p
                target = p
                added += 1
            }
            target.tvaDeductible = dbl(r["tva_deductible"])
            target.creditM1 = dbl(r["credit_m1"])
            target.caHT = dbl(r["ca_ht"])
            target.ligne16 = dbl(r["ligne16"])
            target.ligne19 = dbl(r["ligne19"])
            target.ligne20 = dbl(r["ligne20"])
            // Chemin propre a chaque Mac : on ne remplace que s'il est vide.
            if target.docPath.isEmpty {
                target.docName = str(r["doc_name"])
                target.docPath = str(r["doc_path"])
            }
        }
        print("  ✅ TVA périodes: \(added) ajoutées")
    }

    private func loadImmoInvoices(using context: ModelContext) async {
        guard let rows = await fetchRows("immo_invoices", label: "Factures immo") else { return }
        let locals = (try? context.fetch(FetchDescriptor<ImmoInvoice>())) ?? []
        var byID = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var added = 0
        for r in rows {
            guard let id = uuid(r["id"]), let exID = uuid(r["exercice_id"]) else { continue }
            let target: ImmoInvoice
            if let local = byID[id] {
                target = local
            } else {
                let f = ImmoInvoice(exerciceID: exID)
                f.id = id
                context.insert(f)
                byID[id] = f
                target = f
                added += 1
            }
            target.date = date(r["date"]) ?? target.date
            target.compte = str(r["compte"])
            target.designation = str(r["designation"])
            target.montant = dbl(r["montant"])
            target.ordre = int(r["ordre"])
            if target.docPath.isEmpty {
                target.docName = str(r["doc_name"])
                target.docPath = str(r["doc_path"])
            }
        }
        print("  ✅ Factures immo: \(added) ajoutées")
    }

    private func loadImmoAssetsMerged(using context: ModelContext) async {
        guard let rows = await fetchRows("immo_assets", label: "Immobilisations") else { return }
        let locals = (try? context.fetch(FetchDescriptor<ImmoAsset>())) ?? []
        var byID = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var added = 0
        for r in rows {
            guard let id = uuid(r["id"]), let exID = uuid(r["exercice_id"]) else { continue }
            let target: ImmoAsset
            if let local = byID[id] {
                target = local
            } else {
                let a = ImmoAsset(exerciceID: exID)
                a.id = id
                context.insert(a)
                byID[id] = a
                target = a
                added += 1
            }
            target.compte = str(r["compte"])
            target.numeroImmo = str(r["numero_immo"])
            target.libelle = str(r["libelle"])
            target.montantHT = dbl(r["montant_ht"])
            target.dateAcquisition = date(r["date_acquisition"]) ?? target.dateAcquisition
            target.tauxAmort = dbl(r["taux_amort"])
            target.amortAnterieur = dbl(r["amort_anterieur"])
            target.amortExercice = dbl(r["amort_exercice"])
            target.ordre = int(r["ordre"])
        }
        print("  ✅ Immobilisations: \(added) ajoutées")
    }

    private func loadClass2Movements(using context: ModelContext) async {
        guard let rows = await fetchRows("class2_movements", label: "Mouvements classe 2") else { return }
        let locals = (try? context.fetch(FetchDescriptor<Class2Movement>())) ?? []
        var byID = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var added = 0
        for r in rows {
            guard let id = uuid(r["id"]), let exID = uuid(r["exercice_id"]) else { continue }
            let target: Class2Movement
            if let local = byID[id] {
                target = local
            } else {
                let m = Class2Movement(exerciceID: exID)
                m.id = id
                context.insert(m)
                byID[id] = m
                target = m
                added += 1
            }
            target.date = date(r["date"]) ?? target.date
            target.compte = str(r["compte"])
            target.libelle = str(r["libelle"])
            target.complement = str(r["complement"])
            target.debit = dbl(r["debit"])
            target.credit = dbl(r["credit"])
            target.ordre = int(r["ordre"])
        }
        print("  ✅ Mouvements classe 2: \(added) ajoutés")
    }

    private func loadCycleRules(using context: ModelContext) async {
        guard let rows = await fetchRows("account_cycle_rules", label: "Règles de cycle") else { return }
        let locals = (try? context.fetch(FetchDescriptor<AccountCycleRule>())) ?? []
        var byKey = Dictionary(locals.map {
            (Self.stableID($0.dossierID.pg, $0.accountNumber), $0)
        }, uniquingKeysWith: { first, _ in first })

        var added = 0
        for r in rows {
            guard let id = uuid(r["id"]), let dosID = uuid(r["dossier_id"]) else { continue }
            let cycleRaw = str(r["cycle_raw"])
            if let local = byKey[id] {
                local.cycleRaw = cycleRaw
            } else {
                let cycle = RevisionCycle(rawValue: cycleRaw) ?? .nonClasse
                let rule = AccountCycleRule(dossierID: dosID,
                                            accountNumber: str(r["account_number"]),
                                            cycle: cycle)
                context.insert(rule)
                byKey[id] = rule
                added += 1
            }
        }
        print("  ✅ Règles de cycle: \(added) ajoutées")
    }

    // MARK: - Suppressions

    /// Supprime une ligne sur Supabase apres une suppression locale, pour
    /// eviter qu'elle ne reapparaisse a la synchronisation suivante.
    func deleteRemote(table: String, id: UUID) async {
        do {
            let url = URL(string: "\(baseURL)/rest/v1/\(table)?id=eq.\(id.pg)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, ![200, 204, 404].contains(http.statusCode) {
                print("⚠️ Suppression \(table): HTTP \(http.statusCode)")
            }
        } catch {
            print("⚠️ Suppression \(table): \(error.localizedDescription)")
        }
    }
}
