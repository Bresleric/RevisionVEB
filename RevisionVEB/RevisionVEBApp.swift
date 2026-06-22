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
            AccountCycleRule.self,
            Dossier.self,
            Exercice.self,
            ControlState.self,
            AccountJustification.self,
            BankReconciliation.self,
            ReconItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        func makeContainer() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [modelConfiguration])
        }

        // Verifie que le store est reellement lisible (une base corrompue ou d'un
        // ancien schema peut s'ouvrir mais echouer a la 1ere requete).
        func isHealthy(_ container: ModelContainer) -> Bool {
            let ctx = ModelContext(container)
            var logs = FetchDescriptor<ImportLog>();         logs.fetchLimit = 1
            var rules = FetchDescriptor<AccountCycleRule>();  rules.fetchLimit = 1
            return (try? ctx.fetch(logs)) != nil && (try? ctx.fetch(rules)) != nil
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
            RootView()
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
