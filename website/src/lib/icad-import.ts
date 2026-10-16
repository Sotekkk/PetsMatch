// Import I-CAD (exports « actuellement détenus » / « anciennement détenus »,
// CSV séparé par « ; ») → fiches animaux du profil actif.
// Rapprochement : numéro de puce, sinon prénom identique + même date de
// naissance. Rien n'est écrit sans validation : nouvelles fiches et mises à
// jour sont proposées, l'utilisateur coche ce qu'il applique.
// Le registre d'entrées / sorties suit (statut, date_entree, date_sortie,
// destinataire) ; l'historique de propriété aussi (animaux_proprietes).
// Miroir appli : lib/utils/icad_import.dart.

export interface IcadAnimal {
  puce: string; tatouage: string; nom: string; espece: string; sexe: 'male' | 'femelle' | '';
  race: string; couleur: string; dateNaissance: string; dateEntree: string; dateCession: string;
  /** Détenteur actuel (export « anciennement détenus » : l'acquéreur). */
  acquereur: { nom: string; prenom: string; adresse: string; email: string; tel: string } | null;
}

export interface FicheExistante {
  id: string; nom: string | null; identification: string | null; espece: string | null; sexe: string | null;
  race: string | null; couleur: string | null; date_naissance: string | null; statut: string | null;
  date_entree: string | null; date_sortie: string | null; destinataire_nom: string | null; destinataire_adresse: string | null;
}

export interface Changement { champ: string; libelle: string; actuel: string; icad: string; valeur: unknown }
export interface MiseAJour { fiche: FicheExistante; icad: IcadAnimal; par: 'puce' | 'nom_naissance'; changements: Changement[] }
export interface Analyse {
  nouvelles: IcadAnimal[];
  majs: MiseAJour[];
  aJour: { fiche: FicheExistante; icad: IcadAnimal }[];
  alertes: string[];
}

