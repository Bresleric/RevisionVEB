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
        // Instantané de sécurité de la base existante AVANT toute migration.
        DataBackup.autoBackup()

        // Vérifier la disponibilité iCloud AVANT de migrer vers CloudKit
        let hasICloud = FileManager.default.ubiquityIdentityToken != nil
        if !hasICloud {
            print("⚠️  Vous n'êtes pas connecté à iCloud. La synchronisation CloudKit ne fonctionnera pas.")
            print("    Allez dans Paramètres Système > [Utilisateur] > iCloud pour vous connecter.")
        }

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
            TvaCompteTaux.self,
            Ca3Entry.self,
            Ca3Period.self,
            ImmoInvoice.self,
            Class2Movement.self,
            ImmoAsset.self,
            SoldesIntermedialres.self,
        ])

        // Configurer le stockage DIRECTEMENT dans iCloud Drive pour vraie synchronisation
        var modelConfiguration: ModelConfiguration

        if let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let dbDir = iCloudURL.appendingPathComponent("RevisionVEB", isDirectory: true)
            try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            let dbURL = dbDir.appendingPathComponent("default.store")

            print("📱 Base de données partagée via iCloud Drive: \(dbURL.path)")
            modelConfiguration = ModelConfiguration(schema: schema, url: dbURL)
        } else {
            print("⚠️ iCloud Drive non disponible - utilisant stockage local")
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

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
            // Déclencher la migration CloudKit si nécessaire
            CloudKitMigration.performMigrationIfNeeded(container: container)
            return container
        }

        // Store incompatible/corrompu : on NE SUPPRIME JAMAIS. On SAUVEGARDE la base
        // (deplacement dans Backups/) puis on recree une base vierge. Les donnees
        // restent recuperables a partir de la sauvegarde.
        let url = modelConfiguration.url
        let fm = FileManager.default
        let backupDir = url.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let stamp = String(Int(Date().timeIntervalSince1970))
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: url.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = backupDir.appendingPathComponent("\(src.lastPathComponent).\(stamp).bak")
            try? fm.moveItem(at: src, to: dst)
        }
        print("⚠️ Store incompatible : sauvegardé dans Backups/ puis recréé. Données récupérables.")

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
