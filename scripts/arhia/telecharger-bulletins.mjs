#!/usr/bin/env node
// Téléchargement des bulletins et états de paie depuis l'Espace Employeur
// Combo Pay (Arhia) : https://combohr.arhia.fr
//
// Principe : une fenêtre de navigateur s'ouvre, VOUS vous connectez (le script
// ne connaît jamais le mot de passe), puis le script récupère le jeton de
// session de l'application et appelle son API pour enregistrer tous les
// documents de paie, mois par mois, dans un dossier local.
//
// Usage : voir --help

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";

const BASE = "https://combohr.arhia.fr";
const GRAPHQL = `${BASE}/graphql`;
const DOWNLOAD_LIVRABLE = `${BASE}/reports/downloadLivrable`;

// Catégories de livrables : reprises des onglets de la page « États de paie »
// de l'application Arhia (filtres par liv_type lus dans son code). Un type
// absent d'ici est rangé dans un dossier "type-N" ; on affinera.
const CATEGORIES = [
  ["Bulletins", [1, 41]], // 41 = bulletin de versement d'épargne salariale
  ["Syntheses", [2, 3, 4, 5]],
  ["Comptabilite", [28, 29, 30, 31, 32, 33, 34]],
  ["Paiements", [7, 8]],
  ["Cotisations", [6, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 35, 36]],
  ["Departs", [9, 10, 37]], // documents pour soldes de tout compte
  ["Attestations fiscales", [40]],
  ["Autres documents", [38, 39]],
];
const TYPE_LABELS = Object.fromEntries(CATEGORIES.flatMap(([lib, types]) => types.map((t) => [t, lib])));
const ORIGINE_VIDE = 3; // liv_origin = VIDE : livrable sans fichier

// ---------------------------------------------------------------- arguments
function aide() {
  console.log(`Téléchargement des bulletins et états de paie Combo Pay (Arhia)

Usage : ./telecharger-bulletins.sh [options]

  --depuis AAAAMM     Premier mois (défaut : 202501)
  --jusqua AAAAMM     Dernier mois (défaut : mois courant)
  --dossier CHEMIN    Dossier de destination
                      (défaut : ~/Documents/Paie Arhia)
  --dossier-paie ID   Ne traiter que ce dossier de paie (pad_id)
  --provisoires       Inclure les versions provisoires (défaut : définitives)
  --liste             Lister les documents sans les télécharger
  --forcer            Retélécharger les fichiers déjà présents
  --diagnostic        Enregistrer les réponses brutes de l'API dans un fichier
                      temporaire (hors du dépôt) pour analyse en cas de problème
  --help              Cette aide

Le script ne stocke aucun identifiant. La session du navigateur est conservée
dans un profil local pour éviter de se reconnecter à chaque fois.
`);
}

const args = process.argv.slice(2);
const opt = {
  depuis: 202501,
  jusqua: Number(new Date().toISOString().slice(0, 7).replace("-", "")),
  dossier: path.join(os.homedir(), "Documents", "Paie Arhia"),
  padId: null,
  provisoires: false,
  liste: false,
  forcer: false,
  diagnostic: false,
};
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  const v = () => args[++i];
  if (a === "--help" || a === "-h") { aide(); process.exit(0); }
  else if (a === "--depuis") opt.depuis = Number(v());
  else if (a === "--jusqua") opt.jusqua = Number(v());
  else if (a === "--dossier") opt.dossier = v();
  else if (a === "--dossier-paie") opt.padId = Number(v());
  else if (a === "--provisoires") opt.provisoires = true;
  else if (a === "--liste") opt.liste = true;
  else if (a === "--forcer") opt.forcer = true;
  else if (a === "--diagnostic") opt.diagnostic = true;
  else { console.error(`Option inconnue : ${a}`); aide(); process.exit(2); }
}
if (!/^\d{6}$/.test(String(opt.depuis)) || !/^\d{6}$/.test(String(opt.jusqua))) {
  console.error("--depuis et --jusqua attendent un mois au format AAAAMM (ex. 202501).");
  process.exit(2);
}

// ---------------------------------------------------------------- navigateur
const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require("playwright"));
} catch {
  console.error("Playwright est absent : lancez ./telecharger-bulletins.sh qui l'installe.");
  process.exit(1);
}

