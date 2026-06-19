// Template contrat de vente — partagé entre CessionModal et /elevage/contrat

export interface EleveurContrat {
  nom: string;
  adresse?: string;
  tel?: string;
  email?: string;
  siret?: string;
}

export interface AnimalContrat {
  nom?: string;
  espece?: string;
  race?: string;
  sexe?: string;
  identification?: string;
  date_naissance?: string;
}

export interface DataContrat {
  qualite?: string;
  nom?: string;
  email?: string;
  tel?: string;
  adresse?: string;
  dateCession?: string;
  prix?: string;
  notes?: string;
}

export function animalTerms(espece?: string) {
  switch ((espece ?? '').toLowerCase()) {
    case 'chien':  return { jeune:'chiot',    pedigree:'LOF ou pedigree club FFP n°', vices:'maladie de Carré, de Rubarth, parvovirose, dysplasie coxo-fémorale, atrophie rétinienne, ectopie testiculaire (seulement si cédé âgé de plus de 6 mois pour un chien)', sterilM:'12 mois à compter de la date de naissance pour un chiot mâle', sterilF:'12 mois à compter de la date de naissance pour un chiot femelle (ou après ses premières chaleurs)' };
    case 'chat':   return { jeune:'chaton',   pedigree:'LOOF n°', vices:'leucopénie et péritonite infectieuses félines, virus leucémogène félin (FeLV), immunodéficience féline (FIV)', sterilM:'6 mois à compter de la date de naissance', sterilF:'6 mois à compter de la date de naissance (ou après les premières chaleurs)' };
    case 'lapin':  return { jeune:'lapereau', pedigree:'N° registre', vices:'myxomatose, maladie hémorragique virale (VHD)', sterilM:'5 mois', sterilF:'5 mois' };
    case 'cheval': return { jeune:'poulain',  pedigree:'SIRE n°', vices:'cornage chronique, emphysème pulmonaire, immobilité, stringhalt, mélanose cutanée (pour chevaux gris)', sterilM:'N/A', sterilF:'N/A' };
    case 'ovin':   return { jeune:'agneau',   pedigree:'N° registre', vices:'clavelée, piétin chronique', sterilM:'N/A', sterilF:'N/A' };
    case 'caprin': return { jeune:'chevreau', pedigree:'N° registre', vices:'artérite encéphalite caprine (CAE), brucellose', sterilM:'N/A', sterilF:'N/A' };
    default:       return { jeune:'animal',   pedigree:'N° registre/pedigree', vices:'vices rédhibitoires définis par le code rural', sterilM:'à convenir', sterilF:'à convenir' };
  }
}

const CSS = `
*{box-sizing:border-box}
body{font-family:Arial,sans-serif;font-size:11.5px;margin:0;color:#222;line-height:1.5}
.page{max-width:780px;margin:0 auto;padding:30px 40px}
h1{font-size:18px;text-align:center;margin-bottom:2px;letter-spacing:1px;text-transform:uppercase}
h2{font-size:13px;text-align:center;text-transform:uppercase;letter-spacing:0.5px;margin:24px 0 10px}
.parties{margin:18px 0;line-height:2}
.between{text-align:center;font-style:italic;margin:12px 0}
.art-title{font-weight:bold;margin:18px 0 6px;font-size:12px;text-transform:uppercase}
.block{margin-bottom:10px}
.sign-row{display:flex;gap:60px;margin-top:50px}
.sign-block{flex:1;text-align:center}
.sign-line{border-bottom:1px solid #555;margin-top:50px;margin-bottom:4px}
.foot{margin-top:20px;font-size:9px;color:#aaa;text-align:center}
.cb{display:inline-block;width:12px;height:12px;border:1px solid #444;vertical-align:middle;margin-right:3px;cursor:pointer;background:#fff;text-align:center;line-height:11px;font-size:9px}
.cb.checked{background:#0C5C6C;color:#fff}
.e{border-bottom:1px solid #0C5C6C;min-width:60px;display:inline-block;outline:none;padding:0 3px;color:#0C5C6C;cursor:text}
.e:empty::before{content:attr(data-ph);color:#bbb;font-style:italic}
.e.wide{min-width:200px}
.e.full{min-width:100%;display:block;margin-top:2px}
.no-print{background:#0C5C6C;color:#fff;border:none;padding:8px 20px;border-radius:6px;cursor:pointer;font-size:13px;margin:0 6px}
.toolbar{position:fixed;top:0;left:0;right:0;background:#f0f9ff;border-bottom:2px solid #0C5C6C;padding:8px 20px;display:flex;align-items:center;gap:12px;z-index:999}
.tip{font-size:11px;color:#555}
.page-break{page-break-before:always}
@media print{.toolbar{display:none!important}.e{border-bottom:1px solid #555;color:#222}.page{padding:20px 30px}}
`;

