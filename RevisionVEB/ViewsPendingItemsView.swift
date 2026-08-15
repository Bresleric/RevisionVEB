//
//  ViewsPendingItemsView.swift
//  RevisionVEB
//
//  Module "Points en suspens" d'un cycle de revision : saisie de commentaires
//  et de taches a effectuer, avec statut, priorite, responsable et echeance.
//

import SwiftUI
import SwiftData

struct CyclePendingItemsView: View {
    let cycle: RevisionCycle
    let exerciceID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [PendingItem]

    /// Filtre d'affichage : masquer ou non les points clos.
    @State private var showClosed = false
    /// Point cree a l'instant : son titre prend le focus.
    @State private var focusedItemID: UUID?

    // MARK: - Donnees

    private var items: [PendingItem] {
        allItems
            .filter { $0.exerciceID == exerciceID && $0.cycleRaw == cycle.rawValue }
            .sorted { a, b in
                // Ouverts d'abord, puis priorite, puis echeance, puis date de creation.
                if a.statut.isClosed != b.statut.isClosed { return !a.statut.isClosed }
                if a.priorite.rank != b.priorite.rank { return a.priorite.rank < b.priorite.rank }
                switch (a.echeance, b.echeance) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
                return a.creeLe < b.creeLe
            }
    }

    private var visibleItems: [PendingItem] {
        showClosed ? items : items.filter { !$0.statut.isClosed }
    }

    private var openCount: Int { items.filter { !$0.statut.isClosed }.count }
    private var closedCount: Int { items.filter { $0.statut.isClosed }.count }
    private var lateCount: Int { items.filter { $0.isLate }.count }
    private var taskCount: Int { items.filter { $0.type == .tache && !$0.statut.isClosed }.count }

