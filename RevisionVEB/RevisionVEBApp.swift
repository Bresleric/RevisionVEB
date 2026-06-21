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

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
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
