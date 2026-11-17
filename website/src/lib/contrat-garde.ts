// Génération du contrat de prestation garde (petsitter/promeneur) — HTML,
// signature électronique via /signer-contrat/[token] (même mécanisme que
// les contrats éleveur/association/pension — voir contrat-pension.ts).

import { lignePartieHtml, partiesHtml } from '@/lib/contrat-parties';
export interface RdvContrat {
  animal_nom: string;
  espece?: string;
  race?: string;
  /** Un seul animal : identification (puce) et date de naissance (fiche). */
  puce?: string;
  date_naissance?: string;
  client_nom?: string;
  client_contact?: string;
  client_adresse?: string;
  client_tel?: string;
  client_email?: string;
  date_visite?: string;
  type_prestation?: string;
}

export interface GardeInfo {
  nom: string;
  adresse: string;
  email: string;
  tel: string;
  siret?: string;
}

export interface DataContratGarde {
  tarif?: string;
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
.art-title{font-weight:bold;margin:14px 0 4px;font-size:12px;text-transform:uppercase;color:#0C5C6C}
.block{margin-bottom:8px}
.sign-section{margin-top:20px}
.sign-row{display:flex;gap:24px}
.sign-block{flex:1;border:1px solid #ddd;border-radius:8px;padding:12px 14px;text-align:center}
.sign-label{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:0.5px;color:#0C5C6C;margin-bottom:2px}
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

function signBlock(role: 'vendeur' | 'acheteur', titre: string, nom: string, sig?: string): string {
  const img = sig
    ? `<img src="${sig}" style="max-height:60px;max-width:100%;object-fit:contain">`
    : '';
  return `
<div class="sign-block" data-signer="${role}">
  <div class="sign-label">${titre}</div>
  <div class="sign-name">${nom || '…'}</div>
  <div class="sign-img">${img}</div>
  <div class="sign-note">« Lu et approuvé »</div>
</div>`;
}

export function generateContratGardeHTML(
  rdv: RdvContrat,
  garde: GardeInfo,
  data: DataContratGarde,
  opts?: { signatureEleveur?: string; signatureAcquereur?: string },
): string {
  const sigElv = opts?.signatureEleveur;
  const sigAcq = opts?.signatureAcquereur;
  const today = new Date().toLocaleDateString('fr-FR');
  const tarif = data.tarif ? `${data.tarif} €` : 'à convenir';

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Contrat de prestation — ${rdv.animal_nom}</title>
<style>${CSS}</style>
</head><body>
<div class="page">

<h1>Contrat de prestation pet sitting / promenade</h1>

${partiesHtml(
  { titre: 'Le Prestataire', nom: garde.nom, adresse: garde.adresse, tel: garde.tel, siret: garde.siret, email: garde.email },
  [['Le Client', rdv.client_nom], ['Demeurant à', rdv.client_adresse], ['Téléphone', rdv.client_tel], ['Email', rdv.client_email || rdv.client_contact]],
)}

<h2>Objet du contrat</h2>
<!-- Même présentation que l'appli (contratGardePdfBytes) et que la pension : animal, espèce / race, identification. -->
${rdv.animal_nom ? '' : `<div class="block">Le présent contrat encadre l'ensemble des prestations de garde, visite ou promenade confiées ponctuellement par le Client au Prestataire. Chaque intervention fait l'objet d'une réservation dans l'application, précisant l'animal concerné, les dates et le tarif applicable.</div>`}
${lignePartieHtml(rdv.animal_nom?.includes(',') ? 'Animaux confiés' : 'Animal confié', rdv.animal_nom)}
${lignePartieHtml('Espèce / race', [rdv.espece ? rdv.espece.charAt(0).toUpperCase() + rdv.espece.slice(1) : '', rdv.race ?? ''].filter(Boolean).join(' — '))}
${lignePartieHtml('Identification', rdv.puce)}
${lignePartieHtml('Date de naissance', rdv.date_naissance ? fmt(rdv.date_naissance) : '')}
${lignePartieHtml('Prestation', rdv.type_prestation || 'Garde / visite / promenade')}
${lignePartieHtml('Date de la prestation', rdv.date_visite ? fmt(rdv.date_visite) : '')}
${lignePartieHtml('Tarif', tarif)}

<h2>Conditions générales de prestation</h2>

<div class="art-title">Art. 1 – Conditions d'accès au domicile</div>
<div class="block">Le Client s'engage à fournir au Prestataire les moyens d'accès nécessaires (clés, codes) à la réalisation de la prestation, et à signaler toute consigne particulière de sécurité (alarme, animaux additionnels, accès restreint).</div>

<div class="art-title">Art. 2 – Soins vétérinaires d'urgence</div>
<div class="block">En cas d'urgence médicale constatée pendant la prestation, le Prestataire est autorisé à faire appel au vétérinaire de garde sans délai. Les frais vétérinaires engagés sont intégralement à la charge du Client et feront l'objet d'une facturation. Le Client sera contacté dès que possible.</div>

<div class="art-title">Art. 3 – Responsabilité civile</div>
<div class="block">Le Prestataire est couvert par une assurance responsabilité civile professionnelle. Le Client demeure seul responsable des dommages causés par son animal à des tiers ou à des biens durant la prestation, dans la limite d'une garde normalement diligente par le Prestataire.</div>

<div class="art-title">Art. 4 – Comportement & sécurité de l'animal</div>
<div class="block">Le Client certifie que l'animal est sociable et ne présente pas de comportement agressif connu. Tout antécédent de morsure, d'attaque ou de comportement dangereux doit être déclaré avant la première prestation.</div>

<div class="art-title">Art. 5 – Modalités financières</div>
<div class="block">Le règlement de la prestation est dû selon les modalités convenues entre les parties. En cas d'annulation moins de 24 h avant la prestation prévue, celle-ci pourra être facturée en tout ou partie selon les conditions du Prestataire.</div>

<div class="art-title">Art. 6 – Force majeure & responsabilité médicale</div>
<div class="block">Le Prestataire ne peut être tenu responsable du décès ou de la maladie d'un animal survenant malgré les soins appropriés, ni en cas de force majeure. Le Prestataire s'engage à mettre tout en œuvre pour assurer le bien-être et la sécurité de l'animal confié.</div>

${data.notes ? `<div class="art-title">Art. 7 – Notes complémentaires</div><div class="block">${data.notes}</div>` : ''}

<div class="sign-section">
  <div class="block" style="text-align:right;margin-bottom:8px">Fait le ${today}</div>
  <div class="sign-row">
    ${signBlock('vendeur', 'Le Prestataire', garde.nom, sigElv)}
    ${signBlock('acheteur', 'Le Client', rdv.client_nom || '', sigAcq)}
  </div>
</div>

<p class="foot">Contrat de prestation établi le ${today} · PetsMatch</p>
</div>
</body></html>`;
}
