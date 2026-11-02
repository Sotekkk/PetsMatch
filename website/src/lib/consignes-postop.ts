// Consignes postopératoires pour le propriétaire (migration_consignes_postop.sql) :
// document distinct du compte rendu opératoire, en sections de texte simple
// (titres « ## », listes « - », gras « **…** »). Les modèles fournis ne
// contiennent QUE la structure et des indications de rédaction : aucune
// consigne médicale n'est écrite d'office ; la clinique rédige son texte et
// l'enregistre comme modèle (consignes_modeles). Le préremplissage ne reprend
// que des données déjà saisies (intervention, CR opératoire, coordonnées de
// la clinique). Miroir appli : lib/utils/consignes_postop.dart.

export interface SectionConsigne { titre: string; texte: string; aide?: string }

export interface ModeleConsignes { id?: string; nom: string; type_intervention?: string | null; sections: SectionConsigne[] }

/** Sections du document (structure du cahier des charges). */
export const SECTIONS_CONSIGNES: SectionConsigne[] = [
  { titre: 'Intervention réalisée', texte: '', aide: 'Bref résumé, en termes simples, de ce qui a été fait.' },
  { titre: 'Repos et activité', texte: '', aide: 'Durée du repos, sorties, escaliers, jeux, restrictions.' },
  { titre: 'Alimentation et hydratation', texte: '', aide: 'Quand et comment reprendre l’alimentation et la boisson.' },
  { titre: 'Surveillance', texte: '', aide: 'Ce que le propriétaire doit observer les premiers jours.' },
  { titre: 'Plaie et cicatrisation', texte: '', aide: 'Protection de la plaie, collerette, pansement, soins, bain.' },
  { titre: 'Traitements', texte: '', aide: 'Résumé des traitements ; le détail figure sur l’ordonnance.' },
  { titre: 'Signes nécessitant de contacter la clinique', texte: '', aide: 'Signes d’alerte définis par le vétérinaire.' },
  { titre: 'Prochains contrôles', texte: '', aide: 'Dates ou délais des contrôles, retrait des fils.' },
  { titre: 'Coordonnées de la clinique', texte: '', aide: 'Téléphone, horaires, urgences.' },
];

/** Modèles de base : structure seule, à compléter par la clinique. */
export const MODELES_BASE: ModeleConsignes[] = [
  'Stérilisation', 'Castration', 'Chirurgie abdominale', 'Chirurgie orthopédique', 'Intervention dentaire', 'Autre intervention',
].map(nom => ({ nom: `${nom} (structure vide)`, type_intervention: nom, sections: SECTIONS_CONSIGNES.map(s => ({ ...s })) }));

/** Sections de départ : saisie existante, sinon le modèle choisi, complété
 *  par les données déjà enregistrées (jamais de consigne inventée). */
export function prerempliConsignes(base: SectionConsigne[], d: {
  intervention?: string | null; traitements?: string | null; controles?: string | null; prochainRdv?: string | null;
  cliniqueCoord?: string[];
}): SectionConsigne[] {
  const out = base.map(s => ({ ...s }));
  const remplir = (titre: string, texte: string) => {
    const s = out.find(x => x.titre === titre);
    if (s && !s.texte.trim() && texte.trim()) s.texte = texte.trim();
  };
  remplir('Intervention réalisée', d.intervention ?? '');
  remplir('Traitements', d.traitements?.trim() ? `${d.traitements.trim()}\n\nLe détail (doses, durée) figure sur l’ordonnance.` : '');
  remplir('Prochains contrôles', [d.controles, d.prochainRdv ? `Prochain rendez-vous : ${d.prochainRdv}` : ''].filter(x => x?.trim()).join('\n'));
  remplir('Coordonnées de la clinique', (d.cliniqueCoord ?? []).join('\n'));
  return out;
}

export function controlerConsignes(sections: SectionConsigne[]): { bloquants: string[]; avertissements: string[] } {
  const bloquants: string[] = [], avertissements: string[] = [];
  const remplies = sections.filter(s => s.texte.trim());
  if (!remplies.length) bloquants.push('Au moins une section rédigée');
  if (sections.some(s => !s.titre.trim() && s.texte.trim())) bloquants.push('Une section rédigée n’a pas de titre');
  const vide = (t: string) => !sections.find(s => s.titre === t)?.texte.trim();
  if (vide('Signes nécessitant de contacter la clinique')) avertissements.push('Signes d’alerte non renseignés');
  if (vide('Coordonnées de la clinique')) avertissements.push('Coordonnées de la clinique non renseignées');
  if (sections.some(s => !s.texte.trim())) avertissements.push('Les sections vides ne figureront pas sur le document');
  return { bloquants, avertissements };
}

/** Texte simple → blocs (titre « ## », puce « - », paragraphe) avec segments gras. */
export type Segment = { texte: string; gras: boolean };
export type BlocConsigne = { type: 'titre' | 'puce' | 'paragraphe'; segments: Segment[] };

export function segmentsGras(ligne: string): Segment[] {
  const out: Segment[] = [];
  const parts = ligne.split('**');
  parts.forEach((p, i) => { if (p) out.push({ texte: p, gras: i % 2 === 1 }); });
  return out;
}

export function blocsConsigne(texte: string): BlocConsigne[] {
  const blocs: BlocConsigne[] = [];
  for (const brut of texte.split('\n')) {
    const l = brut.trim();
    if (!l) continue;
    if (l.startsWith('## ')) blocs.push({ type: 'titre', segments: segmentsGras(l.slice(3)) });
    else if (/^[-•*]\s+/.test(l)) blocs.push({ type: 'puce', segments: segmentsGras(l.replace(/^[-•*]\s+/, '')) });
    else blocs.push({ type: 'paragraphe', segments: segmentsGras(l) });
  }
  return blocs;
}
