# 📦 Structure du Projet PLANB Audit

## Vue d'ensemble

```
RevisionVEB/
├── 📱 App
│   ├── RevisionVEBApp.swift          # Point d'entrée SwiftUI
│   └── ContentView.swift             # Navigation principale (sidebar)
│
├── 🗂️ Models/
│   ├── Invoice.swift                 # Modèle Facture + Enums
│   ├── AuditResult.swift             # Résultats d'audit + Enums
│   └── ImportLog.swift               # Logs d'import + Enums
│
├── 🛠️ Services/
│   ├── AuditEngine.swift             # Moteur d'audit (5 règles Cycle E)
│   ├── ImportManager.swift           # Import PDF/Excel
│   └── ExportManager.swift           # Export CSV
│
├── 🎨 Views/
│   ├── DashboardView.swift           # Vue d'ensemble + stats
│   ├── ImportView.swift              # Interface d'import (drag-drop)
│   ├── CycleFournisseursView.swift   # Cycle E complet (3 tabs)
│   └── SettingsView.swift            # Réglages + données démo
│
├── 🧰 Utilities/
│   └── SampleDataGenerator.swift     # Générateur de données test
│
├── 📄 Documentation
│   ├── README.md                     # Doc principale
│   └── QUICKSTART.md                 # Guide démarrage rapide
│
└── ⚙️ Tests/
    ├── RevisionVEBTests.swift
    └── RevisionVEBUITests.swift
```

---

## 📱 App Layer

### RevisionVEBApp.swift
**Rôle** : Bootstrap de l'application

**Responsabilités** :
- Initialise le ModelContainer SwiftData
- Configure le schema (Invoice, AuditResult, ImportLog)
- Injecte le modelContext dans toute l'app
- Définit les commandes macOS (Cmd+N)

**Key Points** :
```swift
Schema([Invoice.self, AuditResult.self, ImportLog.self])
ModelConfiguration(isStoredInMemoryOnly: false) // Persistance SQLite
```

### ContentView.swift
**Rôle** : Navigation principale

**Responsabilités** :
- Sidebar avec 7 sections
- NavigationSplitView (macOS-style)
- Routing vers les vues détaillées

**Sections** :
1. Dashboard
2. Import
3. Cycle B (placeholder Phase 2)
4. Cycle E ✅
5. Cycle H (placeholder Phase 2)
6. Cycle I (placeholder Phase 2)
7. Réglages

---

## 🗂️ Models Layer

### Invoice.swift
**Entités** :
- `Invoice` : Modèle principal (@Model SwiftData)
- `InvoiceStatus` : 6 états possibles
- `AuditCycle` : 4 cycles (B, E, H, I)
- `Restaurant` : Freddy, Bonbao

**Propriétés clés** :
```swift
id: UUID
number: String              // N° facture
date: Date                  // Date émission
supplier: String            // Nom fournisseur
supplierCode: String        // Code Cegid
netAmount: Double           // HT
vatRate: Double             // Taux TVA (0.20 = 20%)
grossAmount: Double         // TTC
paymentDate: Date?          // Date de paiement (optionnel)
status: InvoiceStatus       // État actuel
cycle: AuditCycle           // B/E/H/I
sourceFile: String          // Nom du fichier source
restaurant: Restaurant      // Freddy/Bonbao
```

### AuditResult.swift
**Entités** :
- `AuditResult` : Résultat d'un contrôle
- `AuditStatus` : Passed, Warning, Failed
- `Severity` : Info, Warning, Critical

**Propriétés clés** :
```swift
ruleId: String              // "E.1", "E.2", etc.
ruleName: String            // "Matching facture"
invoiceId: UUID?            // Lien vers la facture
invoiceNumber: String       // N° pour affichage
status: AuditStatus         // ✅⚠️❌
details: String             // Message explicatif
variance: Double            // Écart en €
cycle: AuditCycle           // Cycle testé
severity: Severity          // Niveau de gravité
```

### ImportLog.swift
**Entités** :
- `ImportLog` : Journal d'un import
- `FileType` : 7 types de fichiers supportés
- `ImportStatus` : Pending, Success, PartialSuccess, Failed

**Propriétés clés** :
```swift
fileName: String            // "balance_juin.csv"
fileType: FileType          // Type de fichier
status: ImportStatus        // Résultat
recordsCount: Int           // Total traité
successCount: Int           // Réussis
errorCount: Int             // Échoués
timestamp: Date             // Date/heure
errorDetails: String        // Message d'erreur
restaurant: Restaurant      // Restaurant cible
```