const casse = (s: string) => s.toLowerCase().replace(/(^|[\s\-'])(\p{L})/gu, (_, a: string, b: string) => a + b.toUpperCase());
const casseLibelle = (s: string) => (s ? s.charAt(0).toUpperCase() + s.slice(1).toLowerCase() : '');
const chiffres = (s: string | null | undefined) => (s ?? '').replace(/\D/g, '');
const jour = (s: string | null | undefined) => (s ?? '').slice(0, 10);
const norm = (s: string | null | undefined) => (s ?? '').trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const fr = (iso: string) => (iso ? new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString('fr-FR') : '—');

/** Découpe une ligne CSV « ; » avec guillemets doublés. */
function cellules(ligne: string): string[] {
  const out: string[] = [];
  let cur = '', q = false;
  for (let i = 0; i < ligne.length; i++) {
    const c = ligne[i];
    if (q) {
      if (c === '"' && ligne[i + 1] === '"') { cur += '"'; i++; }
      else if (c === '"') q = false;
      else cur += c;
    } else if (c === '"') q = true;
    else if (c === ';') { out.push(cur); cur = ''; }
    else cur += c;
  }
  out.push(cur);
  return out.map(x => x.trim());
}

const ESPECES: Record<string, string> = { chien: 'chien', chat: 'chat', furet: 'furet' };

export function lireCsvIcad(texte: string): IcadAnimal[] {
  const lignes = texte.replace(/^﻿/, '').split(/\r?\n/).filter(l => l.trim());
  if (lignes.length < 2) return [];
  const entetes = cellules(lignes[0]).map(norm);
  const col = (...noms: string[]) => entetes.findIndex(e => noms.some(n => e === norm(n)));
  const i = {
    puce: col('Insert', 'Transpondeur', 'Puce'), tatouage: col('Tatouage'), nom: col('Nom'), espece: col('Espèce'),
    sexe: col('Sexe'), race: col('Race'), robe: col('Robe'), naissance: col('Date de naissance'),
    entree: col('Date entrée'), cession: col('Date cession'), detenteur: col('Nom et prénom'),
    adresse: col('Adresse du détenteur'), email: col('Email du détenteur'), tel: col('Téléphone du détenteur'),
  };
  if (i.puce < 0 || i.nom < 0) throw new Error("Fichier non reconnu : ce n'est pas un export I-CAD (colonnes « Insert » et « Nom » absentes).");
  return lignes.slice(1).map(l => {
    const c = cellules(l);
    const v = (k: number) => (k >= 0 ? c[k] ?? '' : '');
    const sexe = norm(v(i.sexe));
    const cession = jour(v(i.cession));
    const det = v(i.detenteur).trim();
    const mots = det.split(/\s+/).filter(Boolean);
    return {
      puce: chiffres(v(i.puce)), tatouage: v(i.tatouage), nom: casse(v(i.nom)),
      espece: ESPECES[norm(v(i.espece))] ?? (norm(v(i.espece)) || 'chien'),
      sexe: sexe.startsWith('m') ? 'male' : sexe.startsWith('f') ? 'femelle' : '',
      race: casse(v(i.race)), couleur: casseLibelle(v(i.robe)),
      dateNaissance: jour(v(i.naissance)), dateEntree: jour(v(i.entree)), dateCession: cession,
      // I-CAD : « NOM PRÉNOM » — le prénom est le dernier mot.
      acquereur: cession && det ? {
        prenom: casse(mots.length > 1 ? mots[mots.length - 1] : ''), nom: casse(mots.length > 1 ? mots.slice(0, -1).join(' ') : det),
        adresse: v(i.adresse).trim(), email: v(i.email).trim(), tel: v(i.tel).trim(),
      } : null,
    } as IcadAnimal;
  }).filter(a => a.puce || a.nom);
}

/** Compare l'export aux fiches du profil. `pucesAutres` : puces déjà
 *  enregistrées sur d'autres comptes (jamais modifiées). */
export function analyser(icad: IcadAnimal[], fiches: FicheExistante[], pucesAutres: Set<string>): Analyse {
  const res: Analyse = { nouvelles: [], majs: [], aJour: [], alertes: [] };
  const vus = new Set<string>();
  for (const a of icad) {
    if (a.puce && vus.has(a.puce)) continue;
    if (a.puce) vus.add(a.puce);
    let fiche = a.puce ? fiches.find(f => chiffres(f.identification) === a.puce) : undefined;
    let par: MiseAJour['par'] = 'puce';
    if (!fiche) {
      fiche = fiches.find(f => norm(f.nom) === norm(a.nom) && jour(f.date_naissance) === a.dateNaissance && a.dateNaissance);
      par = 'nom_naissance';
      if (fiche && chiffres(fiche.identification) && chiffres(fiche.identification) !== a.puce) {
        res.alertes.push(`${a.nom} (né le ${fr(a.dateNaissance)}) : une fiche porte ce prénom et cette date mais une autre puce (${fiche.identification}). Rien n'est modifié : vérifiez la puce.`);
        continue;
      }
    }
    if (!fiche) {
      if (a.puce && pucesAutres.has(a.puce)) {
        res.alertes.push(`${a.nom} (puce ${a.puce}) est déjà enregistré sur un autre compte PetsMatch : fiche non créée.`);
        continue;
      }
      res.nouvelles.push(a);
      continue;
    }
    const ch: Changement[] = [];
    const ajoute = (champ: string, libelle: string, actuel: string | null, icadV: string, valeur: unknown = icadV) => {
      if (!icadV) return;
      if (norm(actuel) === norm(icadV)) return;
      ch.push({ champ, libelle, actuel: actuel || '—', icad: icadV, valeur });
    };
    if (!chiffres(fiche.identification)) ajoute('identification', 'Puce', fiche.identification, a.puce);
    ajoute('nom', 'Nom', fiche.nom, a.nom);
    ajoute('sexe', 'Sexe', fiche.sexe === 'male' ? 'Mâle' : fiche.sexe === 'femelle' ? 'Femelle' : fiche.sexe,
      a.sexe === 'male' ? 'Mâle' : a.sexe === 'femelle' ? 'Femelle' : '', a.sexe);
    ajoute('race', 'Race', fiche.race, a.race);
    ajoute('couleur', 'Robe', fiche.couleur, a.couleur);
    if (a.dateNaissance && jour(fiche.date_naissance) !== a.dateNaissance)
      ch.push({ champ: 'date_naissance', libelle: 'Naissance', actuel: fr(jour(fiche.date_naissance)), icad: fr(a.dateNaissance), valeur: a.dateNaissance });
    if (a.dateEntree && jour(fiche.date_entree) !== a.dateEntree)
      ch.push({ champ: 'date_entree', libelle: 'Entrée (registre)', actuel: fr(jour(fiche.date_entree)), icad: fr(a.dateEntree), valeur: a.dateEntree });
    if (a.dateCession) {
      const dejaSorti = fiche.statut === 'sorti' && jour(fiche.date_sortie) === a.dateCession;
      if (!dejaSorti) {
        ch.push({ champ: 'sortie', libelle: 'Sortie (registre)',
          actuel: fiche.statut === 'sorti' ? `Sorti le ${fr(jour(fiche.date_sortie))}` : 'Présent',
          icad: `Sorti le ${fr(a.dateCession)}${a.acquereur ? ` — ${a.acquereur.prenom} ${a.acquereur.nom}` : ''}`, valeur: a.dateCession });
      }
    } else if (fiche.statut === 'sorti') {
      res.alertes.push(`${a.nom} : I-CAD vous indique encore détenteur, mais la fiche est « sortie ». Vérifiez sur I-CAD (déclaration de cession non faite ?). Rien n'est modifié.`);
    }
    if (ch.length) res.majs.push({ fiche, icad: a, par, changements: ch });
    else res.aJour.push({ fiche, icad: a });
  }
  return res;
}

/** Colonnes animaux d'une nouvelle fiche issue d'I-CAD. */
export function ligneNouvelle(a: IcadAnimal) {
  return {
    nom: a.nom, identification: a.puce, espece: a.espece, sexe: a.sexe || null, race: a.race, couleur: a.couleur,
    date_naissance: a.dateNaissance || null, date_entree: a.dateEntree || null,
    statut: a.dateCession ? 'sorti' : 'present',
    ...(a.dateCession ? champsSortie(a) : {}),
  };
}

export function champsSortie(a: IcadAnimal) {
  return {
    statut: 'sorti', date_sortie: a.dateCession,
    ...(a.acquereur ? {
      destinataire_nom: `${a.acquereur.prenom} ${a.acquereur.nom}`.trim(), destinataire_qualite: 'particulier',
      destinataire_adresse: a.acquereur.adresse,
      acquereur_contact_manuel: { prenom: a.acquereur.prenom, nom: a.acquereur.nom, tel: a.acquereur.tel, email: a.acquereur.email, adresse: a.acquereur.adresse },
    } : {}),
  };
}

/** Champs animaux à écrire pour une mise à jour validée. */
export function champsMiseAJour(m: MiseAJour): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const c of m.changements) {
    if (c.champ === 'sortie') Object.assign(out, champsSortie(m.icad));
    else out[c.champ] = c.valeur;
  }
  return out;
}

export const libelleDate = fr;
