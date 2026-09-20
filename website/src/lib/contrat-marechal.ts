// Génération du contrat de prestation maréchalerie (HTML, signature
// électronique via /signer-contrat/[token] — même mécanisme que
// garde/photographe/toilettage).

export interface MarechalRdvContrat {
  client_nom?: string;
  client_contact?: string;
  animal_nom?: string;
  espece?: string;
  date_prestation?: string;
  lieu?: string;
}

export interface MarechalInfo {
  nom: string;
  adresse: string;
  email: string;
  tel: string;
  siret?: string;
}

export interface DataContratMarechal {
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
.art-title{font-weight:bold;margin:14px 0 4px;font-size:12px;text-transform:uppercase;color:#8D6E63}
.block{margin-bottom:8px}
.sign-section{margin-top:20px}
.sign-row{display:flex;gap:24px}
.sign-block{flex:1;border:1px solid #ddd;border-radius:8px;padding:12px 14px;text-align:center}
.sign-label{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:0.5px;color:#8D6E63;margin-bottom:2px}
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

export function generateContratPrestationMarechalHTML(
  rdv: MarechalRdvContrat,
  marechal: MarechalInfo,
  data: DataContratMarechal,
): string {
  const today = new Date().toLocaleDateString('fr-FR');
  const prixTotal = data.prixTotal ?? 0;

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Contrat de prestation maréchalerie — ${rdv.animal_nom ?? ''}</title>
<style>${CSS}</style>
</head><body>
<div class="page">

<h1>Contrat de prestation de maréchalerie</h1>

<div class="between">Entre les soussignés</div>

<div class="parties">
  <b>${marechal.nom}</b>, ci-après désigné « le Prestataire »<br>
  ${marechal.adresse ? marechal.adresse + '<br>' : ''}
  ${marechal.siret ? 'SIRET : ' + marechal.siret + '<br>' : ''}
  ${marechal.tel ? 'Tél : ' + marechal.tel + ' — ' : ''}${marechal.email}
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
  <tr><td>Date de la prestation</td><td>${fmt(rdv.date_prestation)}</td></tr>
  <tr><td>Lieu</td><td>${rdv.lieu || 'à convenir'}</td></tr>
  <tr><td>Prix</td><td>${prixTotal.toFixed(2)} €</td></tr>
</table>

<h2>Conditions générales</h2>

<div class="art-title">Art. 1 – Déroulement de la prestation</div>
<div class="block">Le Prestataire s'engage à réaliser la prestation de maréchalerie (parage, ferrage ou soins des pieds) décrite ci-dessus dans les règles de l'art. Le Client s'engage à assurer la présence et la contention de l'animal pendant toute la durée de l'intervention, dans des conditions de sécurité satisfaisantes.</div>

<div class="art-title">Art. 2 – État de santé et comportement de l'animal</div>
<div class="block">Le Client s'engage à signaler au Prestataire, avant toute intervention, tout problème de santé, boiterie, traitement en cours ou particularité de comportement de l'animal susceptible d'affecter le déroulement de la prestation. Le Prestataire se réserve le droit d'interrompre ou de refuser l'intervention si les conditions de sécurité ne sont pas réunies.</div>

<div class="art-title">Art. 3 – Modalités financières</div>
<div class="block">Le prix indiqué ci-dessus est dû à l'issue de la prestation. En cas d'annulation moins de 24 h avant le rendez-vous, le déplacement peut être facturé au Client.</div>

<div class="art-title">Art. 4 – Responsabilité</div>
<div class="block">Le Prestataire met en œuvre tous les moyens nécessaires pour assurer la sécurité de l'animal et des personnes présentes pendant l'intervention. Le Client demeure responsable des informations transmises sur l'état de santé et le comportement de son animal ; toute omission engageant sa responsabilité en cas d'incident.</div>

${data.notes ? `<div class="art-title">Art. 5 – Notes complémentaires</div><div class="block">${data.notes}</div>` : ''}

<div class="sign-section">
  <div class="block" style="text-align:right;margin-bottom:8px">Fait le ${today}</div>
  <div class="sign-row">
    ${signBlock('vendeur', 'Le Prestataire', marechal.nom)}
    ${signBlock('acheteur', 'Le Client', rdv.client_nom || '')}
  </div>
</div>

<p class="foot">Contrat établi le ${today} · PetsMatch</p>
</div>
</body></html>`;
}
