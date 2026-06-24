//
//  ImportView.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    let exerciceID: UUID

    @Environment(\.modelContext) private var modelContext
    @StateObject private var importManager: ImportManager
    @Query(sort: \ImportLog.timestamp, order: .reverse) private var importLogsRaw: [ImportLog]

    @State private var isDragOver = false
    @State private var showingFilePicker = false
    @State private var showingExcelAlert = false

    /// Historique limite a l'exercice courant.
    private var importLogs: [ImportLog] {
        importLogsRaw.filter { $0.exerciceID == exerciceID }
    }

    init(exerciceID: UUID) {
        self.exerciceID = exerciceID
        // Placeholder EN MEMOIRE uniquement : ne doit JAMAIS toucher le store disque
        // de l'app (sinon conflit de schema -> corruption). Le vrai modelContext de
        // l'environnement est injecte dans .onAppear.
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Invoice.self, AuditResult.self, ImportLog.self, BalanceAccount.self, AccountCycleRule.self,
            Dossier.self, Exercice.self, ControlState.self, AccountJustification.self,
            BankReconciliation.self, ReconItem.self, TvaCompteTaux.self, Ca3Entry.self, Ca3Period.self,
            ImmoInvoice.self,
            configurations: config
        )
        _importManager = StateObject(wrappedValue: ImportManager(modelContext: ModelContext(container)))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Import de données")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("La balance importée sera rattachée à l'exercice en cours.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                
                // Drop Zone
                GroupBox {
                    VStack(spacing: 20) {
                        if importManager.isImporting {
                            ProgressView(value: importManager.importProgress) {
                                Text("Import en cours...")
                            }
                            .frame(width: 300)
                        } else {
                            Image(systemName: isDragOver ? "arrow.down.circle.fill" : "arrow.down.doc")
                                .font(.system(size: 64))
                                .foregroundStyle(isDragOver ? .blue : .secondary)
                            
                            Text("Glisse tes fichiers ici")
                                .font(.headline)
                            
                            Text("PDF factures, CSV/TSV balance/bilan")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text("(Excel : exporte d'abord en CSV avec tabulations)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            
                            Button("Ou sélectionne un fichier") {
                                showingFilePicker = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                    .background(isDragOver ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                    handleDrop(providers)
                }
                .fileImporter(
                    isPresented: $showingFilePicker,
                    allowedContentTypes: [
                        .pdf,
                        .commaSeparatedText,
                        .tabSeparatedText,
                        .plainText,
                        .text,
                        .spreadsheet,
                        UTType(filenameExtension: "xlsx")!,
                        UTType(filenameExtension: "xls")!,
                        UTType(filenameExtension: "txt")!
                    ],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileSelection(result)
                }
                
                // Types de fichiers supportés
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Types de fichiers supportés")
                            .font(.headline)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(FileType.allCases, id: \.self) { fileType in
                                HStack {
                                    Image(systemName: fileType.icon)
                                        .foregroundStyle(.blue)
                                    Text(fileType.rawValue)
                                        .font(.subheadline)
                                    Spacer()
                                }
                                .padding(8)
                                .background(Color.blue.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // Historique des imports
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Historique des imports")
                            .font(.headline)
                        
                        if importLogs.isEmpty {
                            Text("Aucun import réalisé")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(importLogs) { log in
                                ImportLogRow(log: log)
                            }
                        }
                        
                        // Aide OneDrive/iCloud
                        if let lastLog = importLogs.first,
                           lastLog.status == .failed,
                           lastLog.errorDetails.contains("cloud") || lastLog.errorDetails.contains("OneDrive") {
                            Divider()
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("💡 Astuce : Fichier cloud")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("Si ton fichier est dans OneDrive/iCloud, copie-le d'abord sur ton Bureau, puis importe-le.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .background(Color(.windowBackgroundColor))
        .alert("Format Excel non supporté", isPresented: $showingExcelAlert) {
            Button("OK") { }
        } message: {
            Text("Les fichiers Excel (.xlsx/.xls) ne sont pas encore supportés.\n\nPour importer tes données:\n1. Ouvre ton fichier Excel\n2. Fichier → Enregistrer sous...\n3. Format: 'Texte (séparé par des tabulations) (.txt)' ou 'CSV UTF-8'\n4. Enregistre\n5. Importe le fichier .txt ou .csv généré")
        }
        .onAppear {
            // Inject real modelContext
            Task { @MainActor in
                importManager.modelContext = modelContext
            }
        }
    }
    
    // MARK: - Helpers
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            
            Task { @MainActor in
                await processFile(url)
            }
        }
        
        return true
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                print("❌ Aucun fichier sélectionné")
                return
            }
            
            print("✅ Fichier sélectionné: \(url.lastPathComponent)")
            print("📁 Chemin: \(url.path)")
            
            // IMPORTANT: Démarrer l'accès sécurisé AVANT de passer à processFile
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ Impossible d'obtenir l'accès au fichier (sandboxing)")
                return
            }
            
            Task {
                await processFile(url)
                // Libérer l'accès après traitement
                url.stopAccessingSecurityScopedResource()
            }
            
        case .failure(let error):
            print("❌ Erreur sélection fichier: \(error.localizedDescription)")
        }
    }
    
    private func processFile(_ url: URL) async {
        print("🔄 Traitement fichier: \(url.lastPathComponent)")
        let ext = url.pathExtension.lowercased()
        print("📄 Extension détectée: \(ext)")
        
        if ext == "pdf" {
            print("📋 Import PDF...")
            _ = await importManager.importInvoicePDF(url: url, restaurant: .freddy)
        } else if ext == "csv" || ext == "tsv" || ext == "txt" {
            print("📊 Import balance CSV/TSV/TXT...")
            _ = await importManager.importBalance(url: url, exerciceID: exerciceID)
        } else if ext == "xlsx" || ext == "xls" {
            print("⚠️ Excel natif pas encore activé")
            await MainActor.run {
                showingExcelAlert = true
            }
        } else {
            print("📊 Import par défaut (balance CSV/TSV)...")
            _ = await importManager.importBalance(url: url, exerciceID: exerciceID)
        }
        
        print("✅ Traitement terminé")
    }
    
    private func showExcelNotSupported() async {
        await MainActor.run {
            showingExcelAlert = true
        }
    }
}

// MARK: - Import Log Row

struct ImportLogRow: View {
    let log: ImportLog
    
    var body: some View {
        HStack {
            Image(systemName: log.fileType.icon)
                .foregroundStyle(statusColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(log.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text(log.restaurant.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    
                    Text("\(log.successCount)/\(log.recordsCount) réussis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(log.status.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor)
                
                Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var statusColor: Color {
        switch log.status {
        case .success: return .green
        case .partialSuccess: return .orange
        case .failed: return .red
        case .pending: return .blue
        }
    }
}

#Preview {
    ImportView(exerciceID: UUID())
        .modelContainer(for: Invoice.self, inMemory: true)
        .frame(width: 1200, height: 800)
}
