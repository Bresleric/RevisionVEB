import Foundation
import SwiftData

@MainActor
class SupabaseSync {
    static let shared = SupabaseSync()

    private let baseURL: String
    private let anonKey: String

    init() {
        self.baseURL = SupabaseConfig.url
        self.anonKey = SupabaseConfig.anonKey
        print("📱 Supabase configuré: \(baseURL)")
    }

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Authorization": "Bearer \(anonKey)",
            "apikey": anonKey,
            "Content-Type": "application/json",
            "Prefer": "return=minimal"
        ]
        return URLSession(configuration: config)
    }

    // MARK: - Dossiers Sync

    func syncDossiers(from container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            let dossiers = try context.fetch(FetchDescriptor<Dossier>())

            guard !dossiers.isEmpty else {
                print("ℹ️ Aucun dossier à synchroniser")
                return
            }

            print("📤 Synchronisation de \(dossiers.count) dossier(s)...")

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

                do {
                    let (data, response) = try await session.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
                            print("✅ Dossier synced: \(dossier.nom)")
                        } else {
                            let errorMsg = String(data: data, encoding: .utf8) ?? ""
                            print("⚠️ Erreur \(httpResponse.statusCode): \(errorMsg)")
                        }
                    }
                } catch {
                    print("❌ Erreur sync dossier: \(error.localizedDescription)")
                }
            }
        } catch {
            print("❌ Erreur fetch dossiers: \(error)")
        }
    }

    // MARK: - Full Sync

    func fullSync(from container: ModelContainer) async {
        print("🚀 Début synchronisation Supabase...")
        print("   URL: \(baseURL)")
        await syncDossiers(from: container)
        print("✅ Synchronisation complétée!")
    }
}
