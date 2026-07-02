// Génération du contrat d'hébergement pension (HTML, signature électronique
// via /signer-contrat/[token] — même mécanisme que les contrats éleveur/association).

export interface PensionEntreeContrat {
  animal_nom: string;
  espece?: string;
  race?: string;
  proprietaire_nom?: string;
  proprietaire_contact?: string;
  date_entree?: string;
  date_sortie_prevue?: string;
}

export interface PensionInfo {
  nom: string;
  adresse: string;
  email: string;
  tel: string;
  siret?: string;
}

export interface DataContratPension {
  tarifNuit?: string;
  arrhesPourcentage?: number;
  logementNom?: string;
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

export function generateContratHebergementHTML(
  entree: PensionEntreeContrat,
  pension: PensionInfo,
  data: DataContratPension,
): string {
  const today = new Date().toLocaleDateString('fr-FR');
  const arrhes = data.arrhesPourcentage ?? 0;
  const tarif = data.tarifNuit ? `${data.tarifNuit} €/nuit` : 'à convenir';

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Contrat d'hébergement — ${entree.animal_nom}</title>
<style>${CSS}</style>
</head><body>
<div class="page">

<h1>Contrat d'hébergement en pension animalière</h1>

<div class="between">Entre les soussignés</div>

<div class="parties">
  <b>${pension.nom}</b>, ci-après désigné « la Pension »<br>
  ${pension.adresse ? pension.adresse + '<br>' : ''}
  ${pension.siret ? 'SIRET : ' + pension.siret + '<br>' : ''}
  ${pension.tel ? 'Tél : ' + pension.tel + ' — ' : ''}${pension.email}
</div>

<div class="between">et</div>

<div class="parties">
  <b>${entree.proprietaire_nom || 'Le Propriétaire'}</b>, ci-après désigné « le Propriétaire »<br>
  ${entree.proprietaire_contact ? 'Contact : ' + entree.proprietaire_contact : ''}
</div>

<h2>Objet du contrat</h2>
<table class="info-table">
  <tr><td>Animal</td><td>${entree.animal_nom} ${entree.espece ? '(' + entree.espece + (entree.race ? ' — ' + entree.race : '') + ')' : ''}</td></tr>
  <tr><td>Logement</td><td>${data.logementNom || 'à définir à l\'admission'}</td></tr>
  <tr><td>Date d'entrée</td><td>${fmt(entree.date_entree)}</td></tr>
  <tr><td>Date de sortie prévue</td><td>${fmt(entree.date_sortie_prevue)}</td></tr>
  <tr><td>Tarif</td><td>${tarif}</td></tr>
  <tr><td>Arrhes à la réservation</td><td>${arrhes > 0 ? arrhes + ' % du montant total' : 'aucune'}</td></tr>
</table>

<h2>Conditions générales de pension</h2>

<div class="art-title">Art. 1 – Conditions d'admission</div>
<div class="block">L'animal est admis sous réserve d'être à jour de ses vaccinations obligatoires et traitements antiparasitaires. Le propriétaire s'engage à fournir tout document sanitaire demandé par la pension à l'admission. En cas de maladie contagieuse déclarée, la pension se réserve le droit de refuser l'accueil.</div>

<div class="art-title">Art. 2 – Soins vétérinaires d'urgence</div>
<div class="block">En cas d'urgence médicale, la pension est autorisée à faire appel au vétérinaire de garde sans délai. Les frais vétérinaires engagés sont intégralement à la charge du propriétaire et feront l'objet d'une facturation. Le propriétaire sera contacté dès que possible.</div>

<div class="art-title">Art. 3 – Responsabilité civile</div>
<div class="block">La pension est couverte par une assurance responsabilité civile professionnelle. Le propriétaire demeure seul responsable des dommages causés par son animal à des tiers, à d'autres animaux ou aux installations de la pension.</div>

<div class="art-title">Art. 4 – Comportement & sécurité</div>
<div class="block">Le propriétaire certifie que l'animal est sociable et ne présente pas de comportement agressif connu. Tout antécédent de morsure, d'attaque ou de comportement dangereux doit être déclaré à l'admission.</div>

<div class="art-title">Art. 5 – Alimentation</div>
<div class="block">L'alimentation standard est assurée par la pension. Tout régime spécifique doit être signalé à l'admission et accompagné des aliments nécessaires fournis par le propriétaire.</div>

<div class="art-title">Art. 6 – Modalités financières</div>
<div class="block">${arrhes > 0 ? `Un acompte de ${arrhes} % du montant total est exigé à la réservation pour confirmer le séjour. ` : ''}Le solde est dû à l'admission. En cas d'annulation moins de 48 h avant la date d'entrée, l'acompte est conservé. Tout séjour commencé est dû dans son intégralité.</div>

<div class="art-title">Art. 7 – Prolongation & sortie</div>
<div class="block">Toute prolongation de séjour doit être signalée au préalable et fera l'objet d'une facturation complémentaire. L'animal non récupéré dans les 72 h suivant la date de sortie prévue, sans contact du propriétaire, pourra être confié à la SPA ou à une autorité compétente aux frais du propriétaire.</div>

<div class="art-title">Art. 8 – Force majeure & responsabilité médicale</div>
<div class="block">La pension ne peut être tenue responsable du décès ou de la maladie d'un animal survenant malgré les soins appropriés, ni en cas de force majeure. La pension s'engage à mettre tout en œuvre pour assurer le bien-être et la sécurité de l'animal confié.</div>

${data.notes ? `<div class="art-title">Art. 9 – Notes complémentaires</div><div class="block">${data.notes}</div>` : ''}

<div class="sign-section">
  <div class="block" style="text-align:right;margin-bottom:8px">Fait le ${today}</div>
  <div class="sign-row">
    ${signBlock('vendeur', 'La Pension', pension.nom)}
    ${signBlock('acheteur', 'Le Propriétaire', entree.proprietaire_nom || '')}
  </div>
</div>

<p class="foot">Contrat d'hébergement établi le ${today} · PetsMatch</p>
</div>
</body></html>`;
}
