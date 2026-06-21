//
//  ContentView.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSection: NavigationSection? = .dashboard
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedSection: $selectedSection)
        } detail: {
            DetailContentView(section: selectedSection)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Navigation Section

enum NavigationSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case importData = "Import"
    case cycleTresorerie = "B - Trésorerie"
    case cycleFournisseurs = "E - Fournisseurs"
    case cyclePersonnel = "H - Personnel"
    case cycleFiscal = "I - Fiscal"
    case settings = "Réglages"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .importData: return "arrow.down.doc"
        case .cycleTresorerie: return "banknote"
        case .cycleFournisseurs: return "building.2"
        case .cyclePersonnel: return "person.2"
        case .cycleFiscal: return "doc.text"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedSection: NavigationSection?
    
    var body: some View {
        List(selection: $selectedSection) {
            Section("Vue d'ensemble") {
                NavigationLink(value: NavigationSection.dashboard) {
                    Label(NavigationSection.dashboard.rawValue, systemImage: NavigationSection.dashboard.icon)
                }
                NavigationLink(value: NavigationSection.importData) {
                    Label(NavigationSection.importData.rawValue, systemImage: NavigationSection.importData.icon)
                }
            }
            
            Section("Cycles comptables") {
                NavigationLink(value: NavigationSection.cycleTresorerie) {
                    Label(NavigationSection.cycleTresorerie.rawValue, systemImage: NavigationSection.cycleTresorerie.icon)
                }
                NavigationLink(value: NavigationSection.cycleFournisseurs) {
                    Label(NavigationSection.cycleFournisseurs.rawValue, systemImage: NavigationSection.cycleFournisseurs.icon)
                }
                NavigationLink(value: NavigationSection.cyclePersonnel) {
                    Label(NavigationSection.cyclePersonnel.rawValue, systemImage: NavigationSection.cyclePersonnel.icon)
                }
                NavigationLink(value: NavigationSection.cycleFiscal) {
                    Label(NavigationSection.cycleFiscal.rawValue, systemImage: NavigationSection.cycleFiscal.icon)
                }
            }
            
            Section {
                NavigationLink(value: NavigationSection.settings) {
                    Label(NavigationSection.settings.rawValue, systemImage: NavigationSection.settings.icon)
                }
            }
        }
        .navigationTitle("PLANB Audit")
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
    }
}

// MARK: - Detail Content

struct DetailContentView: View {
    let section: NavigationSection?
    
    var body: some View {
        Group {
            switch section {
            case .dashboard:
                DashboardView()
            case .importData:
                ImportView()
            case .cycleFournisseurs:
                CycleFournisseursView()
            case .cycleTresorerie:
                PlaceholderView(title: "Cycle B - Trésorerie", message: "À implémenter en Phase 2")
            case .cyclePersonnel:
                PlaceholderView(title: "Cycle H - Personnel", message: "À implémenter en Phase 2")
            case .cycleFiscal:
                PlaceholderView(title: "Cycle I - Fiscal", message: "À implémenter en Phase 2")
            case .settings:
                SettingsView()
            case .none:
                PlaceholderView(title: "PLANB Audit", message: "Sélectionne une section dans la sidebar")
            }
        }
    }
}

// MARK: - Placeholder

struct PlaceholderView: View {
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Invoice.self, inMemory: true)
}
