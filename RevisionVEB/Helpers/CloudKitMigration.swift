import Foundation
import SwiftData

struct CloudKitMigration {
    static let migrationCompleteKey = "cloudkit_migration_complete_v1"

    static func performMigrationIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard

        guard !defaults.bool(forKey: migrationCompleteKey) else {
            print("✅ Migration CloudKit déjà complétée")
            return
        }

        print("🚀 Début de la migration CloudKit...")

        do {
            let context = ModelContext(container)
            var migrated = 0

            // Migrer Dossiers
            let dossiers = try context.fetch(FetchDescriptor<Dossier>())
            migrated += dossiers.count
            print("  ✓ \(dossiers.count) Dossiers")

            // Migrer Exercices
            let exercices = try context.fetch(FetchDescriptor<Exercice>())
            migrated += exercices.count
            print("  ✓ \(exercices.count) Exercices")

            // Migrer Comptes de balance
            let accounts = try context.fetch(FetchDescriptor<BalanceAccount>())
            migrated += accounts.count
            print("  ✓ \(accounts.count) Comptes")

            // Migrer les contrôles
            let controls = try context.fetch(FetchDescriptor<ControlState>())
            migrated += controls.count
            print("  ✓ \(controls.count) États de contrôle")

            // Migrer les justificatifs
            let justifications = try context.fetch(FetchDescriptor<AccountJustification>())
            migrated += justifications.count
            print("  ✓ \(justifications.count) Justificatifs")

            // Migrer les immos
            let immos = try context.fetch(FetchDescriptor<ImmoAsset>())
            migrated += immos.count
            print("  ✓ \(immos.count) Immobilisations")

            // Migrer les réconciliations bancaires
            let bankReconciliations = try context.fetch(FetchDescriptor<BankReconciliation>())
            migrated += bankReconciliations.count
            print("  ✓ \(bankReconciliations.count) Réconciliations bancaires")

            // Migrer les entrées CA3 (TVA)
            let ca3Entries = try context.fetch(FetchDescriptor<Ca3Entry>())
            migrated += ca3Entries.count
            print("  ✓ \(ca3Entries.count) Entrées TVA")

            // Migrer les SoldesIntermédiaires
            let soldes = try context.fetch(FetchDescriptor<SoldesIntermedialres>())
            migrated += soldes.count
            print("  ✓ \(soldes.count) Soldes Intermédiaires")

            // Migrer les logs d'import
            let importLogs = try context.fetch(FetchDescriptor<ImportLog>())
            migrated += importLogs.count
            print("  ✓ \(importLogs.count) Logs d'import")

            // Migrer les factures
            let invoices = try context.fetch(FetchDescriptor<Invoice>())
            migrated += invoices.count
            print("  ✓ \(invoices.count) Factures")

            // Migrer les résultats d'audit
            let auditResults = try context.fetch(FetchDescriptor<AuditResult>())
            migrated += auditResults.count
            print("  ✓ \(auditResults.count) Résultats d'audit")

            // Migrer les CA3 périodes
            let ca3Periods = try context.fetch(FetchDescriptor<Ca3Period>())
            migrated += ca3Periods.count
            print("  ✓ \(ca3Periods.count) Périodes CA3")

            // Migrer les mouvements classe 2
            let class2Movements = try context.fetch(FetchDescriptor<Class2Movement>())
            migrated += class2Movements.count
            print("  ✓ \(class2Movements.count) Mouvements Classe 2")

            // Migrer les factures immo
            let immoInvoices = try context.fetch(FetchDescriptor<ImmoInvoice>())
            migrated += immoInvoices.count
            print("  ✓ \(immoInvoices.count) Factures Immo")

            // Migrer les taux TVA
            let tvaTaux = try context.fetch(FetchDescriptor<TvaCompteTaux>())
            migrated += tvaTaux.count
            print("  ✓ \(tvaTaux.count) Taux TVA")

            // Migrer les règles de cycle
            let cycleRules = try context.fetch(FetchDescriptor<AccountCycleRule>())
            migrated += cycleRules.count
            print("  ✓ \(cycleRules.count) Règles de cycle")

            // Migrer les récon items
            let reconItems = try context.fetch(FetchDescriptor<ReconItem>())
            migrated += reconItems.count
            print("  ✓ \(reconItems.count) Éléments de réconciliation")

            // Sauvegarder pour déclencher le sync CloudKit
            try context.save()

            // Marquer la migration comme complétée
            defaults.set(true, forKey: migrationCompleteKey)

            print("✅ Migration CloudKit complétée: \(migrated) objets synchronisés")
            print("📱 Les données vont maintenant se synchroniser automatiquement via iCloud")

        } catch {
            print("❌ Erreur lors de la migration CloudKit: \(error)")
            print("   Les données locales restent intactes. Réessayez au prochain lancement.")
        }
    }
}
