//
//  RevisionVEBApp.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import SwiftUI
import SwiftData

@main
struct RevisionVEBApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Invoice.self,
            AuditResult.self,
            ImportLog.self,
            BalanceAccount.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        func makeContainer() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [modelConfiguration])
        }

        // Verifie que le store est reellement lisible (une base corrompue ou d'un
        // ancien schema peut s'ouvrir mais echouer a la 1ere requete).
        func isHealthy(_ container: ModelContainer) -> Bool {
            let ctx = ModelContext(container)
            var d = FetchDescriptor<ImportLog>()
            d.fetchLimit = 1
            return (try? ctx.fetch(d)) != nil
        }

        if let container = try? makeContainer(), isHealthy(container) {
            return container
        }

        // Store incompatible / corrompu -> on le supprime et on recree (dev : pas de donnee precieuse).
        let url = modelConfiguration.url
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
        print("⚠️ Store reinitialise (schema incompatible ou corrompu).")

        do {
            return try makeContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouveau import...") {
                    // TODO: Show import window
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
