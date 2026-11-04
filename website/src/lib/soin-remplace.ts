// Soin déjà renouvelé : une ligne plus récente existe pour le même produit
// (vaccin : même type, catégorie ou nom si elle est vide / « Autre »). Son
// bouton « + Rappel » n'a plus lieu d'être : on renouvelle depuis la dernière
// ligne. Même règle que trg_sante_rappel_a_jour et functions/sante.js.
// Miroir appli : lib/utils/soin_remplace.dart.

type Ligne = Record<string, unknown>;

const norm = (v: unknown) => String(v ?? '').trim().toLowerCase();

function typeVaccin(l: Ligne) {
  const c = norm(l.categorie);
  return c && c !== 'autre' ? c : norm(l.vaccin);
}

const memeSoin = (table: string, a: Ligne, b: Ligne) => table === 'vaccinations'
  ? typeVaccin(a) === typeVaccin(b) || (!!norm(a.vaccin) && norm(a.vaccin) === norm(b.vaccin))
  : !!norm(a.produit) && norm(a.produit) === norm(b.produit);

// Date du soin, puis date de rappel, puis identifiant (deux lignes identiques : une seule reste active).
const cle = (l: Ligne) => `${String(l.date ?? '').slice(0, 10)}|${String(l.date_rappel ?? '').slice(0, 10)}|${String(l.id ?? '')}`;

export function soinRemplace(table: string, ligne: Ligne, lignes: readonly Ligne[]): boolean {
  return lignes.some(x => String(x.id) !== String(ligne.id) && memeSoin(table, ligne, x) && cle(x) > cle(ligne));
}