const SCRIPT = `function toggleCb(el){el.classList.toggle('checked');el.textContent=el.classList.contains('checked')?'✓':'';}`;

export function generateContratHTML(animal: AnimalContrat, data: DataContrat, eleveur: EleveurContrat): string {
  const today = new Date().toLocaleDateString('fr-FR');
  const t = animalTerms(animal.espece);
  const isMasculin = ['male','mâle','m'].includes((animal.sexe ?? '').toLowerCase());
  const sterilDelai = isMasculin ? t.sterilM : t.sterilF;
  const acheteurNom = data.nom || '';
  const isGratuit = !data.prix || parseFloat(data.prix) === 0;
  const prixTTC = data.prix ? `${parseFloat(data.prix).toLocaleString('fr-FR')} euros TTC` : '';
  const dn = animal.date_naissance ? new Date(animal.date_naissance).toLocaleDateString('fr-FR') : '';
  const dateVente = data.dateCession ? new Date(data.dateCession).toLocaleDateString('fr-FR') : today;

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Contrat de vente</title>
<style>${CSS}</style>
<script>${SCRIPT}</script>
</head><body>
<div class="toolbar no-print">
  <span class="tip">✏️ Cliquez sur les champs soulignés pour les modifier · Cochez les cases · Puis imprimez</span>
  <button class="no-print" onclick="window.print()">🖨️ Imprimer / Enregistrer en PDF</button>
</div>
<div class="page" style="margin-top:52px">

<h1>Contrat de vente</h1>

<div class="parties">
<strong>ENTRE :</strong><br>
${eleveur.nom}${eleveur.adresse ? `, demeurant ${eleveur.adresse}` : ''}${eleveur.siret ? ` SIRET ${eleveur.siret}` : ''}${eleveur.tel ? `, ${eleveur.tel}` : ''}<br>
<em>Le Vendeur</em>
</div>

<div class="between">ET :</div>

<div class="parties">
<span class="cb" onclick="toggleCb(this)">☐</span> Monsieur &nbsp;&nbsp;
<span class="cb" onclick="toggleCb(this)">☐</span> Madame<br>
Nom : <span class="e wide" contenteditable="true" data-ph="Nom">${acheteurNom ? acheteurNom.split(' ').slice(-1)[0] : ''}</span><br>
Prénom : <span class="e wide" contenteditable="true" data-ph="Prénom">${acheteurNom ? acheteurNom.split(' ').slice(0, -1).join(' ') : ''}</span><br>
Demeurant à : <span class="e wide" contenteditable="true" data-ph="Adresse">${data.adresse || ''}</span><br>
Ville, code postal : <span class="e wide" contenteditable="true" data-ph="Ville, code postal"></span><br>
Téléphone : <span class="e" contenteditable="true" data-ph="Téléphone">${data.tel || ''}</span><br>
Mail : <span class="e wide" contenteditable="true" data-ph="Email">${data.email || ''}</span><br>
<em>L'Acheteur</em>
</div>

<p style="text-align:center;font-style:italic">Désignés séparément comme la « Partie » et collectivement comme les « Parties »</p>
<p style="text-align:center;font-weight:bold">Il a été convenu ce qui suit :</p>

<div class="art-title">Article 1 – Objet de la vente</div>
<div class="block">
Un ${t.jeune} du Nom <span class="e wide" contenteditable="true" data-ph="Nom de l'animal">${animal.nom || ''}</span><br>
De race ou appartenance <span class="e wide" contenteditable="true" data-ph="Race / appartenance">${animal.race || ''}</span><br>
Né le <span class="e" contenteditable="true" data-ph="JJ/MM/AAAA">${dn}</span> à <span class="e" contenteditable="true" data-ph="Lieu de naissance">PLUMIEUX</span><br>
Sexe <span class="e" contenteditable="true" data-ph="M / F">${animal.sexe || ''}</span><br>
Couleur <span class="e wide" contenteditable="true" data-ph="Couleur / robe"></span><br>
Identification transpondeur n° <span class="e wide" contenteditable="true" data-ph="N° puce">${animal.identification || ''}</span><br>
${t.pedigree} <span class="e wide" contenteditable="true" data-ph="N° pedigree"></span><br>
Nom du père <span class="e wide" contenteditable="true" data-ph="Nom du père"></span><br>
De la mère <span class="e wide" contenteditable="true" data-ph="Nom de la mère"></span>
</div>
<div class="block">
L'animal est cédé avec :<br>
<span class="cb" onclick="toggleCb(this)">☐</span> Un certificat de bonne santé<br>
<span class="cb" onclick="toggleCb(this)">☐</span> Un carnet de santé ou passeport<br>
<span class="cb" onclick="toggleCb(this)">☐</span> Un certificat provisoire d'identification<br>
<span class="cb" onclick="toggleCb(this)">☐</span> Certificat d'engagement signé 7 jours avant départ<br>
<span class="cb" onclick="toggleCb(this)">☐</span> Document d'information sur l'accueil d'un ${t.jeune}
</div>

<div class="art-title">Article 2 – Prix de vente – Stérilisation</div>
<div class="block">
Acompte déjà versé : <span class="e" contenteditable="true" data-ph="0">………</span> euros<br>
Tranche 1 (payable au départ effectif de l'animal) : <span class="e" contenteditable="true" data-ph="Montant">${prixTTC}</span><br>
Dont TVA (si assujetti) : <span class="e" contenteditable="true" data-ph="0">………</span> euros<br>
Payé par <span class="cb" onclick="toggleCb(this)">☐</span> virement / <span class="cb" onclick="toggleCb(this)">☐</span> espèce ou <span class="cb" onclick="toggleCb(this)">☐</span> oney bank<br>
Tranche 2 (payable au terme du délai de stérilisation [${sterilDelai}] en cas de non-présentation du certificat de stérilisation par un vétérinaire agréé) : <span class="e" contenteditable="true" data-ph="Montant">2.000 euros</span><br>
La Tranche 2 n'est pas due par l'Acheteur si la stérilisation a été effectuée par le Vendeur avant la livraison effective de l'animal.
</div>

<div class="art-title">Article 3 – Les conditions de la vente</div>
<div class="block">
L'Acheteur s'engage à détenir l'animal dans les conditions compatibles avec ses besoins biologiques et comportementaux et lui donner des soins attentifs conformément aux obligations légales (art. D 214-32-1 du code rural)<br><br>
<strong>Responsabilité de l'Acheteur :</strong> En adoptant un animal, l'Acheteur assume la responsabilité de son bien-être, ce qui inclut les soins quotidiens et les soins vétérinaires nécessaires.<br><br>
Si l'Acheteur souhaite se séparer de l'animal, il s'engage à prévenir le Vendeur prioritairement et dans les plus brefs délais, afin que celui-ci l'aide à trouver une nouvelle famille.<br><br>
<strong>Obligations financières :</strong> Dès le premier jour, l'Acheteur est responsable financièrement de l'animal. Cela comprend les coûts liés à son entretien, sa nourriture, ses soins vétérinaires, et autres besoins.<br><br>
<strong>Proposition d'une assurance santé animale :</strong> Le Vendeur propose une mutuelle partenaire pour aider à couvrir les frais vétérinaires. Cette assurance peut offrir un remboursement en tout ou partie pour certains types de soins vétérinaires.<br><br>
<strong>Absence de prise en charge médicale par le Vendeur :</strong> La prise en charge médicale relève entièrement de la responsabilité de l'Acheteur à compter de la vente.
</div>

<div class="art-title">Article 4 – Le transfert de propriété</div>
<div class="block">
L'Acheteur déclare avoir été informé et accepter que, quel que soit le mode de règlement, le Vendeur conserve la propriété de l'animal objet de la présente jusqu'à ce qu'il ait encaissé la totalité de la somme convenue pour la vente et que cet encaissement conditionne le transfert de propriété. L'Acheteur est informé et accepte que le « volet B » de la carte d'identification de l'animal ne soit adressé par le Vendeur au fichier I-CAD qu'après qu'il ait encaissé la totalité du montant convenu.
</div>

<div class="art-title">Article 5 – Les garanties</div>
<div class="block">
L'Acheteur admet avoir été informé de ce que ne sont garantis que les maladies et défauts définis comme vices rédhibitoires par les articles L. 213-1 à L. 213-9 du code rural (${t.vices}) qui surviendraient dans les conditions, modalités et délais déterminés par les articles R. 213-3 à R. 213-7 du code rural.<br><br>
L'Acheteur bénéficie de l'action en garantie contre les vices rédhibitoires prévue par les articles L.213-1 à L.213-9 du code rural. Cette garantie donne droit à une réduction de prix si l'animal est conservé par l'Acheteur, ou à remboursement intégral contre restitution de l'animal.<br><br>
L'Acheteur ne bénéficie pas de la garantie des vices cachés édictée aux articles 1641 et suivants du code civil. S'estimant apte pour ce faire, l'Acheteur qui a, le jour de la livraison, examiné les caractéristiques de l'animal atteste que celles-ci ne soulèvent de sa part ni réserve, ni objection.<br><br>
L'Acheteur convient que, préalablement à toute action au titre des garanties, son vétérinaire devra se rapprocher de celui du Vendeur et lui communiquer par écrit ses constat et diagnostic. Toute euthanasie ou intervention non motivée par un pronostic vital à laquelle il serait procédé sans accord écrit du Vendeur déchargerait de facto ce dernier de toute obligation de garantie.
</div>

<div class="art-title">Article 6 – Clause de confidentialité</div>
<div class="block">
Toutes les informations, de quelque nature que ce soit, que l'une des Parties a pu recueillir sur l'autre Partie, par écrit ou oralement, sont confidentielles. Chaque Partie s'engage à ne pas divulguer, ni à communiquer à quiconque tout ou partie de ces informations confidentielles.
</div>

<div class="art-title">Article 7 – Droit de rétractation – Non-applicable</div>
<div class="block">
Lorsque la vente s'est réalisée à distance, l'Acheteur reconnaît que l'animal dont il fait l'acquisition entre dans la catégorie visée par l'article L221-28 3° en tant que « biens confectionnés selon les spécifications du consommateur ou nettement personnalisés ».<br>
L'Acheteur reconnaît qu'un ${t.jeune} est un animal de compagnie, être vivant unique et comme tel irremplaçable, et reconnaît qu'il ne pourra invoquer le droit de rétractation issu de l'article L.221-18 du Code de la consommation.
</div>

<div class="art-title">Article 8 – Clause de règlement amiable préalable obligatoire</div>
<div class="block">
En cas de litige, les Parties tenteront d'abord de le résoudre à l'amiable par la saisine de :<br>
Médiateur : <span class="e" contenteditable="true" data-ph="Nom médiateur">SNPPC Yves Legeay</span><br>
Site du médiateur : <span class="e wide" contenteditable="true" data-ph="Site web">https://snpcc.com/</span>
</div>

${data.notes ? `<div class="block"><strong>Conditions particulières :</strong><br><span class="e full" contenteditable="true">${data.notes}</span></div>` : ''}

<div style="margin-top:30px">Le <span class="e" contenteditable="true" data-ph="JJ/MM/AAAA">${dateVente}</span></div>

<div class="sign-row">
  <div class="sign-block">
    <div style="font-size:11px;font-weight:bold">LE VENDEUR</div>
    <div style="font-size:10px;color:#555">${eleveur.nom}</div>
    <div class="sign-line"></div>
    <div style="font-size:9px;color:#aaa">« Lu et approuvé » · Date et signature</div>
  </div>
  <div class="sign-block">
    <div style="font-size:11px;font-weight:bold">L'ACHETEUR</div>
    <div style="font-size:10px;color:#555">${acheteurNom || '...'}</div>
    <div class="sign-line"></div>
    <div style="font-size:9px;color:#aaa">« Lu et approuvé » · Date et signature</div>
  </div>
</div>

<div class="page-break"></div>

<h2>Attestation de cession à titre ${isGratuit ? 'gratuit' : 'onéreux'}</h2>

<div class="parties">
<strong>Entre les soussignés :</strong><br>
Nom : <span class="e" contenteditable="true" data-ph="Nom">${eleveur.nom.split(' ').slice(-1)[0]}</span>
Prénom : <span class="e" contenteditable="true" data-ph="Prénom">${eleveur.nom.split(' ').slice(0, -1).join(' ')}</span><br>
Société : <span class="e wide" contenteditable="true" data-ph="Nom élevage">${eleveur.nom}</span>
SIRET : <span class="e" contenteditable="true" data-ph="SIRET">${eleveur.siret || ''}</span><br>
Adresse : <span class="e wide" contenteditable="true" data-ph="Adresse">${eleveur.adresse || ''}</span><br>
<em>ci-après dénommé « le cessionnaire »</em><br><br>
Et <span class="e wide" contenteditable="true" data-ph="Nom et prénom">${acheteurNom}</span>,
demeurant à <span class="e wide" contenteditable="true" data-ph="Adresse">${data.adresse || ''}</span><br>
<em>ci-après dénommé « le cédant »</em>
</div>

<div class="block"><strong>Concernant l'animal :</strong><br>
Nom : <span class="e wide" contenteditable="true" data-ph="Nom">${animal.nom || ''}</span><br>
Né le : <span class="e" contenteditable="true" data-ph="JJ/MM/AAAA">${dn}</span>, <span class="e" contenteditable="true" data-ph="M/F">${isMasculin ? 'M' : 'F'}</span><br>
Race/Apparence : <span class="e wide" contenteditable="true" data-ph="Race">${animal.race || ''}</span>
Identifié : <span class="e wide" contenteditable="true" data-ph="N° identification">${animal.identification || ''}</span>
</div>

<div class="block">
Le <span class="e" contenteditable="true" data-ph="JJ/MM/AAAA">${dateVente}</span>, le cédant a manifesté sa volonté de céder l'animal à ${eleveur.nom.split(' ')[0]} pour convenances personnelles.<br><br>
<strong>Art 1 – Cession</strong><br>
Les parties conviennent de la cession à titre ${isGratuit ? 'gratuit' : 'onéreux'} de l'animal désigné en préambule${isGratuit ? ' sans contrepartie financière' : ` pour la somme de ${prixTTC}`}.
Sous peine de résolution des présentes, le cédant doit céder l'animal dans un état indemne de lésion, de pathologie, de malformation, de carence, ou de trouble du comportement.<br>
L'animal a été remis au cessionnaire le <span class="e" contenteditable="true" data-ph="JJ/MM/AAAA">${dateVente}</span> à <span class="e" contenteditable="true" data-ph="HH">……</span>h<span class="e" contenteditable="true" data-ph="MM">……</span><br><br>
<strong>Art 2 – Documents remis</strong><br>
Le cédant restitue ou délivre au cessionnaire les documents suivants : Carte I-CAD originale de l'animal signée, carnet de vaccination et/ou passeport, certificat vétérinaire avant cession et, pour un animal de race, document généalogique (certificat de naissance ou pedigree).
</div>

<div style="margin-top:20px">
Fait en double exemplaire à <span class="e" contenteditable="true" data-ph="Ville"></span>, le <span class="e" contenteditable="true" data-ph="JJ/MM/AAAA">${dateVente}</span>
</div>

<div class="sign-row">
  <div class="sign-block">
    <div style="font-size:11px;font-weight:bold">Le cédant</div>
    <div style="font-size:10px;color:#555">${acheteurNom || '...'}</div>
    <div class="sign-line"></div>
    <div style="font-size:9px;color:#aaa">« Lu et approuvé »</div>
  </div>
  <div class="sign-block">
    <div style="font-size:11px;font-weight:bold">Le cessionnaire</div>
    <div style="font-size:10px;color:#555">${eleveur.nom}</div>
    <div class="sign-line"></div>
    <div style="font-size:9px;color:#aaa">« Lu et approuvé »</div>
  </div>
</div>

<p class="foot">Contrat établi en deux exemplaires originaux · ${today} · PetsMatch</p>
</div></body></html>`;
}

// Version vierge depuis la page /elevage/contrat (sans animal ni acheteur spécifique)
export function generateContratVente(eleveur: EleveurContrat): string {
  return generateContratHTML({}, {}, eleveur);
}