---

## 🛠️ Services Layer

### AuditEngine.swift
**Rôle** : Moteur d'audit Cycle E

**Méthodes publiques** :
```swift
runFullAuditCycleE() async -> [AuditResult]
```

**5 règles implémentées** :
1. `auditMatchingInvoices()` - E.1
2. `auditVATCalculation()` - E.2
3. `auditSupplierCodes()` - E.3
4. `auditPaymentDelay()` - E.4
5. `auditDuplicateInvoices()` - E.5

**Logique** :
- Fetch toutes les invoices du Cycle E
- Lance les 5 règles en parallèle (async let)
- Crée un AuditResult par facture testée
- Sauvegarde dans SwiftData
- Retourne les résultats pour affichage

**Example E.2 (VAT)** :
```swift
let expectedGross = netAmount * (1 + vatRate)
let variance = abs(expectedGross - grossAmount)
if variance > 0.01 {
    // ❌ Anomalie
}
```

### ImportManager.swift
**Rôle** : Import de fichiers PDF et Excel

**Méthodes publiques** :
```swift
importInvoicePDF(url: URL, restaurant: Restaurant) async -> ImportLog
importBalanceExcel(url: URL, restaurant: Restaurant) async -> ImportLog
```

**Workflow PDF** :
1. PDFDocument(url:) pour lire le PDF
2. Extraction texte page par page
3. Parsing avec patterns (regex basique)
4. Création Invoice
5. Insert dans SwiftData
6. Création ImportLog

**Workflow Excel (CSV)** :
1. Lecture contenu texte
2. Split par lignes et tabulations
3. Parsing colonnes attendues
4. Validation formats (dates, nombres)
5. Insert batch dans SwiftData
6. ImportLog avec compteurs

**Format CSV attendu** :
```
Date\tN° Facture\tFournisseur\tCode\tHT\tTVA\tTTC
```

### ExportManager.swift
**Rôle** : Export des résultats en CSV

**Méthodes publiques** :
```swift
exportCycleEResults() async -> URL?      // Résultats audit
exportInvoicesMaster() async -> URL?     // Maîtresse factures
exportSynthesis() async -> URL?          // Synthèse globale
openExportedFile(_ url: URL)             // Ouvre dans app par défaut
```

**Format Export** :
- CSV avec séparateurs virgules
- Encodage UTF-8
- Headers explicites
- Sauvegarde dans Temporary Directory
- Ouverture automatique via NSWorkspace

---

## 🎨 Views Layer

### DashboardView.swift
**Composants** :
- 3 StatCards (Factures, Imports, Anomalies)
- 2 GroupBox (Charts de conformité + Imports récents)
- Liste des anomalies critiques

**Queries SwiftData** :
```swift
@Query private var invoices: [Invoice]
@Query private var auditResults: [AuditResult]
@Query private var importLogs: [ImportLog]
```

**Charts** :
- BarChart avec Swift Charts
- 3 colonnes : Conformes, Alertes, Anomalies
- Couleurs : vert, orange, rouge

### ImportView.swift
**Features** :
- Drag & Drop zone (.onDrop)
- File picker natif (.fileImporter)
- Sélecteur restaurant (Picker)
- Progress bar pendant import
- Historique avec statuts colorés

**Supported Types** :
```swift
.fileImporter(allowedContentTypes: [.pdf, .commaSeparatedText, .tabSeparatedText])
```

### CycleFournisseursView.swift
**Structure** :
- Header avec boutons Audit + Export
- Picker 3 tabs (Résultats, Factures, Statistiques)
- TabView avec contenu dynamique

**Tab 1 - Résultats** :
- Table des AuditResults
- Filtres par statut
- Colonnes : Règle, Facture, Statut, Détails, Écart, Date

**Tab 2 - Factures** :
- Table des Invoices
- Colonnes : Restaurant, Date, N°, Fournisseur, HT, TVA, TTC, Statut

**Tab 3 - Statistiques** :
- Résumé global (4 stats)
- Détail par règle avec progress bars
- Distribution Passed/Warning/Failed

**Actions** :
```swift
runAudit() // Lance AuditEngine
exportAuditResults() // CSV résultats
exportInvoicesMaster() // CSV factures
exportSynthesis() // CSV synthèse
```

