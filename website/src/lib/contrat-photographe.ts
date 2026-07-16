// Génération du contrat de prestation photographe (HTML, signature électronique
// via /signer-contrat/[token] — même mécanisme que les contrats pension/garde).

export interface PhotographeRdvContrat {
  client_nom?: string;
  client_contact?: string;
  animal_nom?: string;
  espece?: string;
  date_shooting?: string;
  lieu?: string;
}

export interface PhotographeInfo {
  nom: string;
  adresse: string;
  email: string;
  tel: string;
  siret?: string;
}

export interface DataContratPhotographe {
  prestationNom?: string;
  prixTotal?: number;
  acomptePourcentage?: number;
  delaiLivraisonJours?: number;
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
.art-title{font-weight:bold;margin:14px 0 4px;font-size:12px;text-transform:uppercase;color:#90A4AE}
.block{margin-bottom:8px}
.sign-section{margin-top:20px}
.sign-row{display:flex;gap:24px}
.sign-block{flex:1;border:1px solid #ddd;border-radius:8px;padding:12px 14px;text-align:center}
.sign-label{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:0.5px;color:#90A4AE;margin-bottom:2px}
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

export function generateContratPrestationPhotoHTML(
  rdv: PhotographeRdvContrat,
  photographe: PhotographeInfo,
  data: DataContratPhotographe,
): string {
  const today = new Date().toLocaleDateString('fr-FR');
  const acompte = data.acomptePourcentage ?? 30;
  const prixTotal = data.prixTotal ?? 0;
  const montantAcompte = Math.round(prixTotal * acompte) / 100;
  const montantSolde = Math.round((prixTotal - montantAcompte) * 100) / 100;

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Contrat de prestation photo — ${rdv.animal_nom ?? ''}</title>
<style>${CSS}</style>
</head><body>
<div class="page">

<h1>Contrat de prestation photographique animalière</h1>

<div class="between">Entre les soussignés</div>

<div class="parties">
  <b>${photographe.nom}</b>, ci-après désigné « le Photographe »<br>
  ${photographe.adresse ? photographe.adresse + '<br>' : ''}
  ${photographe.siret ? 'SIRET : ' + photographe.siret + '<br>' : ''}
  ${photographe.tel ? 'Tél : ' + photographe.tel + ' — ' : ''}${photographe.email}
</div>

<div class="between">et</div>

<div class="parties">
  <b>${rdv.client_nom || 'Le Client'}</b>, ci-après désigné « le Client »<br>
  ${rdv.client_contact ? 'Contact : ' + rdv.client_contact : ''}
</div>

<h2>Objet du contrat</h2>
<table class="info-table">
  <tr><td>Prestation</td><td>${data.prestationNom || 'à définir'}</td></tr>
  <tr><td>Animal</td><td>${rdv.animal_nom ?? ''} ${rdv.espece ? '(' + rdv.espece + ')' : ''}</td></tr>
  <tr><td>Date du shooting</td><td>${fmt(rdv.date_shooting)}</td></tr>
  <tr><td>Lieu</td><td>${rdv.lieu || 'à convenir'}</td></tr>
  <tr><td>Délai de livraison</td><td>${data.delaiLivraisonJours ? data.delaiLivraisonJours + ' jours' : 'à convenir'}</td></tr>
  <tr><td>Prix total</td><td>${prixTotal.toFixed(2)} €</td></tr>
  <tr><td>Acompte (${acompte} %)</td><td>${montantAcompte.toFixed(2)} €</td></tr>
  <tr><td>Solde à la livraison</td><td>${montantSolde.toFixed(2)} €</td></tr>
</table>

<h2>Conditions générales</h2>

<div class="art-title">Art. 1 – Déroulement de la prestation</div>
<div class="block">Le Photographe s'engage à réaliser la prestation décrite ci-dessus à la date et au lieu convenus. Le Client s'engage à assurer la présence et la sécurité de l'animal pendant toute la durée de la séance.</div>

<div class="art-title">Art. 2 – Livraison des photos</div>
<div class="block">Les photos retenues sont livrées dans le délai indiqué ci-dessus, via une galerie numérique en ligne. Le nombre de photos livrées est celui convenu dans la prestation choisie ; des photos supplémentaires peuvent être proposées en option moyennant supplément.</div>

<div class="art-title">Art. 3 – Droits d'usage des photos</div>
<div class="block">Le Client bénéficie d'un droit d'usage privé et non commercial des photos livrées (impression, réseaux sociaux personnels). Toute utilisation commerciale requiert l'accord écrit préalable du Photographe. Le Photographe conserve le droit de présenter les photos dans son book professionnel, sauf refus exprès du Client.</div>

<div class="art-title">Art. 4 – Modalités financières</div>
<div class="block">Un acompte de ${acompte} % du montant total est exigé à la réservation pour confirmer la prestation. Le solde est dû à la livraison des photos. En cas d'annulation moins de 48 h avant la date convenue, l'acompte est conservé. Un déplacement au-delà du forfait inclus donne lieu à un supplément kilométrique facturé en sus.</div>

<div class="art-title">Art. 5 – Responsabilité</div>
<div class="block">Le Photographe ne peut être tenu responsable en cas d'annulation liée au comportement de l'animal rendant la séance impossible ; l'acompte reste dans ce cas acquis. Le Client demeure seul responsable des dommages causés par son animal pendant la séance.</div>

${data.notes ? `<div class="art-title">Art. 6 – Notes complémentaires</div><div class="block">${data.notes}</div>` : ''}

<div class="sign-section">
  <div class="block" style="text-align:right;margin-bottom:8px">Fait le ${today}</div>
  <div class="sign-row">
    ${signBlock('vendeur', 'Le Photographe', photographe.nom)}
    ${signBlock('acheteur', 'Le Client', rdv.client_nom || '')}
  </div>
</div>

<p class="foot">Contrat établi le ${today} · PetsMatch</p>
</div>
</body></html>`;
}