    // MARK: - Vue

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if items.isEmpty {
                PlaceholderView(
                    title: "Aucun point en suspens",
                    message: "Ajoute un commentaire ou une tâche à effectuer pour le cycle \(cycle.letter) — \(cycle.shortName)."
                )
            } else if visibleItems.isEmpty {
                PlaceholderView(
                    title: "Tous les points sont traités",
                    message: "\(closedCount) point\(closedCount > 1 ? "s" : "") clos. Active « Afficher les points clos » pour les revoir."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleItems) { item in
                            PendingItemCard(
                                item: item,
                                isFocused: focusedItemID == item.id,
                                onChange: { save() },
                                onDelete: { delete(item) }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Label("\(openCount) en suspens", systemImage: "tray.full")
                .foregroundStyle(openCount > 0 ? .primary : .secondary)
            if taskCount > 0 {
                Label("\(taskCount) tâche\(taskCount > 1 ? "s" : "")", systemImage: "checkmark.square")
                    .foregroundStyle(.purple)
            }
            if lateCount > 0 {
                Label("\(lateCount) en retard", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            if closedCount > 0 {
                Label("\(closedCount) traité\(closedCount > 1 ? "s" : "")", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }

            Spacer()

            if closedCount > 0 {
                Toggle("Afficher les points clos", isOn: $showClosed)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }

            Menu {
                Button { add(type: .commentaire) } label: {
                    Label("Commentaire", systemImage: PendingKind.commentaire.icon)
                }
                Button { add(type: .tache) } label: {
                    Label("Tâche à effectuer", systemImage: PendingKind.tache.icon)
                }
            } label: {
                Label("Ajouter", systemImage: "plus.circle.fill")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func add(type: PendingKind) {
        let item = PendingItem(exerciceID: exerciceID, cycleRaw: cycle.rawValue, type: type)
        modelContext.insert(item)
        save()
        focusedItemID = item.id
    }

    private func delete(_ item: PendingItem) {
        let id = item.id
        modelContext.delete(item)
        save()
        // Supprime aussi sur Supabase pour eviter que le point revienne a la
        // prochaine synchronisation.
        Task { await SupabaseSync.shared.deletePendingItemRemote(id: id) }
    }

    private func save() {
        try? modelContext.save()
    }
}

// MARK: - Carte d'un point en suspens

private struct PendingItemCard: View {
    @Bindable var item: PendingItem
    let isFocused: Bool
    let onChange: () -> Void
    let onDelete: () -> Void

    @FocusState private var titreFocused: Bool
    @State private var confirmDelete = false

    private var accent: Color {
        if item.statut.isClosed { return .secondary }
        if item.isLate { return .red }
        return item.priorite == .haute ? .red : item.type.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Ligne 1 : type, titre, priorite, statut, suppression
            HStack(spacing: 10) {
                Menu {
                    ForEach(PendingKind.allCases, id: \.self) { k in
                        Button { item.type = k; touch() } label: { Label(k.label, systemImage: k.icon) }
                    }
                } label: {
                    Image(systemName: item.type.icon)
                        .font(.title3)
                        .foregroundStyle(item.type.color)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Nature : \(item.type.label)")

                // Compte d'origine : sans lui, la liste perd son ancrage
                // comptable et devient un pense-bete.
                if !item.accountNumber.isEmpty {
                    Text(item.accountNumber)
                        .font(.caption).monospaced()
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                        .help("Compte \(item.accountNumber)")
                }

                TextField("Intitulé du point…", text: $item.titre)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.weight(.medium))
                    .focused($titreFocused)
                    .onChange(of: item.titre) { _, _ in touch() }

                Menu {
                    ForEach(PendingPriority.allCases, id: \.self) { p in
                        Button { item.priorite = p; touch() } label: { Label(p.rawValue, systemImage: p.icon) }
                    }
                } label: {
                    Label(item.priorite.rawValue, systemImage: item.priorite.icon)
                        .foregroundStyle(item.priorite.color)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Priorité")

                Menu {
                    ForEach(PendingStatus.allCases, id: \.self) { s in
                        Button { item.statut = s; touch() } label: { Label(s.rawValue, systemImage: s.icon) }
                    }
                } label: {
                    Label(item.statut.rawValue, systemImage: item.statut.icon)
                        .foregroundStyle(item.statut.color)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Statut")

                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Supprimer ce point")
            }

            // Ligne 2 : detail
            TextField("Détail, observation, travail à effectuer…", text: $item.detail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .lineLimit(2...6)
                .onChange(of: item.detail) { _, _ in touch() }

            // Ligne 3 : responsable, echeance
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "person").foregroundStyle(.secondary).font(.caption)
                    TextField("Responsable", text: $item.responsable)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .font(.callout)
                        .onChange(of: item.responsable) { _, _ in touch() }
                }

                if let echeance = item.echeance {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .foregroundStyle(item.isLate ? .red : .secondary).font(.caption)
                        DatePicker("", selection: Binding(
                            get: { echeance },
                            set: { item.echeance = $0; touch() }
                        ), displayedComponents: .date)
                        .labelsHidden()
                        .font(.callout)
                        Button { item.echeance = nil; touch() } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Retirer l'échéance")
                    }
                    if item.isLate {
                        Text("En retard").font(.caption).foregroundStyle(.red)
                    }
                } else {
                    Button {
                        item.echeance = Calendar.current.startOfDay(for: Date())
                        touch()
                    } label: {
                        Label("Échéance", systemImage: "calendar.badge.plus").font(.callout)
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("Dernière modification")
            }
        }
        .padding(12)
        .background(item.statut.isClosed ? Color.gray.opacity(0.04) : Color.gray.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle().fill(accent).frame(width: 3)
        }
        .cornerRadius(10)
        .opacity(item.statut.isClosed ? 0.65 : 1)
        .onAppear { if isFocused { titreFocused = true } }
        .confirmationDialog(
            "Supprimer ce point en suspens ?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive, action: onDelete)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(item.titre.isEmpty ? "Ce point n'a pas d'intitulé." : item.titre)
        }
    }

    private func touch() {
        item.updatedAt = Date()
        onChange()
    }
}
