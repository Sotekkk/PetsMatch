// Génération du contrat de prestation d'éducation canine / comportementaliste
// — HTML, signature électronique via /signer-contrat/[token] (même mécanisme
// que les contrats éleveur/garde — voir contrat-garde.ts). Peut être issu
// directement d'un devis accepté (lignes de prestation détaillées).

export interface LigneEducation {
  description: string;
  quantite: number;
  prix_unitaire: number;
  total: number;
}

export interface PrestationEducation {
  animal_nom?: string;
  espece?: string;
  race?: string;
  client_nom?: string;
  client_contact?: string;
  date_prestation?: string;
  lignes?: LigneEducation[];
  total_ttc?: number;
  date_validite?: string;
}

export interface EducateurInfo {
  nom: string;
  adresse: string;
  email: string;
  tel: string;
  siret?: string;
}

export interface DataContratEducation {
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
.lignes-table{width:100%;border-collapse:collapse;margin:10px 0}
.lignes-table th{background:#F1F5F4;color:#0C5C6C;font-size:10px;text-transform:uppercase;letter-spacing:0.3px;padding:6px 8px;text-align:left}
.lignes-table td{padding:6px 8px;border-bottom:1px solid #eee}
.lignes-table td.num{text-align:right;white-space:nowrap}
.lignes-table tfoot td{font-weight:bold;border-top:2px solid #0C5C6C;border-bottom:none}
@media print{
  .page{padding:20px 30px 30px}
  .sign-block{border:1px solid #aaa}
}
`;

function fmt(d?: string): string {
  if (!d) return '—';
  try { return new Date(d).toLocaleDateString('fr-FR'); } catch { return d; }
}

function eur(n?: number): string {
  return `${(n ?? 0).toFixed(2)} €`;
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

export function generateContratEducationHTML(
  prestation: PrestationEducation,
  educateur: EducateurInfo,
  data: DataContratEducation,
): string {
  const today = new Date().toLocaleDateString('fr-FR');
  const lignes = prestation.lignes ?? [];
  const total = prestation.total_ttc ?? lignes.reduce((s, l) => s + (l.total ?? 0), 0);

  const lignesHtml = lignes.length
    ? `<table class="lignes-table">
        <thead><tr><th>Prestation</th><th class="num">Qté</th><th class="num">P.U.</th><th class="num">Total</th></tr></thead>
        <tbody>
          ${lignes.map(l => `<tr><td>${l.description}</td><td class="num">${l.quantite}</td><td class="num">${eur(l.prix_unitaire)}</td><td class="num">${eur(l.total)}</td></tr>`).join('')}
        </tbody>
        <tfoot><tr><td colspan="3">Total TTC</td><td class="num">${eur(total)}</td></tr></tfoot>
      </table>`
    : `<table class="info-table"><tr><td>Montant</td><td>${eur(total)}</td></tr></table>`;

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Contrat de prestation d'éducation — ${prestation.animal_nom ?? ''}</title>
<style>${CSS}</style>
</head><body>
<div class="page">

<h1>Contrat de prestation d'éducation canine</h1>

<div class="between">Entre les soussignés</div>

<div class="parties">
  <b>${educateur.nom}</b>, ci-après désigné « le Prestataire »<br>
  ${educateur.adresse ? educateur.adresse + '<br>' : ''}
  ${educateur.siret ? 'SIRET : ' + educateur.siret + '<br>' : ''}
  ${educateur.tel ? 'Tél : ' + educateur.tel + ' — ' : ''}${educateur.email}
</div>

<div class="between">et</div>

<div class="parties">
  <b>${prestation.client_nom || 'Le Client'}</b>, ci-après désigné « le Client »<br>
  ${prestation.client_contact ? 'Contact : ' + prestation.client_contact : ''}
</div>

<h2>Objet du contrat</h2>
<table class="info-table">
  ${prestation.animal_nom ? `<tr><td>Animal</td><td>${prestation.animal_nom} ${prestation.espece ? '(' + prestation.espece + (prestation.race ? ' — ' + prestation.race : '') + ')' : ''}</td></tr>` : ''}
  ${prestation.date_prestation ? `<tr><td>Date de la prestation</td><td>${fmt(prestation.date_prestation)}</td></tr>` : ''}
  ${prestation.date_validite ? `<tr><td>Devis valable jusqu'au</td><td>${fmt(prestation.date_validite)}</td></tr>` : ''}
</table>

<h2>Détail de la prestation</h2>
${lignesHtml}

<h2>Conditions générales de prestation</h2>

<div class="art-title">Art. 1 – Objet</div>
<div class="block">Le Prestataire s'engage à réaliser, pour le compte du Client, la ou les séances d'éducation canine / comportementalisme décrites ci-dessus, selon les modalités convenues entre les parties.</div>

<div class="art-title">Art. 2 – Engagement du Client</div>
<div class="block">Le Client s'engage à être présent (ou à faire présenter l'animal par une personne majeure de son entourage) aux séances convenues, et à appliquer les consignes de suivi transmises par le Prestataire entre les séances.</div>

<div class="art-title">Art. 3 – Comportement & sécurité de l'animal</div>
<div class="block">Le Client certifie que l'animal est à jour de ses vaccins et déclare tout antécédent de morsure, d'attaque ou de comportement dangereux avant la première séance. Le Prestataire se réserve le droit d'interrompre une séance en cas de danger pour les personnes présentes.</div>

<div class="art-title">Art. 4 – Responsabilité civile</div>
<div class="block">Le Prestataire est couvert par une assurance responsabilité civile professionnelle. Le Client demeure seul responsable des dommages causés par son animal à des tiers ou à des biens durant la prestation.</div>

<div class="art-title">Art. 5 – Modalités financières & annulation</div>
<div class="block">Le règlement de la prestation est dû selon les modalités convenues entre les parties. En cas d'annulation moins de 24 h avant une séance prévue, celle-ci pourra être facturée en tout ou partie selon les conditions du Prestataire.</div>

<div class="art-title">Art. 6 – Résultats & obligation de moyens</div>
<div class="block">Le Prestataire s'engage à mettre en œuvre les moyens professionnels appropriés à l'éducation ou la rééducation comportementale de l'animal. Les résultats dépendent également de l'implication du Client et de facteurs propres à l'animal ; le Prestataire est tenu à une obligation de moyens, non de résultat.</div>

${data.notes ? `<div class="art-title">Art. 7 – Notes complémentaires</div><div class="block">${data.notes}</div>` : ''}

<div class="sign-section">
  <div class="block" style="text-align:right;margin-bottom:8px">Fait le ${today}</div>
  <div class="sign-row">
    ${signBlock('vendeur', 'Le Prestataire', educateur.nom)}
    ${signBlock('acheteur', 'Le Client', prestation.client_nom || '')}
  </div>
</div>

<p class="foot">Contrat de prestation établi le ${today} · PetsMatch</p>
</div>
</body></html>`;
}
