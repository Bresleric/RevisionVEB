# 🚀 Quick Start Guide - PLANB Audit

## Démarrage en 5 minutes

### 1️⃣ Lancer l'application
1. Ouvre le projet dans Xcode
2. Appuie sur `Cmd+R` pour compiler et lancer
3. L'app s'ouvre sur le Dashboard (vide pour le moment)

### 2️⃣ Générer des données de test
1. Va dans **Réglages** (sidebar en bas)
2. Clique sur **"Générer données de démo"**
3. Confirme l'action
4. ✅ 20+ factures de test sont créées automatiquement

### 3️⃣ Explorer le Dashboard
1. Retourne au **Dashboard**
2. Tu verras :
   - Nombre de factures
   - Historique des imports
   - Statistiques globales

### 4️⃣ Lancer ton premier audit
1. Va dans **Cycle E - Fournisseurs**
2. Clique sur **"Lancer l'audit"**
3. Attends quelques secondes
4. Explore les 3 onglets :
   - **Résultats audit** : tous les contrôles
   - **Factures** : liste complète
   - **Statistiques** : graphiques et résumés

### 5️⃣ Exporter les résultats
1. Reste sur **Cycle E - Fournisseurs**
2. Clique sur **Export** (bouton en haut à droite)
3. Choisis un type d'export :
   - Résultats audit
   - Maîtresse factures
   - Synthèse
4. Le fichier CSV s'ouvre automatiquement dans Excel/Numbers

---

## 📊 Que contiennent les données de démo ?

### Factures (22 au total)
- 10 factures Freddy + 10 factures Bonbao
- Fournisseurs variés : Sysco, Metro, Transgourmet, etc.
- Montants réalistes : 100€ à 5000€
- Dates sur 6 mois
- Différents statuts : payé, en attente, en retard

### Anomalies incluses (pour tester les règles)
- ✅ **1 facture avec TVA incorrecte** (E.2)
  - FAC_BAD_VAT : 1000€ HT + 20% devrait = 1200€ TTC, mais affiche 1205€
  
- ✅ **1 code fournisseur générique** (E.3)
  - Deliveroo : code "00FOUR001" (à éviter)
  
- ✅ **Plusieurs factures en retard** (E.4)
  - Factures > 90j sans paiement
  
- ✅ **1 doublon** (E.5)
  - FAC001 et FAC001_DUP (même fournisseur, même montant, 5 jours d'écart)

---

## 🎯 Scénarios de test

### Scénario 1 : Import manuel
1. Va dans **Import**
2. Prépare un fichier CSV avec ce format :
```
Date	N° Facture	Fournisseur	Code	HT	TVA	TTC
19/06/2026	TEST001	Fournisseur Test	TST001	100.00	0.20	120.00
```
3. Glisse-dépose le fichier
4. Vérifie dans le Dashboard que l'import est réussi

### Scénario 2 : Détecter une anomalie TVA
1. Dans **Cycle E - Fournisseurs**, lance l'audit
2. Va dans **Résultats audit**
3. Filtre par "❌ Anomalie"
4. Cherche la règle **E.2 - Validation TVA**
5. Tu devrais voir : FAC_BAD_VAT avec écart de 5.00€

### Scénario 3 : Trouver les doublons
1. Dans **Résultats audit**
2. Cherche la règle **E.5 - Doubles factures**
3. Tu verras : FAC001 et FAC001_DUP signalés

### Scénario 4 : Analyser les retards de paiement
1. Va dans **Factures**
2. Trie par statut
3. Repère les factures "En retard"
4. Dans **Résultats audit**, règle **E.4** montre le détail

---

## 🛠️ Personnaliser les réglages

### Modifier les tolérances
1. Va dans **Réglages**
2. Ajuste :
   - **Tolérance montants** : 0.01€ à 1.00€
   - **Délai maximal paiement** : 30j à 180j
3. Relance l'audit pour voir les changements

### Changer le restaurant par défaut
1. Dans **Réglages** > "Restaurant par défaut"
2. Choisis Freddy ou Bonbao
3. Tes prochains imports utiliseront ce restaurant

---

## 📁 Format d'import attendu

### CSV/TSV Balance Cegid
**Séparateur** : Tabulation (`\t`)

**Colonnes** :
1. Date (format: `dd/MM/yyyy`)
2. N° Facture
3. Fournisseur
4. Code fournisseur
5. Montant HT (avec point décimal)
6. Taux TVA (0.055, 0.10, 0.20)
7. Montant TTC

**Exemple** :
```
Date	N° Facture	Fournisseur	Code	HT	TVA	TTC
01/06/2026	FAC001	Sysco France	SYS001	1000.00	0.20	1200.00
05/06/2026	FAC002	Metro	MET001	500.00	0.10	550.00
```

### PDF Factures
L'app extrait automatiquement :
- Numéro (recherche "Facture" ou "N°")
- Date (format dd/MM/yyyy)
- Montants (HT, TTC avec symbole €)

**Note** : Le parsing PDF est basique dans cette version MVP. Pour de meilleurs résultats, utilise des factures structurées.

---

## 🐛 Problèmes courants

### "Aucune donnée dans le Dashboard"
→ Va dans **Réglages** et clique **"Générer données de démo"**

### "L'audit ne retourne aucun résultat"
→ Assure-toi d'avoir importé des factures d'abord

### "L'import PDF échoue"
→ Le parsing PDF est basique. Utilise l'import CSV pour des tests fiables

### "Le fichier CSV n'est pas reconnu"
→ Vérifie que tu utilises bien des tabulations (`\t`) comme séparateur

---

## 🎓 Comprendre les règles d'audit

### E.1 - Matching facture
- **Objectif** : Vérifier que chaque facture PDF a une correspondance dans Cegid
- **Critères** : Même N° + même montant
- **Tolérance** : 0€
- **Résultat** : Anomalie si pas de correspondance

### E.2 - Validation TVA
- **Objectif** : Calculer automatiquement la TVA
- **Formule** : `HT × (1 + taux) = TTC`
- **Tolérance** : 0.01€
- **Résultat** : Anomalie si écart > tolérance

### E.3 - Code fournisseur
- **Objectif** : Éviter les codes génériques
- **Critères** : Code ne doit PAS commencer par "00FOUR"
- **Résultat** : Alerte si code générique, Anomalie si vide

### E.4 - Délai paiement
- **Objectif** : Contrôler les délais fournisseurs
- **Critères** : 
  - < 90j = Conforme
  - 90-120j = Alerte
  - > 120j = Anomalie
- **Résultat** : Basé sur date facture → date paiement

### E.5 - Doubles factures
- **Objectif** : Détecter les doublons
- **Critères** : Même fournisseur + même montant dans une fenêtre de 30j
- **Résultat** : Anomalie critique

---

## ✅ Checklist avant utilisation production

- [ ] Tester avec vos vrais formats CSV Cegid
- [ ] Adapter le parsing PDF à vos fournisseurs
- [ ] Valider les tolérances (0.01€ par défaut)
- [ ] Définir les codes fournisseurs acceptables
- [ ] Former l'équipe sur les 5 règles du Cycle E
- [ ] Préparer un process d'export mensuel

---

**Besoin d'aide ?** Consulte le [README.md](README.md) pour la doc complète.
