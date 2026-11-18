// Génération du contrat de prestation toilettage (HTML, signature électronique
// via /signer-contrat/[token] — même mécanisme que garde/photographe).

import { lignePartieHtml, partiesHtml } from '@/lib/contrat-parties';
export interface ToilettageRdvContrat {
  client_nom?: string;
  client_contact?: string;
  client_email?: string;
  client_tel?: string;
  client_adresse?: string;
  animal_nom?: string;
  /** Animaux concernés (fiches) : nom, espèce / race, identification, naissance. */
  animaux?: { nom: string; espece?: string; race?: string; identification?: string; date_naissance?: string | null }[];
  espece?: string;
  date_prestation?: string;
  lieu?: string;
}

export interface ToilettageInfo {
  nom: string;
  adresse: string;
  email: string;
  tel: string;
  siret?: string;
}

export interface DataContratToilettage {
  prestationNom?: string;
  prixTotal?: number;
  notes?: string;
}

const CSS = `
*{box-sizing:border-box}
body{font-family:Arial,sans-serif;font-size:11.5px;margin:0;color:#222;line-height:1.6}
.page{max-width:780px;margin:0 auto;padding:30px 40px 60px}
h1{font-size:18px;text-align:center;margin-bottom:2px;letter-spacing:1px;text-transform:uppercase}
h2{font-size:13px;text-align:center;text-transform:uppercase;letter-spacing:0.5px;margin:24px 0 10px}
.parties{margin:18px 0;line-height:2}
.between{text-align:center;font-style:italic;margin:12px 0}
.art-title{font-weight:bold;margin:14px 0 4px;font-size:12px;text-transform:uppercase;color:#FFB74D}
.block{margin-bottom:8px}
.sign-section{margin-top:20px}
.sign-row{display:flex;gap:24px}
.sign-block{flex:1;border:1px solid #ddd;border-radius:8px;padding:12px 14px;text-align:center}
.sign-label{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:0.5px;color:#FFB74D;margin-bottom:2px}
.sign-name{font-size:10px;color:#555;margin-bottom:6px}
.sign-img{height:64px;border-bottom:1px solid #888;display:flex;align-items:center;justify-content:center;margin-bottom:4px}
.sign-img img{max-height:60px;max-width:100%;object-fit:contain}
.sign-img:not(:has(img))::after{content:"_________________________";color:#bbb;font-size:11px}
.sign-note{font-size:9px;color:#888}
.foot{margin-top:16px;font-size:9px;color:#aaa;text-align:center}
.info-table{width:100%;border-collapse:collapse;margin:10px 0}
.info-table td{padding:4px 6px;border-bottom:1px solid #eee}
.info-table td:first-child{color:#666;width:40%}
@media print{
  .page{padding:20px 30px 30px}
  .sign-block{border:1px solid #aaa}
}
`;

function fmt(d?: string): string {
  if (!d) return '—';
  try { return new Date(d).toLocaleDateString('fr-FR'); } catch { return d; }
}

function signBlock(role: 'vendeur' | 'acheteur', titre: string, nom: string): string {
  return `
<div class="sign-block" data-signer="${role}">
  <div class="sign-label">${titre}</div>
  <div class="sign-name">${nom || '…'}</div>
  <div class="sign-img"></div>
  <div class="sign-note">« Lu et approuvé »</div>
</div>`;
}

const espRace = (espece?: string, race?: string) =>
  [espece ? espece.charAt(0).toUpperCase() + espece.slice(1) : '', race ?? ''].filter(Boolean).join(' — ');

/** Un animal : nom, espèce / race, identification, naissance ; plusieurs : une ligne chacun. */
function animauxHtml(rdv: ToilettageRdvContrat): string {
  const l = (rdv.animaux ?? []).filter(a => a.nom);
  if (l.length > 1) {
    return lignePartieHtml('Animaux', l.map(a => {
      const d = [espRace(a.espece, a.race), a.identification ? `puce ${a.identification}` : '', a.date_naissance ? `né(e) le ${fmt(a.date_naissance)}` : '']
        .filter(Boolean).join(', ');
      return d ? `${a.nom} (${d})` : a.nom;
    }).join(' ; '));
  }
  const a = l[0];
  return [
    lignePartieHtml('Animal', a?.nom || rdv.animal_nom),
    lignePartieHtml('Espèce / race', a ? espRace(a.espece, a.race) : espRace(rdv.espece)),
    lignePartieHtml('Identification', a?.identification),
    lignePartieHtml('Date de naissance', a?.date_naissance ? fmt(a.date_naissance) : ''),
  ].join('');
}