const profilDir =
  process.platform === "darwin"
    ? path.join(os.homedir(), "Library", "Application Support", "RevisionVEB", "arhia-profile")
    : path.join(os.homedir(), ".revisionveb-arhia");
fs.mkdirSync(profilDir, { recursive: true });

async function ouvrirNavigateur() {
  const commun = { headless: false, viewport: { width: 1200, height: 850 } };
  if (process.env.ARHIA_NAVIGATEUR) commun.executablePath = process.env.ARHIA_NAVIGATEUR;
  try {
    return await chromium.launchPersistentContext(profilDir, { ...commun, channel: "chrome" });
  } catch {
    try {
      return await chromium.launchPersistentContext(profilDir, commun);
    } catch (e) {
      console.error(
        "Impossible d'ouvrir un navigateur. Installez Google Chrome, ou lancez :\n" +
          "  npx playwright install chromium\n" + e.message
      );
      process.exit(1);
    }
  }
}

// ---------------------------------------------------------------- API
let token = null;

// Journal de diagnostic (--diagnostic) : réponses brutes, sans le jeton.
let fichierDiagnostic = null;
function diagnostic(etape, contenu) {
  if (!opt.diagnostic) return;
  if (!fichierDiagnostic) {
    fichierDiagnostic = path.join(os.tmpdir(), `arhia-diagnostic-${Date.now()}.jsonl`);
    console.log(`Diagnostic : ${fichierDiagnostic}`);
  }
  const texte = typeof contenu === "string" ? contenu.slice(0, 20000) : contenu;
  fs.appendFileSync(fichierDiagnostic, JSON.stringify({ quand: new Date().toISOString(), etape, contenu: texte }) + "\n");
}

async function gql(query, variables = {}) {
  const r = await fetch(GRAPHQL, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ query, variables }),
  });
  const brut = await r.text();
  diagnostic("graphql", { statut: r.status, variables, reponse: brut });
  let j = {};
  try { j = JSON.parse(brut); } catch { /* réponse non JSON */ }
  if (!r.ok || j.errors) {
    const msg = j.errors ? j.errors.map((e) => e.message).join(" ; ") : `HTTP ${r.status}`;
    throw new Error(`GraphQL : ${msg}`);
  }
  return j.data;
}

