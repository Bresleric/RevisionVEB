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

    // MARK: - Dossiers Sync (UPSERT)

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
                request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                do {
                    let (data, response) = try await session.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
                            print("✅ Dossier synced: \(dossier.nom)")
                        } else if httpResponse.statusCode == 409 {
                            print("ℹ️ Dossier existe déjà: \(dossier.nom)")
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

    // MARK: - Load from Supabase

    func loadDossiersFromSupabase(to container: ModelContainer) async {
        do {
            let context = ModelContext(container)
            let existingDossiers = try context.fetch(FetchDescriptor<Dossier>())
            let existingIds = Set(existingDossiers.map { $0.id })

            print("📥 Chargement des dossiers depuis Supabase...")

            let url = URL(string: "\(baseURL)/rest/v1/dossiers")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var loaded = 0
                    for item in jsonArray {
                        if let idStr = item["id"] as? String,
                           let id = UUID(uuidString: idStr),
                           let nom = item["nom"] as? String,
                           let ordre = item["ordre"] as? Int {

                            if !existingIds.contains(id) {
                                let dossier = Dossier(id: id, nom: nom, ordre: ordre)
                                context.insert(dossier)
                                print("✅ Dossier chargé: \(nom)")
                                loaded += 1
                            }
                        }
                    }
                    if loaded > 0 {
                        try context.save()
                    }
                    print("📊 \(loaded) nouveaux dossiers, total Supabase: \(jsonArray.count)")
                }
            }
        } catch {
            print("⚠️ Erreur chargement Supabase: \(error.localizedDescription)")
        }
    }

    // MARK: - Full Sync

    func fullSync(from container: ModelContainer) async {
        print("🚀 Début synchronisation Supabase...")
        print("   URL: \(baseURL)")
        await loadDossiersFromSupabase(to: container)
        await syncDossiers(from: container)
        print("✅ Synchronisation complétée!")
    }
}
