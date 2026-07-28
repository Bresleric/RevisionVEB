//
//  SupabaseStorage.swift
//  RevisionVEB
//
//  Depot distant des pieces justificatives.
//
//  Les pieces sont copiees dans le conteneur local de l'app, et la base ne
//  retient qu'un chemin absolu — inexploitable depuis l'autre Mac, dont le
//  conteneur est ailleurs et ne contient pas le fichier. Le fichier lui-meme
//  transite donc par Supabase Storage, et le chemin distant se deduit de
//  l'exercice et du nom de fichier : aucune colonne supplementaire.
//

import Foundation
import CryptoKit

@MainActor
enum SupabaseStorage {
    static let bucket = "justificatifs"

    private static var base: String { "\(SupabaseConfig.url)/storage/v1/object" }

    private static var headers: [String: String] {
        [
            "Authorization": "Bearer \(SupabaseConfig.anonKey)",
            "apikey": SupabaseConfig.anonKey
        ]
    }

    /// Chemin distant d'une piece : `<exercice>/<empreinte>-<nom assaini>`.
    ///
    /// Storage refuse les caracteres non ASCII dans un nom d'objet : « Tab amort
    /// pret FDC.pdf » etait rejete en `InvalidKey` a cause de son accent, et la
    /// piece restait introuvable depuis l'autre Mac. Le nom est donc replie en
    /// ASCII.
    ///
    /// Deux pieces ne differant que par leurs accents produiraient alors la meme
    /// clef, et la seconde ecraserait la premiere. On prefixe donc une empreinte
    /// du nom d'origine. Le calcul ne depend que du nom de fichier : les deux
    /// Macs aboutissent a la meme clef sans rien stocker de plus.
    static func remotePath(forLocalPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let file = url.lastPathComponent
        let exercice = url.deletingLastPathComponent().lastPathComponent
        guard !file.isEmpty, let id = UUID(uuidString: exercice) else { return nil }
        return remotePath(exerciceID: id, fileName: file)
    }

    static func remotePath(exerciceID: UUID, fileName: String) -> String {
        // Le systeme de fichiers macOS restitue les noms en forme decomposee :
        // on recompose avant de calculer l'empreinte, sinon deux machines
        // pourraient hacher deux representations du meme nom.
        let name = fileName.precomposedStringWithCanonicalMapping
        let digest = SHA256.hash(data: Data(name.utf8))
        let stamp = digest.prefix(4).map { String(format: "%02x", $0) }.joined()

        let folded = name.folding(options: [.diacriticInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
        let safe = String(folded.map { ch in
            ch.isASCII && (ch.isLetter || ch.isNumber || "-_. ".contains(ch)) ? ch : "_"
        }.prefix(120))

        return "\(exerciceID.uuidString)/\(stamp)-\(safe)"
    }

    private static func encoded(_ path: String) -> String {
        path.split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-_.~"))) ?? String($0) }
            .joined(separator: "/")
    }

    // MARK: - Envoi

    /// Depose une piece sur Supabase. `upsert` remplace une version existante.
    @discardableResult
    static func upload(localPath: String, remotePath path: String) async -> Bool {
        guard let data = FileManager.default.contents(atPath: localPath) else { return false }

        var request = URLRequest(url: URL(string: "\(base)/\(bucket)/\(encoded(path))")!)
        request.httpMethod = "POST"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.setValue(mimeType(for: localPath), forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if [200, 201].contains(http.statusCode) { return true }
            let detail = String(data: body, encoding: .utf8) ?? ""
            SyncDiagnostics.record(table: "storage/\(bucket)", status: http.statusCode, body: detail)
            return false
        } catch {
            print("⚠️ Envoi pièce: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Réception

    /// Récupère une pièce absente en local. Renvoie le chemin local du fichier.
    static func download(remotePath path: String, to localURL: URL) async -> URL? {
        var request = URLRequest(url: URL(string: "\(base)/\(bucket)/\(encoded(path))")!)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: localURL, options: .atomic)
            return localURL
        } catch {
            print("⚠️ Réception pièce: \(error.localizedDescription)")
            return nil
        }
    }

    /// Chemins déjà présents dans le bucket, pour ne pas renvoyer deux fois.
    static func existingPaths(exerciceID: UUID) async -> Set<String> {
        var request = URLRequest(url: URL(string: "\(SupabaseConfig.url)/storage/v1/object/list/\(bucket)")!)
        request.httpMethod = "POST"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "prefix": exerciceID.uuidString,
            "limit": 1000
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return [] }
            return Set(rows.compactMap { $0["name"] as? String }
                           .map { "\(exerciceID.uuidString)/\($0)" })
        } catch {
            return []
        }
    }

    private static func mimeType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "pdf":          return "application/pdf"
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "csv":          return "text/csv"
        case "txt":          return "text/plain"
        case "xlsx":         return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        default:             return "application/octet-stream"
        }
    }
}
