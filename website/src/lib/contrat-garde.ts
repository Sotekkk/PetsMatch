// Génération du contrat de prestation garde (petsitter/promeneur) — HTML,
// signature électronique via /signer-contrat/[token] (même mécanisme que
// les contrats éleveur/association/pension — voir contrat-pension.ts).

export interface RdvContrat {
  animal_nom: string;
  espece?: string;
  race?: string;
  client_nom?: string;
  client_contact?: string;
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

function signBlock(role: 'vendeur' | 'acheteur', titre: string, nom: string): string {
  return `
<div class="sign-block" data-signer="${role}">
  <div class="sign-label">${titre}</div>
  <div class="sign-name">${nom || '…'}</div>
  <div class="sign-img"></div>
  <div class="sign-note">« Lu et approuvé »</div>
</div>`;
}

export function generateContratGardeHTML(
  rdv: RdvContrat,
  garde: GardeInfo,
  data: DataContratGarde,
): string {
  const today = new Date().toLocaleDateString('fr-FR');
  const tarif = data.tarif ? `${data.tarif} €` : 'à convenir';

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Contrat de prestation — ${rdv.animal_nom}</title>
<style>${CSS}</style>
</head><body>
<div class="page">

<h1>Contrat de prestation pet sitting / promenade</h1>

<div class="between">Entre les soussignés</div>

<div class="parties">
  <b>${garde.nom}</b>, ci-après désigné « le Prestataire »<br>
  ${garde.adresse ? garde.adresse + '<br>' : ''}
  ${garde.siret ? 'SIRET : ' + garde.siret + '<br>' : ''}
  ${garde.tel ? 'Tél : ' + garde.tel + ' — ' : ''}${garde.email}
</div>

<div class="between">et</div>

<div class="parties">
  <b>${rdv.client_nom || 'Le Client'}</b>, ci-après désigné « le Client »<br>
  ${rdv.client_contact ? 'Contact : ' + rdv.client_contact : ''}
</div>

<h2>Objet du contrat</h2>
<table class="info-table">
  <tr><td>Animal</td><td>${rdv.animal_nom} ${rdv.espece ? '(' + rdv.espece + (rdv.race ? ' — ' + rdv.race : '') + ')' : ''}</td></tr>
  <tr><td>Prestation</td><td>${rdv.type_prestation || 'Visite / promenade'}</td></tr>
  <tr><td>Date de la prestation</td><td>${fmt(rdv.date_visite)}</td></tr>
  <tr><td>Tarif</td><td>${tarif}</td></tr>
</table>

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
    ${signBlock('vendeur', 'Le Prestataire', garde.nom)}
    ${signBlock('acheteur', 'Le Client', rdv.client_nom || '')}
  </div>
</div>

<p class="foot">Contrat de prestation établi le ${today} · PetsMatch</p>
</div>
</body></html>`;
}