export function generateContratPrestationToilettageHTML(
  rdv: ToilettageRdvContrat,
  toiletteur: ToilettageInfo,
  data: DataContratToilettage,
): string {
  const today = new Date().toLocaleDateString('fr-FR');
  const prixTotal = data.prixTotal ?? 0;

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Contrat de prestation toilettage — ${rdv.animal_nom ?? ''}</title>
<style>${CSS}</style>
</head><body>
<div class="page">

<h1>Contrat de prestation de toilettage animalier</h1>

${partiesHtml(
  { titre: 'Le Prestataire', nom: toiletteur.nom, adresse: toiletteur.adresse, tel: toiletteur.tel, siret: toiletteur.siret, email: toiletteur.email },
  [['Le Client', rdv.client_nom], ['Demeurant à', rdv.client_adresse], ['Téléphone', rdv.client_tel],
   ['Email', rdv.client_email || (rdv.client_tel || rdv.client_adresse ? '' : rdv.client_contact)]],
)}

<h2>Objet du contrat</h2>
<!-- Même présentation que l'appli (contratToilettagePdfBytes) et que les contrats de garde / pension. -->
${lignePartieHtml('Prestation', data.prestationNom || 'à définir')}
${animauxHtml(rdv)}
${lignePartieHtml('Date de la prestation', rdv.date_prestation ? fmt(rdv.date_prestation) : '')}
${lignePartieHtml('Lieu', rdv.lieu || 'à convenir')}
${lignePartieHtml('Prix', prixTotal > 0 ? `${prixTotal.toFixed(2).replace('.', ',')} €` : 'à convenir')}

<h2>Conditions générales</h2>

<div class="art-title">Art. 1 – Déroulement de la prestation</div>
<div class="block">Le Prestataire s'engage à réaliser la prestation de toilettage décrite ci-dessus dans les règles de l'art, avec le souci du bien-être et de la sécurité de l'animal. Le Client s'engage à récupérer l'animal à l'heure convenue.</div>

<div class="art-title">Art. 2 – État de santé et comportement de l'animal</div>
<div class="block">Le Client s'engage à signaler au Prestataire, avant toute prestation, tout problème de santé, allergie, traitement en cours, antécédent comportemental (agressivité, anxiété) ou toute particularité de l'animal susceptible d'affecter le déroulement de la séance. Le Prestataire se réserve le droit d'interrompre ou de refuser une prestation si l'état de l'animal le justifie, sans que cela ne donne lieu à remboursement de l'acompte le cas échéant.</div>

<div class="art-title">Art. 3 – Constat de l'état de l'animal</div>
<div class="block">Le Prestataire examine l'animal à son arrivée et signale au Client toute anomalie constatée (nœuds importants, lésions cutanées, parasites, etc.) pouvant nécessiter une prestation adaptée ou un tarif complémentaire, accepté préalablement par le Client.</div>

<div class="art-title">Art. 4 – Modalités financières</div>
<div class="block">Le prix indiqué ci-dessus est dû à l'issue de la prestation, sauf acompte convenu à la réservation. En cas d'annulation moins de 24 h avant le rendez-vous, un acompte éventuellement versé peut être conservé par le Prestataire.</div>

<div class="art-title">Art. 5 – Responsabilité</div>
<div class="block">Le Prestataire met en œuvre tous les moyens nécessaires pour assurer la sécurité de l'animal pendant la prestation. Le Client demeure responsable des informations transmises sur l'état de santé et le comportement de son animal ; toute omission engageant sa responsabilité en cas d'incident.</div>

${data.notes ? `<div class="art-title">Art. 6 – Notes complémentaires</div><div class="block">${data.notes}</div>` : ''}

<div class="sign-section">
  <div class="block" style="text-align:right;margin-bottom:8px">Fait le ${today}</div>
  <div class="sign-row">
    ${signBlock('vendeur', 'Le Prestataire', toiletteur.nom)}
    ${signBlock('acheteur', 'Le Client', rdv.client_nom || '')}
  </div>
</div>

<p class="foot">Contrat établi le ${today} · PetsMatch</p>
</div>
</body></html>`;
}
