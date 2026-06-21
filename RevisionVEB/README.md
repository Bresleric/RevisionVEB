# 🧾 PLANB Audit Comptable

Application macOS native pour l'audit comptable automatisé des restaurants PLANB SARL (Freddy & Bonbao).

## 🎯 Objectif

Automatiser les contrôles comptables mensuels selon les cycles A-M avec tolérance zéro sur les écarts financiers.

## ✨ Fonctionnalités (Phase 1 - MVP)

### Import de données
- ✅ Drag-drop de fichiers PDF (factures) et CSV/TSV (balance, bilan)
- ✅ Parsing automatique des factures
- ✅ Support multi-restaurants (Freddy, Bonbao)
- ✅ Historique des imports avec statuts

### Cycle E - Fournisseurs (5 règles)
- ✅ **E.1** : Matching factures PDF ↔ fichiers Cegid (N° + montant)
- ✅ **E.2** : Validation TVA (net × (1 + taux) = gross, tolérance 0.01€)
- ✅ **E.3** : Codes fournisseurs normalisés (éviter 00FOUR)
- ✅ **E.4** : Délai paiement < 90j (alerte > 120j)
- ✅ **E.5** : Détection doubles-factures (fenêtre 30j)

### Dashboard & Reporting
- ✅ Vue d'ensemble avec statistiques clés
- ✅ Graphiques de conformité
- ✅ Liste des anomalies récentes
- ✅ Historique des imports

### Export
- ✅ Export résultats audit (CSV)
- ✅ Export maîtresse factures (CSV)
- ✅ Export synthèse globale (CSV)

## 🏗️ Architecture

### Technologies
- **Frontend** : SwiftUI (macOS 13+)
- **Backend** : SwiftData (Core Data wrapper)
- **Parsing** : PDFKit (factures), Foundation (CSV)
- **Export** : CSV natif (Excel-compatible)

### Structure de fichiers

```
RevisionVEB/
├── Models/
│   ├── Invoice.swift           # Factures
│   ├── AuditResult.swift       # Résultats d'audit
│   └── ImportLog.swift         # Logs d'import
├── Services/
│   ├── AuditEngine.swift       # Moteur d'audit (5 règles Cycle E)
│   ├── ImportManager.swift     # Gestion imports PDF/Excel
│   └── ExportManager.swift     # Export CSV
├── Views/
│   ├── ContentView.swift       # Navigation principale
│   ├── DashboardView.swift     # Dashboard avec stats
│   ├── ImportView.swift        # Interface d'import
│   ├── CycleFournisseursView.swift  # Cycle E complet
│   └── SettingsView.swift      # Réglages
└── RevisionVEBApp.swift        # Point d'entrée
```

### Modèles de données

**Invoice**
- Informations facture : numéro, date, fournisseur, montants
- Statut : pending, matched, paid, overdue, disputed, canceled
- Cycle comptable : B, E, H, I
- Restaurant : Freddy, Bonbao

**AuditResult**
- Règle testée : ID, nom
- Statut : passed, warning, failed
- Détails et écart financier
- Sévérité : info, warning, critical

**ImportLog**
- Fichier importé : nom, type
- Statut : pending, success, partialSuccess, failed
- Compteurs : total, réussis, erreurs

## 🚀 Utilisation

### 1. Import de données
1. Va dans la section **Import**
2. Sélectionne le restaurant (Freddy/Bonbao)
3. Glisse-dépose tes fichiers :
   - PDF de factures
   - CSV/TSV de balance/bilan Cegid
4. L'import se fait automatiquement

### 2. Lancer un audit
1. Va dans **Cycle E - Fournisseurs**
2. Clique sur **Lancer l'audit**
3. Consulte les résultats dans les 3 onglets :
   - **Résultats audit** : détail de chaque contrôle
   - **Factures** : liste complète des factures
   - **Statistiques** : résumé par règle

### 3. Export des résultats
1. Clique sur le menu **Export**
2. Choisis :
   - Résultats audit (contrôles détaillés)
   - Maîtresse factures (toutes les factures)
   - Synthèse (vue globale)
3. Le fichier CSV s'ouvre automatiquement

## 📊 Format des fichiers d'import

### CSV Balance/Bilan
Format attendu (séparé par tabulation) :

```
Date       N° Facture  Fournisseur     Code    HT      TVA    TTC
01/06/2026 FAC001     Sysco France    SYS001  1000.00 0.20   1200.00
05/06/2026 FAC002     Metro          MET001  500.00  0.20   600.00
```

### PDF Factures
L'app extrait automatiquement :
- Numéro de facture
- Date
- Montants HT/TTC
- Nom du fournisseur

## ⚙️ Réglages

### Paramètres d'audit
- **Tolérance montants** : 0.01€ par défaut
- **Délai maximal paiement** : 90 jours par défaut
- **Restaurant par défaut** : Freddy/Bonbao
- **Audit automatique** : après import

## 🔮 Phase 2 (Roadmap)

- [ ] Cycle B - Trésorerie
- [ ] Cycle H - Personnel
- [ ] Cycle I - Fiscal
- [ ] Rapprochements bancaires
- [ ] Multi-périodes (N, N-1, N-2)
- [ ] Export Excel natif (XLSX)
- [ ] Règles d'audit personnalisées
- [ ] Dashboard avancé avec charts 3D

## 🛠️ Configuration technique

### Prérequis
- macOS 13.0+ (Ventura)
- Xcode 15.0+
- Swift 5.9+

### Build & Run
1. Ouvre `RevisionVEB.xcodeproj`
2. Sélectionne le target macOS
3. Cmd+R pour compiler et lancer

### Tests
```bash
# Tests unitaires
Cmd+U dans Xcode
```

## 📝 Notes

### Limites actuelles (MVP)
- Parsing PDF basique (à améliorer avec regex spécifiques)
- Export CSV uniquement (Excel natif en Phase 2)
- Cycles B/H/I non implémentés

### Points d'amélioration
1. Regex avancés pour parsing PDF multi-formats
2. Validation des codes fournisseurs contre référentiel
3. Rapprochement automatique avec extraits bancaires
4. Notifications push pour anomalies critiques

## 🎯 Philosophie

**Tolérance zéro** : Chaque écart compte. L'app détecte tout :
- Écarts de TVA > 0.01€
- Codes fournisseurs génériques
- Factures impayées > 90j
- Doubles-factures
- Factures sans correspondance Cegid

**Production-ready** : Code robuste, pas de TODOs, gestion d'erreurs complète.

---

**PLANB SARL** • Freddy & Bonbao • 2026
