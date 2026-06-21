// Contrat d'adoption association — génération HTML pour impression / signature électronique

export interface AssociationInfo {
  nom: string;
  adresse?: string;
  tel?: string;
  email?: string;
  siret?: string;
  president?: string;
}

export interface AnimalAdoption {
  nom?: string;
  espece?: string;
  race?: string;
  sexe?: string;
  identification?: string;
  date_naissance?: string;
  couleur?: string;
  vaccine?: boolean;
  sterilise?: boolean;
  traite?: boolean;
}

export interface AdoptantInfo {
  nom?: string;
  prenom?: string;
  adresse?: string;
  tel?: string;
  email?: string;
}

export interface DataAdoption {
  participation?: string;
  dateContrat?: string;
  avecSteril?: boolean;
  notes?: string;
  acquereur_email?: string;
  acquereur_nom?: string;
}

// Participation aux frais par défaut selon l'espèce
export const PARTICIPATION_DEFAUT: Record<string, number> = {
  chien: 150, chat: 100, cheval: 500, lapin: 50,
  oiseau: 30, nac: 50, ovin: 80, caprin: 80, porcin: 80, autre: 50,
};

function fmtDate(s?: string | null) {
  if (!s) return '____/____/________';
  return new Date(s).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

function sexeLabel(s?: string) {
  return s === 'male' || s === 'mâle' ? 'Mâle' : s === 'femelle' ? 'Femelle' : (s ?? '—');
}

const CSS = `
*{box-sizing:border-box}
body{font-family:Arial,sans-serif;font-size:11.5px;margin:0;color:#222;line-height:1.6;orphans:4;widows:4}
.page{max-width:780px;margin:0 auto;padding:30px 40px 120px}
h1{font-size:17px;text-align:center;margin-bottom:2px;letter-spacing:1px;text-transform:uppercase;page-break-after:avoid;break-after:avoid}
.subtitle{text-align:center;font-size:12px;color:#555;margin-bottom:18px}
h2{font-size:12px;text-transform:uppercase;letter-spacing:0.5px;margin:20px 0 6px;border-bottom:1px solid #333;padding-bottom:3px;page-break-after:avoid;break-after:avoid}
.parties{margin:14px 0;line-height:2;page-break-inside:avoid;break-inside:avoid}
.between{text-align:center;font-style:italic;margin:10px 0;font-size:11px}
.animal-table{width:100%;border-collapse:collapse;margin:8px 0}
.animal-table td{padding:4px 8px;border:1px solid #ccc;font-size:11px}
.animal-table td:first-child{font-weight:bold;background:#f5f5f5;width:40%}
.article{margin:14px 0;page-break-inside:avoid;break-inside:avoid}
.article p{margin:4px 0}
ul.clauses{margin:6px 0;padding-left:20px}
ul.clauses li{margin:4px 0}
.montant{font-size:14px;font-weight:bold;color:#0a5a6a;border:2px solid #0a5a6a;display:inline-block;padding:4px 12px;border-radius:6px;margin:6px 0}
.sign-block{display:flex;gap:40px;margin-top:40px;page-break-inside:avoid;break-inside:avoid}
.sign-col{flex:1;min-width:0}
.sign-col p{font-size:11px;margin:0 0 6px}
.sign-area{border:1px solid #ccc;border-radius:4px;min-height:80px;background:#fafafa}
.sign-img{max-width:100%;height:80px;object-fit:contain}
.date-line{font-size:11px;color:#555;margin-top:4px}
.note-box{background:#f9f9f9;border:1px solid #ddd;border-radius:4px;padding:8px 12px;margin:8px 0;font-size:11px}
.warn{color:#b45309;font-weight:bold}
@media print{
  body{font-size:10.5px}
  .no-print{display:none}
  .page{padding:20px 30px 80px}
}
`;

export function generateContratAdoptionHTML(
  asso: AssociationInfo,
  animal: AnimalAdoption,
  adoptant: AdoptantInfo,
  data: DataAdoption,
  opts: { signatureEleveur?: string; signatureAcquereur?: string } = {}
): string {
  const dateContrat = fmtDate(data.dateContrat);
  const participation = data.participation ? `${data.participation} €` : `${PARTICIPATION_DEFAUT[animal.espece?.toLowerCase() ?? ''] ?? 50} €`;
  const nomAnimal = animal.nom ?? '(animal)';
  const nomAsso = asso.nom || 'L\'association';
  const nomAdoptant = `${adoptant.prenom ?? ''} ${adoptant.nom ?? ''}`.trim() || 'L\'adoptant(e)';
  const needSteril = data.avecSteril !== false && animal.sterilise !== true;

  const animalRows = [
    ['Nom', nomAnimal],
    ['Espèce / Race', [animal.espece, animal.race].filter(Boolean).join(' — ') || '—'],
    ['Sexe', sexeLabel(animal.sexe)],
    ['Date de naissance', fmtDate(animal.date_naissance)],
    ['Identification / Puce', animal.identification || 'Non fourni'],
    ['Couleur / Robe', animal.couleur || '—'],
    ['Vacciné', animal.vaccine ? 'Oui' : 'Non précisé'],
    ['Stérilisé', animal.sterilise ? 'Oui' : 'Non'],
    ['Traité antiparasitaire', animal.traite ? 'Oui' : 'Non précisé'],
  ];

  const signAsso = opts.signatureEleveur
    ? `<img class="sign-img" src="${opts.signatureEleveur}" alt="Signature association" />`
    : '<div class="sign-area"></div>';
  const signAdoptant = opts.signatureAcquereur
    ? `<img class="sign-img" src="${opts.signatureAcquereur}" alt="Signature adoptant" />`
    : '<div class="sign-area"></div>';

  return `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8">
<title>Contrat d'adoption — ${nomAnimal}</title>
<style>${CSS}</style></head><body><div class="page">

<h1>Contrat d'adoption</h1>
<p class="subtitle">${nomAsso}</p>

<h2>Article 1 — Les parties</h2>
<div class="parties">
  <strong>L'association cédante :</strong><br>
  ${nomAsso}${asso.adresse ? ` — ${asso.adresse}` : ''}${asso.siret ? ` — SIRET : ${asso.siret}` : ''}
  ${asso.president ? `<br>Représentée par ${asso.president}` : ''}
  ${asso.tel ? ` — Tél : ${asso.tel}` : ''}${asso.email ? ` — Email : ${asso.email}` : ''}
  <br><br>
  <strong>L'adoptant(e) :</strong><br>
  ${nomAdoptant}${adoptant.adresse ? ` — ${adoptant.adresse}` : ''}
  ${adoptant.tel ? ` — Tél : ${adoptant.tel}` : ''}${adoptant.email ? ` — Email : ${adoptant.email}` : ''}
</div>
<p class="between">ont conclu le <strong>${dateContrat}</strong> le contrat d'adoption suivant :</p>

<h2>Article 2 — Identification de l'animal</h2>
<table class="animal-table">
  <tbody>
    ${animalRows.map(([l, v]) => `<tr><td>${l}</td><td>${v}</td></tr>`).join('')}
  </tbody>
</table>

<h2>Article 3 — Participation aux frais d'adoption</h2>
<div class="article">
  <p>En contrepartie de la cession à titre d'adoption de <strong>${nomAnimal}</strong>, l'adoptant(e) versera à l'association une participation aux frais d'adoption d'un montant de :</p>
  <p><span class="montant">${participation}</span></p>
  <p style="font-size:11px;color:#555">Cette somme couvre notamment les frais vétérinaires engagés (vaccinations, traitements, stérilisation éventuelle, identification). Elle ne constitue pas un prix de vente.</p>
</div>

<h2>Article 4 — Engagements de l'adoptant(e)</h2>
<div class="article">
  <ul class="clauses">
    <li>Offrir à <strong>${nomAnimal}</strong> des conditions de vie adaptées à son espèce : alimentation appropriée, soins vétérinaires réguliers, environnement adapté et sécurisé.</li>
    <li>Ne pas céder, vendre, prêter ou abandonner l'animal sans accord préalable de l'association.</li>
    <li>Signaler tout changement de domicile à l'association dans les 15 jours.</li>
    <li>En cas d'impossibilité définitive de garde, restituer l'animal à <strong>${nomAsso}</strong> et non à un tiers.</li>
    <li>Informer l'association en cas de perte, vol, maladie grave ou décès de l'animal.</li>
    ${needSteril ? `<li class="warn">S'engager à faire stériliser l'animal dès que l'âge le permet, et à en fournir la preuve vétérinaire à l'association.</li>` : ''}
  </ul>
</div>

<h2>Article 5 — Droits de l'association</h2>
<div class="article">
  <ul class="clauses">
    <li>${nomAsso} se réserve le droit d'effectuer des visites de contrôle du bien-être animal dans le foyer adoptant, avec un préavis raisonnable.</li>
    <li>En cas de maltraitance avérée, non-respect des engagements ou danger pour l'animal, l'association pourra procéder à la reprise immédiate de l'animal et en informer les autorités compétentes.</li>
  </ul>
</div>

<h2>Article 6 — Conditions de retour</h2>
<div class="article">
  <p>Si pour quelque raison que ce soit l'adoptant(e) n'est plus en mesure de garder <strong>${nomAnimal}</strong>, il/elle s'engage à le retourner à <strong>${nomAsso}</strong> dans les meilleurs délais. La participation aux frais versée ne sera pas remboursée.</p>
</div>

${data.notes ? `<h2>Notes complémentaires</h2><div class="note-box">${data.notes}</div>` : ''}

<h2>Signatures</h2>
<div class="sign-block">
  <div class="sign-col">
    <p><strong>L'association cédante</strong><br>${nomAsso}</p>
    ${signAsso}
    <p class="date-line">Fait le : ${dateContrat}</p>
  </div>
  <div class="sign-col">
    <p><strong>L'adoptant(e)</strong><br>${nomAdoptant}</p>
    ${signAdoptant}
    <p class="date-line">Fait le : ${dateContrat}</p>
  </div>
</div>

<p style="font-size:10px;color:#888;margin-top:32px;border-top:1px solid #eee;padding-top:8px">
  Document généré via PetsMatch — ${new Date().toLocaleDateString('fr-FR')}. Ce contrat constitue un engagement moral et civil entre les parties.
</p>

</div></body></html>`;
}