### SettingsView.swift
**Sections** :
1. Général (restaurant par défaut, audit auto)
2. Paramètres audit (tolérances, délais)
3. À propos (version, entreprise)
4. Gestion données (démo, reset)

**AppStorage** :
```swift
@AppStorage("defaultRestaurant") var defaultRestaurant = "Freddy"
@AppStorage("autoRunAudit") var autoRunAudit = false
@AppStorage("toleranceEuro") var toleranceEuro = 0.01
@AppStorage("maxPaymentDelay") var maxPaymentDelay = 90
```

---

## 🧰 Utilities

### SampleDataGenerator.swift
**Rôle** : Créer des données de test

**Méthode principale** :
```swift
static func generateSampleData(in context: ModelContext)
```

**Données générées** :
- 20 factures aléatoires (10 Freddy, 10 Bonbao)
- 6 fournisseurs variés
- Montants 100€ - 5000€
- Dates sur 6 mois
- 1 doublon (E.5)
- 1 TVA incorrecte (E.2)
- 1 code générique (E.3)
- Plusieurs retards (E.4)

**Logs d'import** :
- 1 succès récent
- 1 partiel
- 1 échec

---

## 🔗 Flux de données

### Import → Audit → Export

```
1. User drops file
   ↓
2. ImportManager.importBalanceExcel()
   ↓
3. Parsing + Create Invoices
   ↓
4. Insert SwiftData → @Query refresh
   ↓
5. User clicks "Lancer l'audit"
   ↓
6. AuditEngine.runFullAuditCycleE()
   ↓
7. 5 rules execute (async parallel)
   ↓
8. Create AuditResults
   ↓
9. Insert SwiftData → @Query refresh
   ↓
10. User clicks "Export"
    ↓
11. ExportManager.exportCycleEResults()
    ↓
12. Generate CSV → Save temp → Open
```

### Queries automatiques

SwiftData `@Query` déclenche un refresh automatique quand :
- Un objet est inséré (`modelContext.insert()`)
- Un objet est supprimé (`modelContext.delete()`)
- Un objet est modifié
- `modelContext.save()` est appelé

Pas besoin de `@Published` ou `objectWillChange` !

---

## 🎯 Points d'extension Phase 2

### Cycles B, H, I
**Fichiers à créer** :
- `Services/AuditEngineCycleB.swift`
- `Services/AuditEngineCycleH.swift`
- `Services/AuditEngineCycleI.swift`
- `Views/CycleTresorerieView.swift`
- `Views/CyclePersonnelView.swift`
- `Views/CycleFiscalView.swift`

### Excel natif (XLSX)
**Dépendance** :
- [CoreXLSX](https://github.com/CoreOffice/CoreXLSX) pour lecture
- [ZipFoundation](https://github.com/weichsel/ZIPFoundation) pour écriture

### Rapprochements bancaires
**Modèle** :
```swift
@Model
class BankTransaction {
    var date: Date
    var amount: Double
    var description: String
    var matched: Bool
    var invoice: Invoice?
}
```

### Dashboard avancé
**Charts 3D** :
- Swift Charts 3D (iOS 18+)
- Surface plots pour multi-périodes

---

## 📊 Performances

### SwiftData optimizations

**Fetch avec prédicats** :
```swift
#Predicate<Invoice> { $0.cycle == .fournisseurs }
```
→ SQL WHERE optimisé

**Sorting à la source** :
```swift
@Query(sort: \ImportLog.timestamp, order: .reverse)
```
→ SQL ORDER BY

**Lazy loading** :
SwiftData charge les relations à la demande

### Async audit
```swift
async let matching = auditMatchingInvoices()
async let vat = auditVATCalculation()
// ...
let allResults = await matching + vat + ...
```
→ Parallélisation des 5 règles

---

## 🐛 Debug Tips

### Voir le SQLite
```swift
print(modelContext.container.configurations.first?.url)
```
→ Ouvre dans DB Browser for SQLite

### Reset données
Settings → "Réinitialiser toutes les données"

### Logs d'import
```swift
print(importManager.lastError)
```

### Preview avec données
```swift
#Preview {
    DashboardView()
        .modelContainer(for: Invoice.self, inMemory: true)
        .onAppear {
            SampleDataGenerator.generateSampleData(in: context)
        }
}
```

---

**Questions ?** Consulte [README.md](README.md) et [QUICKSTART.md](QUICKSTART.md)
