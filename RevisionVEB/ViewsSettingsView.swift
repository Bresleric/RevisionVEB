//
//  SettingsView.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("defaultRestaurant") private var defaultRestaurant = "Freddy"
    @AppStorage("autoRunAudit") private var autoRunAudit = false
    @AppStorage("toleranceEuro") private var toleranceEuro = 0.01
    @AppStorage("maxPaymentDelay") private var maxPaymentDelay = 90
    
    @State private var showingResetAlert = false
    @State private var showingDemoDataAlert = false
    @State private var showingAdoptAlert = false
    @State private var adoptionEnCours = false
    @State private var syncEnCours = false
    @State private var derniereSync: Date?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Réglages")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Configure l'application selon tes besoins")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                
                // Général
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Général")
                            .font(.headline)
                        
                        Picker("Restaurant par défaut", selection: $defaultRestaurant) {
                            Text("Freddy").tag("Freddy")
                            Text("Chez Tante Liesel").tag("Chez Tante Liesel")
                        }
                        .pickerStyle(.segmented)
                        
                        Toggle("Lancer l'audit automatiquement après import", isOn: $autoRunAudit)
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // Paramètres d'audit
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Paramètres d'audit")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tolérance sur les montants (€)")
                                .font(.subheadline)
                            
                            HStack {
                                Slider(value: $toleranceEuro, in: 0...1, step: 0.01)
                                Text("\(String(format: "%.2f", toleranceEuro))€")
                                    .frame(width: 60, alignment: .trailing)
                                    .monospaced()
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Délai maximal de paiement (jours)")
                                .font(.subheadline)
                            
                            HStack {
                                Slider(value: Binding(
                                    get: { Double(maxPaymentDelay) },
                                    set: { maxPaymentDelay = Int($0) }
                                ), in: 30...180, step: 10)
                                Text("\(maxPaymentDelay)j")
                                    .frame(width: 60, alignment: .trailing)
                                    .monospaced()
                            }
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // À propos
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("À propos")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Version")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("1.0.0 (MVP)")
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Entreprise")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("PLANB SARL")
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Restaurants")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Freddy & Chez Tante Liesel")
                                    .fontWeight(.medium)
                            }
                        }
                        
                        Divider()
                        
                        Text("Application d'audit comptable automatisé pour les cycles B, E, H, I")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // Données
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Gestion des données")
                            .font(.headline)
                        
                        Button {
                            showingDemoDataAlert = true
                        } label: {
                            Label("Générer données de démo", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.bordered)
                        
                        Text("Crée 20+ factures de test pour explorer l'app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Divider()

                        // La synchronisation ne tourne qu'au demarrage : sans ce
                        // bouton, une saisie ne quitte la machine qu'au lancement
                        // suivant, et on croit avoir synchronise alors que rien
                        // n'est parti.
                        Button {
                            syncEnCours = true
                            Task {
                                await SupabaseSync.shared.fullSync(from: modelContext.container, force: true)
                                derniereSync = Date()
                                syncEnCours = false
                            }
                        } label: {
                            Label(syncEnCours ? "Synchronisation en cours…" : "Synchroniser maintenant",
                                  systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(syncEnCours)

                        if let d = derniereSync {
                            Text("Dernière synchronisation manuelle : \(d.formatted(date: .omitted, time: .standard))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Envoie tes saisies et récupère celles de l'autre Mac. À faire avant de quitter, sinon ton travail ne part qu'au prochain démarrage.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        // Sortie de secours quand deux Macs ont divergé : plutôt
                        // que de réconcilier ligne à ligne, on déclare Supabase
                        // seul dépositaire et on jette ce que cette machine
                        // croyait savoir.
                        Button {
                            showingAdoptAlert = true
                        } label: {
                            Label(adoptionEnCours ? "Programmé au prochain démarrage" : "Recharger tout depuis Supabase",
                                  systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        }
                        .buttonStyle(.bordered)
                        .disabled(adoptionEnCours)

                        Text("Abandonne le cache de ce Mac et le reconstruit depuis Supabase, sans rien envoyer au préalable. À utiliser quand deux machines divergent : celle-ci adoptera la version de l'autre. Prend effet au redémarrage de l'application.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        Button(role: .destructive) {
                            showingResetAlert = true
                        } label: {
                            Label("Réinitialiser toutes les données", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        
                        Text("⚠️ Cette action est irréversible")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .background(Color(.windowBackgroundColor))
        .alert("Générer données de démo ?", isPresented: $showingDemoDataAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Générer", role: .destructive) {
                generateDemoData()
            }
        } message: {
            Text("Cela va remplacer toutes les données actuelles par des données de test.")
        }
        .alert("Recharger tout depuis Supabase ?", isPresented: $showingAdoptAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Programmer et quitter", role: .destructive) {
                SupabaseSync.rechargementDemande = true
                adoptionEnCours = true
            }
        } message: {
            Text("Au prochain démarrage, ce Mac abandonnera son cache et adoptera intégralement la version présente sur Supabase.\n\n"
                 + "Il n'enverra rien au préalable — c'est tout l'intérêt : la synchronisation démarre avec l'application et pousse avant de charger, "
                 + "si bien qu'une machine divergente réécrit ses valeurs sur Supabase avant qu'on ait pu intervenir.\n\n"
                 + "Toute saisie faite ici et pas encore synchronisée sera perdue. Le grand livre 641 et les factures scannées ne sont pas concernés : "
                 + "ils ne sont pas synchronisés et restent en place.\n\n"
                 + "Quitte l'application puis relance-la pour que ça prenne effet.")
        }
        .alert("Réinitialiser les données ?", isPresented: $showingResetAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Réinitialiser", role: .destructive) {
                resetAllData()
            }
        } message: {
            Text("Cette action est irréversible. Toutes les factures, audits et imports seront supprimés.")
        }
    }
    
    private func generateDemoData() {
        SampleDataGenerator.generateSampleData(in: modelContext)
    }
    
    private func resetAllData() {
        let invoiceDescriptor = FetchDescriptor<Invoice>()
        if let invoices = try? modelContext.fetch(invoiceDescriptor) {
            for invoice in invoices {
                modelContext.delete(invoice)
            }
        }
        
        let auditDescriptor = FetchDescriptor<AuditResult>()
        if let results = try? modelContext.fetch(auditDescriptor) {
            for result in results {
                modelContext.delete(result)
            }
        }
        
        let logDescriptor = FetchDescriptor<ImportLog>()
        if let logs = try? modelContext.fetch(logDescriptor) {
            for log in logs {
                modelContext.delete(log)
            }
        }
        
        try? modelContext.save()
    }
}

#Preview {
    SettingsView()
        .frame(width: 800, height: 600)
}
