// Contrats de prestation (site) — bloc « Entre les soussignés », présenté
// comme dans l'appli (lib/pages/eleveur/animaux/contrat_pdf.dart : _line) :
// une ligne « Libellé : valeur » par information, lignes vides omises.
// Utilisé par les contrats éducation, garde, photo, toilettage, maréchal,
// santé et pension.

export const CSS_PARTIES = `
.soussignes{font-weight:bold;text-transform:uppercase;margin:16px 0 2px}
.partie-ligne{margin:0;line-height:1.7}
.partie-ligne b{display:inline-block;min-width:120px}`;

/** Ligne « Libellé : valeur » (omise si la valeur est vide). */
export function lignePartieHtml(label: string, valeur?: string | null): string {
  const v = (valeur ?? '').trim();
  return v ? `<p class="partie-ligne"><b>${label} :</b> ${v}</p>` : '';
}

export interface PrestatairePartie { titre: string; nom: string; adresse?: string | null; tel?: string | null; siret?: string | null; email?: string | null }

/** Bloc complet des parties : prestataire, puis client (lignes [libellé, valeur]). */
export function partiesHtml(prestataire: PrestatairePartie, client: [string, string | null | undefined][]): string {
  return `<style>${CSS_PARTIES}</style>
<p class="soussignes">Entre les soussignés :</p>
${lignePartieHtml(prestataire.titre, prestataire.nom)}
${lignePartieHtml('Demeurant à', prestataire.adresse)}
${lignePartieHtml('Téléphone', prestataire.tel)}
${lignePartieHtml('SIRET', prestataire.siret)}
${lignePartieHtml('Email', prestataire.email)}
<p class="soussignes">Et :</p>
${client.map(([l, v]) => lignePartieHtml(l, v)).join('\n')}`;
}