async function telechargerLivrable(livId) {
  const r = await fetch(`${DOWNLOAD_LIVRABLE}?liv_id=${livId}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const ct = r.headers.get("content-type") || "";
  diagnostic("downloadLivrable", { livId, statut: r.status, contentType: ct });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  if (ct.includes("application/json")) {
    // Forme observée dans l'application : { data: { file: { data: [octets] },
    // filename, fileNameForSave, mimetype } }
    const j = await r.json();
    if (j.errors) throw new Error(j.errors.map((e) => e.message).join(" ; "));
    const d = j.data ?? j;
    const octets = d.file?.data ?? d.file;
    if (!Array.isArray(octets)) throw new Error("réponse JSON sans contenu de fichier");
    return { octets: Buffer.from(octets), nom: d.fileNameForSave ?? d.filename ?? null, mime: d.mimetype ?? null };
  }
  return { octets: Buffer.from(await r.arrayBuffer()), nom: null, mime: ct };
}

// ---------------------------------------------------------------- utilitaires
const propre = (s) =>
  String(s ?? "")
    .normalize("NFKD").replace(/[̀-ͯ]/g, "")
    .replace(/[\/\\:*?"<>|]/g, "-").replace(/\s+/g, " ").trim() || "sans-nom";

const periodeDe = (liv) => {
  const p = liv.loli?.loli_peri_anneemois ?? liv.liv_periode_debut ?? liv.liv_periode_fin;
  const s = String(p ?? "").replace(/\D/g, "").slice(0, 6);
  return /^\d{6}$/.test(s) ? `${s.slice(0, 4)}-${s.slice(4, 6)}` : "periode-inconnue";
};

const extensionDe = (liv, mime) => {
  const ext = { 1: ".pdf", 2: ".xlsx", 3: ".xml", 4: ".csv", 6: ".docx", 7: ".odt" }[liv.liv_output_type];
  if (ext) return ext;
  if (mime?.includes("pdf")) return ".pdf";
  if (mime?.includes("spreadsheet")) return ".xlsx";
  return ".pdf";
};

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- déroulé
async function main() {
  const contexte = await ouvrirNavigateur();
  const page = contexte.pages()[0] ?? (await contexte.newPage());

  page.on("request", (req) => {
    if (!req.url().startsWith(BASE)) return;
    const auth = req.headers()["authorization"];
    if (auth && /^Bearer .+/.test(auth) && auth.length > 20) token = auth.slice(7);
  });

  await page.goto(`${BASE}/`, { waitUntil: "domcontentloaded" });

  console.log("\nConnectez-vous dans la fenêtre du navigateur, puis choisissez votre dossier.");
  console.log("Le script continue tout seul dès que l'espace employeur est ouvert.\n");

  const debut = Date.now();
  const routesAttente = /#\/(login|selectFolder|selectRole)?\/?$/;
  while (Date.now() - debut < 15 * 60 * 1000) {
    const url = page.url();
    const hash = url.includes("#") ? url.slice(url.indexOf("#")) : "";
    if (token && hash && !routesAttente.test(hash)) break;
    await dormir(1000);
  }
  if (!token) {
    console.error("Pas de connexion détectée après 15 minutes, abandon.");
    await contexte.close();
    process.exit(1);
  }
  await dormir(1500);

  // Qui est connecté, à quels dossiers ?
  const { viewer } = await gql(`{ viewer { uti_prenom uti_nom grantedFolders { pad_id pad_libelle dos_libelle } } }`);
  console.log(`Connecté : ${viewer.uti_prenom} ${viewer.uti_nom}`);
  let dossiers = viewer.grantedFolders ?? [];
  if (opt.padId) dossiers = dossiers.filter((d) => d.pad_id === opt.padId);
  if (dossiers.length === 0) {
    console.error("Aucun dossier de paie accessible.");
    await contexte.close();
    process.exit(1);
  }

  fs.mkdirSync(opt.dossier, { recursive: true });
  const manifeste = [];
  let nbTelecharges = 0, nbIgnores = 0, nbErreurs = 0;

  for (const dossier of dossiers) {
    console.log(`\n=== Dossier ${dossier.pad_libelle} (${dossier.pad_id})`);
    let lots = [];
    try {
      const r = await gql(
        `mutation ($padId: Int!) { selectFolder(padId: $padId) { pad { pad_id pad_libelle lots { lot_id lot_code lot_libelle } } } }`,
        { padId: dossier.pad_id }
      );
      lots = r.selectFolder?.pad?.lots ?? [];
    } catch (e) {
      console.error(`  Sélection du dossier impossible : ${e.message}`);
      continue;
    }
    if (lots.length) console.log(`  Lots : ${lots.map((l) => `${l.lot_code} ${l.lot_libelle ?? ""}`.trim()).join(", ")}`);

    // Interrogation année par année pour rester léger.
    const livrables = [];
    for (let annee = Math.floor(opt.depuis / 100); annee <= Math.floor(opt.jusqua / 100); annee++) {
      const startPeri = Math.max(opt.depuis, annee * 100 + 1);
      const endPeri = Math.min(opt.jusqua, annee * 100 + 12);
      // Même forme que la page « États de paie » de l'application : plage de
      // périodes et version définitive, sans filtre de lot (le dossier a été
      // sélectionné côté serveur par selectFolder).
      const variables = { startPeri, endPeri };
      if (!opt.provisoires) variables.isVersionDef = true;
      try {
        const r = await gql(
          `query ($startPeri: Int, $endPeri: Int, $isVersionDef: Boolean) {
             getLivrables(startPeri: $startPeri, endPeri: $endPeri, isVersionDef: $isVersionDef) {
               liv_id liv_type liv_filename liv_lib_perso liv_periode_debut liv_periode_fin
               liv_origin liv_output_type liv_datetime_creation lot_id cnt_id aeta_type lot_code eta_code
               loli { loli_peri_anneemois loli_est_version_def loli_version }
               sal { sal_id sal_matricule sal_nom_usage sal_prenom }
             } }`,
          variables
        );
        livrables.push(...(r.getLivrables ?? []));
      } catch (e) {
        console.error(`  ${startPeri}-${endPeri} : ${e.message}`);
        nbErreurs++;
      }
    }

    const utiles = livrables.filter((l) => l.liv_origin !== ORIGINE_VIDE);
    console.log(`  ${utiles.length} document(s) trouvé(s) entre ${opt.depuis} et ${opt.jusqua}`);

    for (const liv of utiles) {
      const periode = periodeDe(liv);
      const type = TYPE_LABELS[liv.liv_type] ?? `type-${liv.liv_type}`;
      const salarie = liv.sal ? `${liv.sal.sal_nom_usage ?? ""} ${liv.sal.sal_prenom ?? ""}`.trim() : "";
      const version = liv.loli?.loli_est_version_def ? "definitive" : "provisoire";
      const ligne = { pad: dossier.pad_libelle, periode, type, liv_type: liv.liv_type, liv_id: liv.liv_id, salarie, version, fichier: "" };
      manifeste.push(ligne);

      if (opt.liste) {
        console.log(`  ${periode}  ${type.padEnd(22)} ${liv.liv_id}  ${salarie || liv.liv_filename || liv.liv_lib_perso || ""}`);
        continue;
      }

      const repertoire = path.join(opt.dossier, propre(dossier.pad_libelle), periode, propre(type));
      fs.mkdirSync(repertoire, { recursive: true });
      let base = propre(liv.liv_filename || liv.liv_lib_perso || `${type} ${periode}`).replace(/\.[a-z0-9]{2,5}$/i, "");
      if (salarie && !base.toLowerCase().includes(propre(salarie).toLowerCase().split(" ")[0])) base = `${propre(salarie)} - ${base}`;
      if (version !== "definitive") base += " (provisoire)";
      base += ` [${liv.liv_id}]`;

      const existant = fs.readdirSync(repertoire).find((f) => f.startsWith(base));
      if (existant && !opt.forcer) {
        ligne.fichier = path.join(repertoire, existant);
        nbIgnores++;
        continue;
      }
      try {
        const { octets, nom, mime } = await telechargerLivrable(liv.liv_id);
        const ext = (nom && path.extname(nom)) || extensionDe(liv, mime);
        const cible = path.join(repertoire, base + ext);
        fs.writeFileSync(cible, octets);
        ligne.fichier = cible;
        nbTelecharges++;
        console.log(`  + ${path.relative(opt.dossier, cible)}`);
        await dormir(300);
      } catch (e) {
        nbErreurs++;
        console.error(`  ! ${periode} ${type} ${liv.liv_id} : ${e.message}`);
      }
    }
  }

  if (!opt.liste) {
    const csv = ["dossier;periode;type;liv_type;liv_id;salarie;version;fichier"]
      .concat(manifeste.map((m) => [m.pad, m.periode, m.type, m.liv_type, m.liv_id, m.salarie, m.version, m.fichier].map((v) => String(v ?? "").replace(/;/g, ",")).join(";")))
      .join("\n");
    fs.writeFileSync(path.join(opt.dossier, "index.csv"), csv + "\n");
  }

  // Récapitulatif : nombre de documents par mois et par catégorie.
  if (manifeste.length) {
    const types = [...new Set(manifeste.map((m) => m.type))].sort();
    const periodes = [...new Set(manifeste.map((m) => m.periode))].sort();
    const compte = {};
    for (const m of manifeste) compte[`${m.periode}|${m.type}`] = (compte[`${m.periode}|${m.type}`] ?? 0) + 1;
    const larg = Math.max(8, ...types.map((t) => t.length));
    console.log("\nRécapitulatif (documents par mois et par catégorie) :");
    console.log("  " + "Mois".padEnd(9) + types.map((t) => t.padStart(larg)).join(" "));
    for (const p of periodes) console.log("  " + p.padEnd(9) + types.map((t) => String(compte[`${p}|${t}`] ?? "").padStart(larg)).join(" "));
  }

  console.log(`\nTerminé : ${nbTelecharges} téléchargé(s), ${nbIgnores} déjà présent(s), ${nbErreurs} erreur(s).`);
  if (!opt.liste) console.log(`Dossier : ${opt.dossier}`);
  await contexte.close();
}

main().catch((e) => {
  console.error(`Erreur : ${e.message}`);
  process.exit(1);
});
