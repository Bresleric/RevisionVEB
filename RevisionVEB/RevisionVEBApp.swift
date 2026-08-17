//
//  RevisionVEBApp.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import SwiftUI
import SwiftData
import AppKit

/// Retient la fermeture de l'application le temps d'envoyer les modifications.
///
/// La synchronisation ne s'executait qu'a l'ouverture : une saisie suivie d'un
/// simple ⌘Q ne quittait jamais la machine, et l'utilisateur croyait
/// legitimement avoir synchronise. macOS n'accorde qu'un delai bref a une
/// application qui se ferme — d'ou `terminateLater`, qui suspend la fermeture
/// jusqu'a `reply(toApplicationShouldTerminate:)`, et le delai borne cote
/// `envoiFinal` pour qu'une panne reseau ne bloque jamais la fermeture.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Renseigne au demarrage par la scene principale.
    @MainActor static var container: ModelContainer?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let container = AppDelegate.container else { return .terminateNow }

        Task { @MainActor in
            await SupabaseSync.shared.envoiFinal(from: container)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct RevisionVEBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var sharedModelContainer: ModelContainer = {
        // Instantané de sécurité de la base existante AVANT toute migration.
        DataBackup.autoBackup()

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
            CirculationDocument.self,
            ImmoAsset.self,
            SoldesIntermedialres.self,
            PendingItem.self,
            SocialPayrollEntry.self,
            DsnAssiette.self,
            SocialReconciliation.self,
            SocialAnomaly.self,
            CyclePiece.self,
        ])

        // Supabase est la source de vérité. SwiftData = cache local synchronisé.
        print("📊 Source de vérité: Supabase")
        print("💾 Cache local: SwiftData")
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
            // Déclencher la migration CloudKit si nécessaire
            // CloudKitMigration.performMigrationIfNeeded(container: container)
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
                .onAppear {
                    // Le delegue en a besoin pour envoyer a la fermeture.
                    AppDelegate.container = sharedModelContainer
                    Task {
                        print("🔄 Synchronisation Supabase (sans perdre les justifications)")
                        await SupabaseSync.shared.fullSync(from: sharedModelContainer)
                        print("✅ Synchronisation réussie")

                        // Filet contre le plantage, l'arret force et la coupure :
                        // dans ces cas l'envoi a la fermeture ne s'execute pas.
                        // La perte est ainsi bornee a dix minutes de travail.
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(600))
                            await SupabaseSync.shared.envoiPeriodique(from: sharedModelContainer)
                        }
                    }
                }
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
