import Foundation
import SwiftData

struct iCloudSync {
    static let containerID = "iCloud.PlanB.RevisionVEB"

    static var iCloudDocumentsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: containerID)?.appendingPathComponent("Documents", isDirectory: true)
    }

    static func exportDatabase(from container: ModelContainer) -> Result<URL, Error> {
        guard let iCloudURL = iCloudDocumentsURL else {
            return .failure(NSError(domain: "iCloudSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud Drive non disponible"]))
        }

        do {
            try FileManager.default.createDirectory(at: iCloudURL, withIntermediateDirectories: true)

            let exportURL = iCloudURL.appendingPathComponent("RevisionVEB-export-\(Date().formatted(date: .numeric, time: .shortened)).db")

            // Exporter toutes les données
            let context = ModelContext(container)
            var allData: [String: Any] = [:]

            // Dossiers
            let dossiers = try context.fetch(FetchDescriptor<Dossier>())
            allData["dossiers"] = dossiers.map { ["id": $0.id.uuidString, "nom": $0.nom, "ordre": $0.ordre] }

            // Exercices
            let exercices = try context.fetch(FetchDescriptor<Exercice>())
            allData["exercices"] = exercices.map { ["id": $0.id.uuidString, "dossierID": $0.dossierID.uuidString, "libelle": $0.libelle, "dateCloture": $0.dateCloture.timeIntervalSince1970] }

            // Comptes
            let accounts = try context.fetch(FetchDescriptor<BalanceAccount>())
            allData["accounts"] = accounts.count

            // Encoder et sauvegarder
            let json = try JSONSerialization.data(withJSONObject: allData, options: [.prettyPrinted, .sortedKeys])
            try json.write(to: exportURL)

            print("✅ Export vers iCloud réussi: \(exportURL.lastPathComponent)")
            return .success(exportURL)
        } catch {
            print("❌ Erreur export: \(error)")
            return .failure(error)
        }
    }

    static func checkiCloudAvailable() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil && iCloudDocumentsURL != nil
    }

    static func getiCloudExports() -> [URL]? {
        guard let iCloudURL = iCloudDocumentsURL else { return nil }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: iCloudURL, includingPropertiesForKeys: nil)
            return files.filter { $0.lastPathComponent.contains("RevisionVEB-export") }.sorted { $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date(timeIntervalSince1970: 0) > $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date(timeIntervalSince1970: 0) }
        } catch {
            print("⚠️  Erreur lecture iCloud: \(error)")
            return nil
        }
    }
}
