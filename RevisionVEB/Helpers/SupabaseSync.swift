import Foundation
import SwiftData

actor SupabaseSync {
    static let shared = SupabaseSync()

    private let baseURL = SupabaseConfig.url
    private let anonKey = SupabaseConfig.anonKey

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Authorization": "Bearer \(anonKey)",
            "apikey": anonKey,
            "Content-Type": "application/json"
        ]
        return URLSession(configuration: config)
    }

    // MARK: - Dossiers Sync

    func syncDossiers(from container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            let dossiers = try context.fetch(FetchDescriptor<Dossier>())

            for dossier in dossiers {
                let payload: [String: Any] = [
                    "id": dossier.id.uuidString,
                    "nom": dossier.nom,
                    "ordre": dossier.ordre
                ]

                let url = URL(string: "\(baseURL)/rest/v1/dossiers")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (_, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                    print("✅ Dossier synced: \(dossier.nom)")
                }
            }
        } catch {
            print("❌ Sync error: \(error)")
        }
    }

    // MARK: - Exercices Sync

    func syncExercices(from container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            let exercices = try context.fetch(FetchDescriptor<Exercice>())

            for exercice in exercices {
                let payload: [String: Any] = [
                    "id": exercice.id.uuidString,
                    "dossier_id": exercice.dossierID.uuidString,
                    "libelle": exercice.libelle,
                    "date_cloture": ISO8601DateFormatter().string(from: exercice.dateCloture)
                ]

                let url = URL(string: "\(baseURL)/rest/v1/exercices")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (_, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                    print("✅ Exercice synced: \(exercice.libelle)")
                }
            }
        } catch {
            print("❌ Sync error: \(error)")
        }
    }

    // MARK: - Comptes Sync

    func syncBalanceAccounts(from container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            let accounts = try context.fetch(FetchDescriptor<BalanceAccount>())

            for account in accounts {
                let payload: [String: Any] = [
                    "id": account.id.uuidString,
                    "exercice_id": account.exerciceID.uuidString,
                    "account_number": account.accountNumber,
                    "account_code": account.accountCode,
                    "account_label": account.accountLabel,
                    "debit": account.debit,
                    "credit": account.credit,
                    "balance_n": account.balanceN,
                    "balance_n_minus_1": account.balanceNMinus1
                ]

                let url = URL(string: "\(baseURL)/rest/v1/balance_accounts")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                _ = try await session.data(for: request)
            }

            print("✅ \(accounts.count) comptes synced vers Supabase")
        } catch {
            print("❌ Sync error: \(error)")
        }
    }

    // MARK: - Full Sync

    func fullSync(from container: ModelContainer) async {
        print("🚀 Début synchronisation Supabase...")
        await syncDossiers(from: container)
        await syncExercices(from: container)
        await syncBalanceAccounts(from: container)
        print("✅ Synchronisation complétée!")
    }
}
