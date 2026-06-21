# 📊 Guide : Convertir Excel en CSV pour l'import

## 🎯 Pourquoi CSV et pas Excel natif ?

L'app utilise actuellement un import CSV/TSV simple pour le MVP. Le support Excel natif (.xlsx) sera ajouté en Phase 2.

---

## 📝 Comment convertir ton fichier Excel en CSV

### Méthode 1 : Texte séparé par tabulations (Recommandé ✅)

1. **Ouvre ton fichier Excel** (balance Cegid, bilan, etc.)

2. **Fichier → Enregistrer sous...**

3. **Choisis le format** :
   - Sur Mac : `Text (Tab delimited) (.txt)`
   - Sur Windows : `Texte (séparé par des tabulations) (*.txt)`

4. **Enregistre** avec un nom descriptif
   - Exemple : `balance_juin_2026.txt`

5. **Importe le fichier .txt** dans l'app

✅ **Avantage** : Les tabulations conservent bien les colonnes

---

### Méthode 2 : CSV UTF-8

1. **Ouvre ton fichier Excel**

2. **Fichier → Enregistrer sous...**

3. **Choisis le format** :
   - Sur Mac : `CSV UTF-8 (Comma delimited) (.csv)`
   - Sur Windows : `CSV UTF-8 (délimité par des virgules) (*.csv)`

4. **Enregistre**

5. **IMPORTANT** : Ouvre le fichier CSV dans TextEdit/Notepad
   - Remplace toutes les virgules `,` par des tabulations
   - Ou vérifie que les colonnes sont bien séparées

6. **Importe le fichier** dans l'app

⚠️ **Attention** : Si tes montants contiennent des virgules (ex: `1,234.56`), cette méthode peut poser problème.

---

## 🔧 Format attendu par l'app

### Structure des colonnes (séparées par tabulations)

```
Date	N° Facture	Fournisseur	Code	HT	TVA	TTC
01/06/2026	FAC001	Sysco France	SYS001	1000.00	0.20	1200.00
```

### Détails des colonnes

1. **Date** : Format `dd/MM/yyyy` (ex: `19/06/2026`)
2. **N° Facture** : Numéro unique (ex: `FAC001`)
3. **Fournisseur** : Nom complet (ex: `Sysco France`)
4. **Code** : Code fournisseur Cegid (ex: `SYS001`)
5. **HT** : Montant hors taxes avec point (ex: `1000.00`)
6. **TVA** : Taux en décimal (ex: `0.20` pour 20%)
7. **TTC** : Montant TTC avec point (ex: `1200.00`)

### ⚠️ Points importants

- **Séparateur** : Tabulation (`\t`), PAS virgule ou point-virgule
- **Décimales** : Point `.` (pas virgule `,`)
- **Date** : Format français `dd/MM/yyyy`
- **Header** : Première ligne avec noms de colonnes
- **Encodage** : UTF-8

---

## 📋 Checklist avant import

- [ ] Fichier sauvegardé en `.txt` ou `.csv`
- [ ] Colonnes séparées par tabulations
- [ ] Dates au format `dd/MM/yyyy`
- [ ] Montants avec point décimal (ex: `1000.00`)
- [ ] Taux TVA en décimal (ex: `0.20` pas `20%`)
- [ ] Première ligne = header avec noms de colonnes
- [ ] Pas de lignes vides à la fin

---

## 🎯 Exemple complet

### Ton export Excel Cegid

Colonnes dans Excel :
```
Date | N° | Fournisseur | Code | Net | TVA | Gross
```

### Transformation nécessaire

1. Garde les colonnes dans cet ordre
2. Renomme le header si besoin :
   ```
   Date → Date
   N° → N° Facture
   Net → HT
   Gross → TTC
   ```

3. Vérifie les formats :
   - Dates : `01/06/2026` ✅
   - Montants : `1000.00` ✅
   - TVA : `0.20` ✅

4. Enregistre en `.txt` avec tabulations

5. Importe dans l'app !

---

## 🚀 Phase 2 : Excel natif

En Phase 2, l'app supportera directement :
- ✅ Fichiers `.xlsx` et `.xls`
- ✅ Lecture directe sans conversion
- ✅ Détection automatique des colonnes
- ✅ Multi-feuilles (onglets)

Pour le MVP actuel, la conversion CSV est nécessaire.

---

## 💡 Astuce : Automatisation

Si tu fais souvent cette conversion :

### Script Excel VBA (Windows/Mac)

```vba
Sub ExportToTSV()
    Dim filePath As String
    filePath = Application.GetSaveAsFilename( _
        FileFilter:="Text Files (*.txt), *.txt")
    
    If filePath <> "False" Then
        ActiveWorkbook.SaveAs _
            Filename:=filePath, _
            FileFormat:=xlTextWindows, _
            CreateBackup:=False
    End If
End Sub
```

### Script Shell (Mac)

Crée un fichier `convert_to_tsv.sh` :
```bash
#!/bin/bash
# Convertit Excel en TSV
# Usage: ./convert_to_tsv.sh mon_fichier.xlsx

filename=$(basename "$1" .xlsx)
libreoffice --headless --convert-to csv:"Text - txt - csv (StarCalc)":9,34,76 "$1"
mv "${filename}.csv" "${filename}.txt"
echo "✅ Converti en ${filename}.txt"
```

---

## ❓ FAQ

### Mon fichier Excel a plusieurs onglets
**Solution** : Exporte chaque onglet séparément en TXT

### J'ai des erreurs d'import
**Solution** :
1. Vérifie le format des dates (`dd/MM/yyyy`)
2. Vérifie que les montants ont un point (pas virgule)
3. Vérifie que les colonnes sont séparées par tabulations
4. Regarde les logs d'import dans l'app

### Mes montants ont des virgules
**Solution** : Remplace `,` par `.` dans Excel avant d'exporter
- Excel : Rechercher/Remplacer dans la colonne montants

### Les accents ne s'affichent pas
**Solution** : Utilise l'encodage UTF-8 lors de l'export

---

## 📞 Besoin d'aide ?

Si tu as des problèmes :
1. Vérifie le fichier exemple : `sample_data_balance.csv`
2. Compare ton format avec l'exemple
3. Consulte les logs d'import dans l'app

---

**Prochaine étape** : Lance l'import et vérifie le Dashboard ! 🚀
