// Contrat de vente numérique — signature électronique simple + stockage Supabase
// TODO YouSign : remplacer les canvas par l'API YouSign pour signature qualifiée (eIDAS)
// Voir supabase/migration_contrats_storage.sql pour le bucket

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
    case 'chien':  return { jeune:'chiot',    pedigree:'LOF ou pedigree FFP n°', vices:'maladie de Carré, de Rubarth, parvovirose, dysplasie coxo-fémorale, atrophie rétinienne, ectopie testiculaire (seulement si cédé âgé de plus de 6 mois)', sterilM:'12 mois à compter de la date de naissance pour un chiot mâle', sterilF:'12 mois à compter de la date de naissance pour un chiot femelle (ou après ses premières chaleurs)' };
    case 'chat':   return { jeune:'chaton',   pedigree:'LOOF n°', vices:'leucopénie et péritonite infectieuses félines, FeLV, FIV', sterilM:'6 mois à compter de la date de naissance', sterilF:'6 mois à compter de la date de naissance (ou après les premières chaleurs)' };
    case 'lapin':  return { jeune:'lapereau', pedigree:'N° registre', vices:'myxomatose, maladie hémorragique virale (VHD)', sterilM:'5 mois', sterilF:'5 mois' };
    case 'cheval': return { jeune:'poulain',  pedigree:'SIRE n°', vices:'cornage chronique, emphysème pulmonaire, immobilité, stringhalt, mélanose cutanée (pour chevaux gris)', sterilM:'N/A', sterilF:'N/A' };
    case 'ovin':   return { jeune:'agneau',   pedigree:'N° registre', vices:'clavelée, piétin chronique', sterilM:'N/A', sterilF:'N/A' };
    case 'caprin': return { jeune:'chevreau', pedigree:'N° registre', vices:'artérite encéphalite caprine (CAE), brucellose', sterilM:'N/A', sterilF:'N/A' };
    default:       return { jeune:'animal',   pedigree:'N° registre/pedigree', vices:'vices rédhibitoires définis par le code rural', sterilM:'à convenir', sterilF:'à convenir' };
  }
}

const CSS = `
*{box-sizing:border-box}
body{font-family:Arial,sans-serif;font-size:11.5px;margin:0;color:#222;line-height:1.6;orphans:4;widows:4}
.page{max-width:780px;margin:0 auto;padding:30px 40px 120px}
h1{font-size:18px;text-align:center;margin-bottom:2px;letter-spacing:1px;text-transform:uppercase;page-break-after:avoid;break-after:avoid}
h2{font-size:13px;text-align:center;text-transform:uppercase;letter-spacing:0.5px;margin:24px 0 10px;page-break-after:avoid;break-after:avoid}
.parties{margin:18px 0;line-height:2;page-break-inside:avoid;break-inside:avoid}
.between{text-align:center;font-style:italic;margin:12px 0}
.article{page-break-inside:avoid;break-inside:avoid;margin-bottom:2px}
.art-title{font-weight:bold;margin:14px 0 4px;font-size:12px;text-transform:uppercase;color:#0C5C6C;page-break-after:avoid;break-after:avoid}
.block{margin-bottom:8px}
.sign-section{page-break-inside:avoid;break-inside:avoid;margin-top:20px}
.sign-row{display:flex;gap:24px}
.sign-block{flex:1;border:1px solid #ddd;border-radius:8px;padding:12px 14px;text-align:center;page-break-inside:avoid;break-inside:avoid}
.sign-label{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:0.5px;color:#0C5C6C;margin-bottom:2px}
.sign-name{font-size:10px;color:#555;margin-bottom:6px}
.sign-img{height:64px;border-bottom:1px solid #888;display:flex;align-items:center;justify-content:center;margin-bottom:4px}
.sign-img img{max-height:60px;max-width:100%;object-fit:contain}
.sign-img:not(:has(img))::after{content:"_________________________";color:#bbb;font-size:11px}
.sign-note{font-size:9px;color:#888}
.copy-banner{border:2px dashed #0C5C6C;border-radius:6px;padding:6px 14px;text-align:center;font-size:10px;color:#0C5C6C;font-weight:bold;margin:14px 0 8px;page-break-inside:avoid;break-inside:avoid}
.foot{margin-top:16px;font-size:9px;color:#aaa;text-align:center;page-break-before:avoid;break-before:avoid}
.cb{display:inline-block;width:12px;height:12px;border:1px solid #444;vertical-align:middle;margin-right:3px;cursor:pointer;background:#fff;text-align:center;line-height:11px;font-size:9px}
.cb.checked{background:#0C5C6C;color:#fff}
.e{border-bottom:1px solid #0C5C6C;min-width:60px;display:inline-block;outline:none;padding:0 3px;color:#0C5C6C;cursor:text}
.e:empty::before{content:attr(data-ph);color:#bbb;font-style:italic}
.e.wide{min-width:200px}
.e.full{min-width:100%;display:block;margin-top:2px}
/* Barre outils + panel signatures */
.toolbar{position:fixed;top:0;left:0;right:0;background:#f0f9ff;border-bottom:2px solid #0C5C6C;padding:8px 20px;display:flex;align-items:center;gap:10px;z-index:999;flex-wrap:wrap}
.sig-panel{position:fixed;bottom:0;left:0;right:0;background:#fff;border-top:2px solid #0C5C6C;padding:12px 24px;z-index:999;display:flex;gap:20px;align-items:center;justify-content:center;flex-wrap:wrap}
.sig-pad{text-align:center}
.sig-pad-label{font-size:10px;font-weight:bold;color:#0C5C6C;margin-bottom:4px}
.sig-canvas{border:1px solid #ccc;border-radius:6px;cursor:crosshair;background:#fafcff;display:block}
.sig-clear{background:none;border:1px solid #ddd;border-radius:4px;padding:2px 10px;font-size:10px;cursor:pointer;color:#888;margin-top:3px}
.btn-primary{background:#0C5C6C;color:#fff;border:none;padding:9px 18px;border-radius:7px;cursor:pointer;font-size:13px;font-weight:bold}
.btn-green{background:#6E9E57;color:#fff;border:none;padding:9px 18px;border-radius:7px;cursor:pointer;font-size:13px;font-weight:bold}
.btn-outline{background:#fff;color:#0C5C6C;border:1.5px solid #0C5C6C;padding:9px 18px;border-radius:7px;cursor:pointer;font-size:12px}
.tip{font-size:10px;color:#555}
.page-break{page-break-before:always;break-before:always}
.status-ok{background:#f0fdf4;color:#166534;border:1px solid #bbf7d0;border-radius:8px;padding:10px 16px;text-align:center;font-size:12px;font-weight:bold;margin:8px 0}
@media print{
  .toolbar,.sig-panel{display:none!important}
  .e{border-bottom:1px solid #555;color:#222}
  .page{padding:20px 30px 30px}
  .sign-block{border:1px solid #aaa}
  body{padding-bottom:0}
}
`;

function buildScript(animalId: string, supabaseUrl: string, supabaseKey: string) {
  return `
var _pads = [];
var _animalId = ${JSON.stringify(animalId)};
var _sbUrl = ${JSON.stringify(supabaseUrl)};
var _sbKey = ${JSON.stringify(supabaseKey)};

window.addEventListener('load', function() {
  if (typeof SignaturePad === 'undefined') return;
  ['sigVendeur','sigAcheteur'].forEach(function(id, i) {
    var c = document.getElementById(id);
    if (c) _pads[i] = new SignaturePad(c, {backgroundColor:'rgba(0,0,0,0)', penColor:'#1F2A2E', minWidth:1, maxWidth:2.5});
  });
});

function toggleCb(el){el.classList.toggle('checked');el.textContent=el.classList.contains('checked')?'✓':'';}

function clearSig(i){ if(_pads[i]) _pads[i].clear(); }

function injectSigs(imgs) {
  ['vendeur','acheteur'].forEach(function(role, i) {
    var sig = imgs[i];
    document.querySelectorAll('[data-signer="'+role+'"] .sign-img').forEach(function(el) {
      el.innerHTML = sig
        ? '<img src="'+sig+'" style="max-height:60px;max-width:100%;object-fit:contain">'
        : '<span style="font-size:9px;color:#aaa;font-style:italic">Signature manuscrite</span>';
    });
  });
}

async function finaliser() {
  if (!_pads[0] || !_pads[1]) { alert('Initialisation incomplète.'); return; }
  var hasSig0 = !_pads[0].isEmpty();
  var hasSig1 = !_pads[1].isEmpty();
  // Permettre d'enregistrer sans signature (ex: imprimer + signer physiquement)
  var imgs = [
    hasSig0 ? _pads[0].toDataURL('image/png') : null,
    hasSig1 ? _pads[1].toDataURL('image/png') : null,
  ];
  injectSigs(imgs);

  // Masquer les éléments non imprimables
  var panel = document.querySelector('.sig-panel');
  var toolbar = document.querySelector('.toolbar');
  if (panel) panel.style.display = 'none';
  if (toolbar) toolbar.style.display = 'none';

  var html = '<!DOCTYPE html>' + document.documentElement.outerHTML;

  // Enregistrer dans Supabase Storage si animalId présent
  if (_animalId && _sbUrl && _sbKey) {
    try {
      var blob = new Blob([html], {type:'text/html;charset=utf-8'});
      var filename = 'contrat_'+_animalId+'_'+Date.now()+'.html';
      var uploadRes = await fetch(_sbUrl+'/storage/v1/object/contrats/'+filename, {
        method: 'POST',
        headers: {'apikey': _sbKey, 'Authorization': 'Bearer '+_sbKey, 'Content-Type': 'text/html;charset=utf-8', 'x-upsert': 'true'},
        body: blob
      });
      if (uploadRes.ok) {
        var publicUrl = _sbUrl+'/storage/v1/object/public/contrats/'+filename;
        // Mettre à jour animaux
        await fetch(_sbUrl+'/rest/v1/animaux?id=eq.'+_animalId, {
          method: 'PATCH',
          headers: {'apikey':_sbKey,'Authorization':'Bearer '+_sbKey,'Content-Type':'application/json','Prefer':'return=minimal'},
          body: JSON.stringify({cession_contrat_url: publicUrl})
        });
        // Notifier le parent
        if (window.opener) window.opener.postMessage({type:'contract_signed', url: publicUrl, animalId: _animalId}, '*');
        // Afficher statut
        var st = document.getElementById('sign-status');
        if (st) { st.textContent = '✅ Contrat signé et enregistré — accessible aux deux parties'; st.style.display='block'; }
      }
    } catch(e) { console.error('Upload contrat:', e); }
  } else {
    if (window.opener) window.opener.postMessage({type:'contract_signed', html: html}, '*');
  }

  // Réafficher la barre pour impression
  if (toolbar) toolbar.style.display = '';
  var pb = document.getElementById('print-btn');
  if (pb) pb.style.display = 'inline-block';
}

function imprimerFinalise() { window.print(); }
`;
}

function buildScriptCert(animalId: string, supabaseUrl: string, supabaseKey: string, eleveurUid: string) {
  return `
var _pads = [];
var _animalId = ${JSON.stringify(animalId)};
var _sbUrl = ${JSON.stringify(supabaseUrl)};
var _sbKey = ${JSON.stringify(supabaseKey)};
var _eleveurUid = ${JSON.stringify(eleveurUid)};

window.addEventListener('load', function() {
  if (typeof SignaturePad === 'undefined') return;
  ['sigVendeur','sigAcheteur'].forEach(function(id, i) {
    var c = document.getElementById(id);
    if (c) _pads[i] = new SignaturePad(c, {backgroundColor:'rgba(0,0,0,0)', penColor:'#1F2A2E', minWidth:1, maxWidth:2.5});
  });
});

function toggleCb(el){el.classList.toggle('checked');el.textContent=el.classList.contains('checked')?'✓':'';}
function clearSig(i){ if(_pads[i]) _pads[i].clear(); }

function injectSigs(imgs) {
  ['vendeur','acheteur'].forEach(function(role, i) {
    var sig = imgs[i];
    document.querySelectorAll('[data-signer="'+role+'"] .sign-img').forEach(function(el) {
      el.innerHTML = sig
        ? '<img src="'+sig+'" style="max-height:60px;max-width:100%;object-fit:contain">'
        : '<span style="font-size:9px;color:#aaa;font-style:italic">Signature manuscrite</span>';
    });
  });
}

async function finaliser() {
  if (!_pads[0] || !_pads[1]) { alert('Initialisation incomplète.'); return; }
  var imgs = [
    !_pads[0].isEmpty() ? _pads[0].toDataURL('image/png') : null,
    !_pads[1].isEmpty() ? _pads[1].toDataURL('image/png') : null,
  ];
  injectSigs(imgs);
  var panel = document.querySelector('.sig-panel');
  var toolbar = document.querySelector('.toolbar');
  if (panel) panel.style.display = 'none';
  if (toolbar) toolbar.style.display = 'none';
  var html = '<!DOCTYPE html>' + document.documentElement.outerHTML;

  if (_animalId && _sbUrl && _sbKey) {
    try {
      var blob = new Blob([html], {type:'text/html;charset=utf-8'});
      var filename = 'certificat_cession_'+_animalId+'_'+Date.now()+'.html';
      var uploadRes = await fetch(_sbUrl+'/storage/v1/object/contrats/'+filename, {
        method: 'POST',
        headers: {'apikey':_sbKey,'Authorization':'Bearer '+_sbKey,'Content-Type':'text/html;charset=utf-8','x-upsert':'true'},
        body: blob
      });
      if (uploadRes.ok) {
        var publicUrl = _sbUrl+'/storage/v1/object/public/contrats/'+filename;
        // Màj cession_certificat_url sur l'animal
        await fetch(_sbUrl+'/rest/v1/animaux?id=eq.'+_animalId, {
          method: 'PATCH',
          headers: {'apikey':_sbKey,'Authorization':'Bearer '+_sbKey,'Content-Type':'application/json','Prefer':'return=minimal'},
          body: JSON.stringify({cession_certificat_url: publicUrl})
        });
        // Insérer dans documents_animaux
        await fetch(_sbUrl+'/rest/v1/documents_animaux', {
          method: 'POST',
          headers: {'apikey':_sbKey,'Authorization':'Bearer '+_sbKey,'Content-Type':'application/json','Prefer':'return=minimal'},
          body: JSON.stringify({animal_id:_animalId, uid_eleveur:_eleveurUid, type:'certificat_cession', titre:'Certificat de cession', url:publicUrl, statut:'signe', signe_le: new Date().toISOString()})
        });
        // Notifier le parent
        if (window.opener) window.opener.postMessage({type:'certificate_signed', url: publicUrl, animalId: _animalId}, '*');
        var st = document.getElementById('sign-status');
        if (st) { st.textContent = '✅ Certificat signé et enregistré'; st.style.display='block'; }
      }
    } catch(e) { console.error('Upload certificat:', e); }
  } else {
    if (window.opener) window.opener.postMessage({type:'certificate_signed', html: html}, '*');
  }

  if (toolbar) toolbar.style.display = '';
  var pb = document.getElementById('print-btn');
  if (pb) pb.style.display = 'inline-block';
}

function imprimerFinalise() { window.print(); }
`;
}

function signBlock(role: 'vendeur' | 'acheteur', nom: string) {
  return `
<div class="sign-block" data-signer="${role}">
  <div class="sign-label">${role === 'vendeur' ? 'Le Vendeur' : "L'Acheteur"}</div>
  <div class="sign-name">${nom || '…'}</div>
  <div class="sign-img"></div>
  <div class="sign-note">« Lu et approuvé »</div>
  <div style="margin-top:6px;font-size:9px"><span class="cb" onclick="toggleCb(this)">☐</span> J'ai reçu mon exemplaire original</div>
</div>`;
}

export function generateContratHTML(
  animal: AnimalContrat,
  data: DataContrat,
  eleveur: EleveurContrat,
  opts?: { animalId?: string; supabaseUrl?: string; supabaseKey?: string }
): string {
  const today = new Date().toLocaleDateString('fr-FR');
  const t = animalTerms(animal.espece);
  const isMasculin = ['male','mâle','m'].includes((animal.sexe ?? '').toLowerCase());
  const sterilDelai = isMasculin ? t.sterilM : t.sterilF;
  const acheteurNom = data.nom || '';
  const isGratuit = !data.prix || parseFloat(data.prix) === 0;
  const prixTTC = data.prix ? `${parseFloat(data.prix).toLocaleString('fr-FR')} euros TTC` : '';
  const dn = animal.date_naissance ? new Date(animal.date_naissance).toLocaleDateString('fr-FR') : '';
  const dateVente = data.dateCession ? new Date(data.dateCession).toLocaleDateString('fr-FR') : today;
  const animalId = opts?.animalId ?? '';
  const sbUrl = opts?.supabaseUrl ?? '';
  const sbKey = opts?.supabaseKey ?? '';
  const hasSign = !!animalId;

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Contrat de vente — ${animal.nom || 'animal'}</title>
<script src="https://cdn.jsdelivr.net/npm/signature_pad@4.1.7/dist/signature_pad.umd.min.js"><\/script>
<style>${CSS}</style>
<script>${buildScript(animalId, sbUrl, sbKey)}<\/script>
</head><body>

<!-- Barre d'outils -->
<div class="toolbar">
  <span class="tip">✏️ Modifiez les champs soulignés · Signez dans le panneau en bas · Finalisez</span>
  <button class="btn-outline" onclick="window.print()">🖨️ Imprimer</button>
  ${hasSign ? `<button class="btn-green" onclick="finaliser()">✅ Finaliser et enregistrer</button>` : `<button class="btn-outline" onclick="window.print()">🖨️ Imprimer x2</button>`}
  <button id="print-btn" class="btn-primary" onclick="imprimerFinalise()" style="display:none">🖨️ Imprimer le contrat signé</button>
</div>

<div class="page" style="margin-top:56px">

<div id="sign-status" class="status-ok" style="display:none"></div>

<h1>Contrat de vente</h1>

<div class="parties">
<strong>ENTRE :</strong><br>
${eleveur.nom}${eleveur.adresse ? `, demeurant ${eleveur.adresse}` : ''}${eleveur.siret ? ` — SIRET ${eleveur.siret}` : ''}${eleveur.tel ? ` — ${eleveur.tel}` : ''}<br>
<em>Le Vendeur</em>
</div>
<div class="between">ET :</div>
<div class="parties">
<span class="cb" onclick="toggleCb(this)">☐</span> M. &nbsp; <span class="cb" onclick="toggleCb(this)">☐</span> Mme<br>
Nom : <span class="e wide" contenteditable="true" data-ph="Nom">${acheteurNom ? acheteurNom.split(' ').slice(-1)[0] : ''}</span> &nbsp;
Prénom : <span class="e wide" contenteditable="true" data-ph="Prénom">${acheteurNom ? acheteurNom.split(' ').slice(0,-1).join(' ') : ''}</span><br>
Adresse : <span class="e wide" contenteditable="true" data-ph="Adresse">${data.adresse || ''}</span><br>
Tél : <span class="e" contenteditable="true" data-ph="Téléphone">${data.tel || ''}</span> &nbsp;
Mail : <span class="e wide" contenteditable="true" data-ph="Email">${data.email || ''}</span><br>
<em>L'Acheteur</em>
</div>

<p style="text-align:center;font-style:italic;margin:8px 0">Il a été convenu ce qui suit :</p>

<div class="article">
<div class="art-title">Article 1 – Objet de la vente</div>
<div class="block">
Un ${t.jeune} du Nom <span class="e wide" contenteditable="true" data-ph="Nom">${animal.nom || ''}</span>
De race <span class="e wide" contenteditable="true" data-ph="Race">${animal.race || ''}</span><br>
Né le <span class="e" contenteditable="true" data-ph="JJ/MM/AAAA">${dn}</span> à <span class="e" contenteditable="true" data-ph="Lieu">PLUMIEUX</span> &nbsp;
Sexe <span class="e" contenteditable="true" data-ph="M/F">${animal.sexe || ''}</span> &nbsp;
Couleur <span class="e wide" contenteditable="true" data-ph="Couleur/robe"></span><br>
Puce n° <span class="e wide" contenteditable="true" data-ph="N° identification">${animal.identification || ''}</span><br>
${t.pedigree} <span class="e wide" contenteditable="true" data-ph="N° pedigree"></span><br>
Père <span class="e wide" contenteditable="true" data-ph="Nom du père"></span> &nbsp; Mère <span class="e wide" contenteditable="true" data-ph="Nom de la mère"></span><br>
Documents remis :
<span class="cb" onclick="toggleCb(this)">☐</span> Certificat de bonne santé &nbsp;
<span class="cb" onclick="toggleCb(this)">☐</span> Carnet/passeport &nbsp;
<span class="cb" onclick="toggleCb(this)">☐</span> Certificat d'identification &nbsp;
<span class="cb" onclick="toggleCb(this)">☐</span> Certificat d'engagement &nbsp;
<span class="cb" onclick="toggleCb(this)">☐</span> Document d'accueil
</div>
</div>

<div class="article">
<div class="art-title">Article 2 – Prix de vente – Stérilisation</div>
<div class="block">
Acompte versé : <span class="e" contenteditable="true" data-ph="0">………</span> € &nbsp;
Tranche 1 (au départ) : <span class="e wide" contenteditable="true" data-ph="Montant">${prixTTC}</span><br>
TVA (si assujetti) : <span class="e" contenteditable="true" data-ph="0">………</span> € &nbsp;
Paiement : <span class="cb" onclick="toggleCb(this)">☐</span> virement <span class="cb" onclick="toggleCb(this)">☐</span> espèces <span class="cb" onclick="toggleCb(this)">☐</span> Oney<br>
Tranche 2 (si non-présentation certificat stérilisation sous ${sterilDelai}) : <span class="e" contenteditable="true" data-ph="Montant">2 000</span> €<br>
La Tranche 2 n'est pas due si la stérilisation a été effectuée par le Vendeur avant la livraison.
</div>
</div>

<div class="article">
<div class="art-title">Article 3 – Conditions de la vente</div>
<div class="block">
L'Acheteur s'engage à détenir l'animal dans des conditions compatibles avec ses besoins biologiques et comportementaux. Il assume la responsabilité de son bien-être, de son entretien et de ses soins vétérinaires dès le premier jour. Si l'Acheteur souhaite se séparer de l'animal, il s'engage à prévenir le Vendeur prioritairement.
</div>
</div>

<div class="article">
<div class="art-title">Article 4 – Transfert de propriété</div>
<div class="block">
Le Vendeur conserve la propriété de l'animal jusqu'à encaissement complet du prix convenu. Le volet B de la carte I-CAD ne sera transmis qu'après paiement intégral.
</div>
</div>

<div class="article">
<div class="art-title">Article 5 – Garanties</div>
<div class="block">
Sont garantis les vices rédhibitoires (art. L.213-1 à L.213-9 du code rural) : ${t.vices}. L'Acheteur ne bénéficie pas de la garantie des vices cachés (art. 1641 c.civ.). Toute euthanasie ou intervention sans accord écrit du Vendeur décharge ce dernier de toute obligation de garantie.
</div>
</div>

<div class="article">
<div class="art-title">Article 6 – Confidentialité</div>
<div class="block">Toutes les informations échangées sont confidentielles et ne peuvent être utilisées à d'autres fins que l'exécution du présent contrat.</div>
</div>

<div class="article">
<div class="art-title">Article 7 – Droit de rétractation (non applicable)</div>
<div class="block">
L'Acheteur reconnaît qu'un ${t.jeune} est un être vivant unique et irremplaçable. Le droit de rétractation (art. L.221-18 C. conso.) ne s'applique pas.
</div>
</div>

<div class="article">
<div class="art-title">Article 8 – Règlement amiable</div>
<div class="block">
En cas de litige, les Parties saisissent prioritairement le médiateur SNPPC
(<span class="e" contenteditable="true" data-ph="Nom médiateur">Yves Legeay</span> — <span class="e wide" contenteditable="true" data-ph="Site">https://snpcc.com/</span>).
</div>
</div>

${data.notes ? `<div class="article"><div class="art-title">Conditions particulières</div><div class="block"><span class="e full" contenteditable="true">${data.notes}</span></div></div>` : ''}

<div style="margin-top:12px">Fait à <span class="e wide" contenteditable="true" data-ph="Ville"></span>, le <span class="e" contenteditable="true" data-ph="JJ/MM/AAAA">${dateVente}</span></div>

<div class="sign-section">
  <div class="copy-banner">📄 Contrat établi en DEUX exemplaires originaux — un pour chaque partie</div>
  <div class="sign-row">
    ${signBlock('vendeur', eleveur.nom)}
    ${signBlock('acheteur', acheteurNom)}
  </div>
</div>

<div class="page-break"></div>

<!-- ── ATTESTATION DE CESSION ────────────────────────────────────── -->
<h2>Attestation de cession à titre ${isGratuit ? 'gratuit' : 'onéreux'}</h2>

<div class="parties">
<strong>Entre les soussignés :</strong><br>
<span class="e" contenteditable="true" data-ph="Nom">${eleveur.nom.split(' ').slice(-1)[0]}</span>
<span class="e wide" contenteditable="true" data-ph="Prénom">${eleveur.nom.split(' ').slice(0,-1).join(' ')}</span> —
Société : <span class="e wide" contenteditable="true" data-ph="Élevage">${eleveur.nom}</span>
SIRET : <span class="e" contenteditable="true" data-ph="SIRET">${eleveur.siret || ''}</span><br>
Adresse : <span class="e wide" contenteditable="true" data-ph="Adresse">${eleveur.adresse || ''}</span><br>
<em>ci-après « le cessionnaire »</em><br><br>
Et <span class="e wide" contenteditable="true" data-ph="Nom et prénom acheteur">${acheteurNom}</span>,
demeurant <span class="e wide" contenteditable="true" data-ph="Adresse">${data.adresse || ''}</span><br>
<em>ci-après « le cédant »</em>
</div>

<div class="article">
<div class="block"><strong>Animal concerné :</strong><br>
Nom : <span class="e wide" contenteditable="true" data-ph="Nom">${animal.nom || ''}</span> &nbsp;
Né le : <span class="e" contenteditable="true" data-ph="JJ/MM/AAAA">${dn}</span> &nbsp;
${isMasculin ? 'M' : 'F'} &nbsp;
Race : <span class="e wide" contenteditable="true" data-ph="Race">${animal.race || ''}</span><br>
Identifié : <span class="e wide" contenteditable="true" data-ph="N° puce">${animal.identification || ''}</span>
</div>
</div>

<div class="article">
<div class="art-title">Art. 1 – Cession</div>
<div class="block">
Les parties conviennent de la cession à titre ${isGratuit ? 'gratuit' : 'onéreux'} de l'animal${isGratuit ? ' sans contrepartie financière' : ` pour ${prixTTC}`}.
L'animal a été remis le <span class="e" contenteditable="true" data-ph="JJ/MM/AAAA">${dateVente}</span> à <span class="e" contenteditable="true" data-ph="HH">……</span>h<span class="e" contenteditable="true" data-ph="MM">……</span>
</div>
</div>

<div class="article">
<div class="art-title">Art. 2 – Documents remis</div>
<div class="block">Carte I-CAD originale signée, carnet de vaccination/passeport, certificat vétérinaire avant cession${animal.race ? `, document généalogique (${t.pedigree})` : ''}.</div>
</div>

<div style="margin-top:12px">Fait à <span class="e wide" contenteditable="true" data-ph="Ville"></span>, le <span class="e" contenteditable="true" data-ph="JJ/MM/AAAA">${dateVente}</span></div>

<div class="sign-section">
  <div class="copy-banner">📄 Attestation établie en DEUX exemplaires originaux — un pour chaque partie</div>
  <div class="sign-row">
    ${signBlock('acheteur', acheteurNom)}
    ${signBlock('vendeur', eleveur.nom)}
  </div>
</div>

<p class="foot">Document établi en deux exemplaires originaux · ${today} · PetsMatch</p>
</div>

${hasSign ? `
<!-- Panneau de signature numérique (masqué à l'impression) -->
<div class="sig-panel">
  <div class="sig-pad">
    <div class="sig-pad-label">✍️ Vendeur — ${eleveur.nom}</div>
    <canvas id="sigVendeur" class="sig-canvas" width="220" height="80"></canvas>
    <button class="sig-clear" onclick="clearSig(0)">✕ Effacer</button>
  </div>
  <div class="sig-pad">
    <div class="sig-pad-label">✍️ Acheteur — ${acheteurNom || '…'}</div>
    <canvas id="sigAcheteur" class="sig-canvas" width="220" height="80"></canvas>
    <button class="sig-clear" onclick="clearSig(1)">✕ Effacer</button>
  </div>
  <div style="text-align:center">
    <button class="btn-green" onclick="finaliser()">✅ Finaliser et enregistrer</button>
    <div style="font-size:9px;color:#888;margin-top:4px">Les signatures sont intégrées au document<br>et sauvegardées pour les deux parties</div>
  </div>
</div>
` : ''}

</body></html>`;
}

export function generateContratVente(eleveur: EleveurContrat): string {
  return generateContratHTML({}, {}, eleveur);
}

// ── Certificat de cession ─────────────────────────────────────────────────────

export function generateCertificatCessionHTML(
  animal: AnimalContrat,
  data: DataContrat,
  eleveur: EleveurContrat,
  opts?: { animalId?: string; supabaseUrl?: string; supabaseKey?: string; eleveurUid?: string }
): string {
  const t = animalTerms(animal.espece);
  const today = new Date().toLocaleDateString('fr-FR');
  const dn = animal.date_naissance ? new Date(animal.date_naissance).toLocaleDateString('fr-FR') : '';
  const dateVente = data.dateCession ? new Date(data.dateCession).toLocaleDateString('fr-FR') : today;
  const acqNom = data.nom ?? '';
  const espece = animal.espece ? (animal.espece.charAt(0).toUpperCase() + animal.espece.slice(1)) : '—';
  const animalId = opts?.animalId ?? '';
  const sbUrl    = opts?.supabaseUrl ?? '';
  const sbKey    = opts?.supabaseKey ?? '';
  const elvUid   = opts?.eleveurUid ?? '';
  const hasSign  = !!animalId;
  const isMasculin = ['male','mâle','m'].includes((animal.sexe ?? '').toLowerCase());
  const vicesSpec = t.vices;

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Certificat de cession — ${animal.nom || t.jeune}</title>
<script src="https://cdn.jsdelivr.net/npm/signature_pad@4.1.7/dist/signature_pad.umd.min.js"><\/script>
<style>${CSS}</style>
<script>${buildScriptCert(animalId, sbUrl, sbKey, elvUid)}<\/script>
</head><body>

<div class="toolbar">
  <span class="tip">✏️ Modifiez les champs soulignés · Signez dans le panneau en bas · Finalisez</span>
  <button class="btn-outline" onclick="window.print()">🖨️ Imprimer</button>
  ${hasSign ? `<button class="btn-green" onclick="finaliser()">✅ Finaliser et enregistrer</button>` : ''}
  <button id="print-btn" class="btn-primary" onclick="imprimerFinalise()" style="display:none">🖨️ Imprimer le certificat signé</button>
</div>

<div class="page" style="margin-top:56px">

<div id="sign-status" class="status-ok" style="display:none"></div>

<h1>Certificat de cession</h1>
<h2 style="font-size:11px;color:#555;text-align:center;margin-top:0">Établi conformément aux dispositions des articles L214-8 et suivants du Code rural</h2>

<div class="parties">
<strong>ENTRE :</strong><br>
<strong>Vendeur / Cédant</strong><br>
${eleveur.nom}${eleveur.adresse ? `, ${eleveur.adresse}` : ''}${eleveur.siret ? ` — SIRET ${eleveur.siret}` : ''}${eleveur.tel ? ` — Tél. ${eleveur.tel}` : ''}${eleveur.email ? ` — ${eleveur.email}` : ''}
</div>

<div class="between">ET :</div>

<div class="parties">
<strong>Acquéreur</strong><br>
<span class="cb" onclick="toggleCb(this)">☐</span> M. &nbsp; <span class="cb" onclick="toggleCb(this)">☐</span> Mme<br>
Nom / Prénom : <span class="e wide" contenteditable="true" data-ph="Nom et prénom">${acqNom}</span><br>
Adresse : <span class="e full" contenteditable="true" data-ph="Adresse complète">${data.adresse ?? ''}</span>
Email : <span class="e wide" contenteditable="true" data-ph="Email">${data.email ?? ''}</span> &nbsp;
Téléphone : <span class="e wide" contenteditable="true" data-ph="Téléphone">${data.tel ?? ''}</span>
</div>

<div class="article">
<div class="art-title">Article 1 — Animal cédé</div>
<div class="block">
Espèce : <span class="e wide" contenteditable="true" data-ph="Espèce">${espece}</span> &nbsp;
Race : <span class="e wide" contenteditable="true" data-ph="Race">${animal.race ?? ''}</span><br>
Sexe : <span class="cb" onclick="toggleCb(this)">${isMasculin ? '✓' : '☐'}</span> Mâle &nbsp; <span class="cb" onclick="toggleCb(this)">${!isMasculin ? '✓' : '☐'}</span> Femelle<br>
Nom de l'animal : <span class="e wide" contenteditable="true" data-ph="Nom">${animal.nom ?? ''}</span><br>
Date de naissance : <span class="e wide" contenteditable="true" data-ph="jj/mm/aaaa">${dn}</span><br>
N° d'identification (puce / tatouage) : <span class="e wide" contenteditable="true" data-ph="N° identification">${animal.identification ?? ''}</span><br>
${animal.espece?.toLowerCase() === 'chien' || animal.espece?.toLowerCase() === 'chat'
  ? `Numéro de pedigree : <span class="e full" contenteditable="true" data-ph="${t.pedigree}"></span>`
  : ''}
</div>
</div>

<div class="article">
<div class="art-title">Article 2 — Conditions de cession</div>
<div class="block">
Date effective de cession : <span class="e wide" contenteditable="true" data-ph="jj/mm/aaaa">${dateVente}</span><br>
Prix de cession : <span class="e wide" contenteditable="true" data-ph="Montant en euros">${data.prix ? `${parseFloat(data.prix).toLocaleString('fr-FR')} euros TTC` : ''}</span><br>
Mode de règlement : <span class="cb" onclick="toggleCb(this)">☐</span> Virement &nbsp;
<span class="cb" onclick="toggleCb(this)">☐</span> Espèces &nbsp;
<span class="cb" onclick="toggleCb(this)">☐</span> Chèque<br>
${data.notes ? `Conditions particulières : <span class="e full" contenteditable="true">${data.notes}</span>` : 'Conditions particulières : <span class="e full" contenteditable="true" data-ph="Conditions particulières éventuelles"></span>'}
</div>
</div>

<div class="article">
<div class="art-title">Article 3 — Garanties légales</div>
<div class="block">
Le cédant certifie que l'animal est, à sa connaissance, en bonne santé au jour de la cession et a bénéficié de l'ensemble des soins nécessaires à son bon développement (vaccinations, vermifugations, antiparasitaires).<br><br>
Conformément à l'article L213-1 du Code rural, la présente cession est soumise aux garanties légales contre les vices rédhibitoires suivants : <span class="e full" contenteditable="true">${vicesSpec}</span><br><br>
Le délai de garantie légale est de <span class="e" contenteditable="true" data-ph="30">30</span> jours à compter de la livraison pour les vices rédhibitoires.<br><br>
L'acquéreur déclare avoir reçu les informations nécessaires concernant les besoins spécifiques, l'entretien et le mode de vie adapté à cette espèce/race.
</div>
</div>

<div class="article">
<div class="art-title">Article 4 — Documents remis</div>
<div class="block">
<span class="cb" onclick="toggleCb(this)">☐</span> Carnet de santé / passeport européen<br>
<span class="cb" onclick="toggleCb(this)">☐</span> Certificat vétérinaire de moins de 5 jours<br>
<span class="cb" onclick="toggleCb(this)">☐</span> Attestation de cession (présent document)<br>
<span class="cb" onclick="toggleCb(this)">☐</span> Pedigree / document de filiation<br>
<span class="cb" onclick="toggleCb(this)">☐</span> Certificat d'engagement et de connaissance<br>
<span class="cb" onclick="toggleCb(this)">☐</span> Contrat de vente / réservation
</div>
</div>

<div class="sign-section">
  <div class="block" style="text-align:right;margin-bottom:8px">
    Fait à <span class="e" contenteditable="true" data-ph="Ville">___________</span>, le <span class="e" contenteditable="true" data-ph="date">${today}</span>
  </div>
  <div class="copy-banner">📄 Attestation établie en DEUX exemplaires originaux — un pour chaque partie</div>
  <div class="sign-row">
    ${signBlock('vendeur', eleveur.nom)}
    ${signBlock('acheteur', acqNom || "L'Acquéreur")}
  </div>
</div>

<p class="foot">Certificat de cession établi le ${today} · PetsMatch — Ce document ne remplace pas les obligations légales d'identification et de déclaration auprès du fichier national d'identification (I-CAD).</p>
</div>

${hasSign ? `
<div class="sig-panel">
  <div class="sig-pad">
    <div class="sig-pad-label">✍️ Vendeur — ${eleveur.nom}</div>
    <canvas id="sigVendeur" class="sig-canvas" width="220" height="80"></canvas>
    <button class="sig-clear" onclick="clearSig(0)">✕ Effacer</button>
  </div>
  <div class="sig-pad">
    <div class="sig-pad-label">✍️ Acquéreur — ${acqNom || '…'}</div>
    <canvas id="sigAcheteur" class="sig-canvas" width="220" height="80"></canvas>
    <button class="sig-clear" onclick="clearSig(1)">✕ Effacer</button>
  </div>
  <div style="text-align:center">
    <button class="btn-green" onclick="finaliser()">✅ Finaliser et enregistrer</button>
    <div style="font-size:9px;color:#888;margin-top:4px">Signatures intégrées · document sauvegardé pour les deux parties</div>
  </div>
</div>
` : ''}

</body></html>`;
}

// ── Contrat de réservation ────────────────────────────────────────────────────

export function generateContratReservationHTML(
  animal: AnimalContrat,
  data: DataContrat & { acompte?: string; tranche1?: string; nomPere?: string; nomMere?: string },
  eleveur: EleveurContrat,
  opts?: { animalId?: string; supabaseUrl?: string; supabaseKey?: string }
): string {
  const t = animalTerms(animal.espece);
  const isMasculin = ['male','mâle','m'].includes((animal.sexe ?? '').toLowerCase());
  const sterilDelaiM = 6; // mois stérilisation mâle
  const sterilDelaiF = 8; // mois stérilisation femelle (selon template)
  const jeune = t.jeune;
  const today = new Date().toLocaleDateString('fr-FR');
  const dn = animal.date_naissance ? new Date(animal.date_naissance).toLocaleDateString('fr-FR') : '';
  const acqNom    = data.nom ?? '';
  const prix      = data.prix ? `${parseFloat(data.prix).toLocaleString('fr-FR')} euros` : '';
  const acompte   = data.acompte ? `${parseFloat(data.acompte).toLocaleString('fr-FR')} euros` : '';
  const tranche1  = data.tranche1 ? `${parseFloat(data.tranche1).toLocaleString('fr-FR')} euros` : '';
  const animalId  = opts?.animalId ?? '';
  const sbUrl     = opts?.supabaseUrl ?? '';
  const sbKey     = opts?.supabaseKey ?? '';
  const hasSign   = !!animalId;

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Contrat de réservation — ${animal.nom || jeune}</title>
<script src="https://cdn.jsdelivr.net/npm/signature_pad@4.1.7/dist/signature_pad.umd.min.js"><\/script>
<style>${CSS}</style>
<script>${buildScript(animalId, sbUrl, sbKey)}<\/script>
</head><body>

<div class="toolbar">
  <span class="tip">✏️ Modifiez les champs soulignés · Signez dans le panneau en bas · Finalisez</span>
  <button class="btn-outline" onclick="window.print()">🖨️ Imprimer</button>
  ${hasSign ? `<button class="btn-green" onclick="finaliser()">✅ Finaliser et enregistrer</button>` : ''}
  <button id="print-btn" class="btn-primary" onclick="imprimerFinalise()" style="display:none">🖨️ Imprimer le contrat signé</button>
</div>

<div class="page" style="margin-top:56px">

<div id="sign-status" class="status-ok" style="display:none"></div>

<h1>Contrat de réservation</h1>

<div class="parties">
<strong>ENTRE :</strong><br>
${eleveur.nom}${eleveur.adresse ? `, demeurant ${eleveur.adresse}` : ''}${eleveur.siret ? `, SIRET ${eleveur.siret}` : ''}${eleveur.tel ? `, ${eleveur.tel}` : ''}<br>
<em>Le Vendeur</em>
</div>

<div class="between">ET :</div>

<div class="parties">
<span class="cb" onclick="toggleCb(this)">☐</span> Monsieur &nbsp; <span class="cb" onclick="toggleCb(this)">☐</span> Madame<br>
Nom : <span class="e wide" contenteditable="true" data-ph="Nom">${acqNom ? acqNom.split(' ').slice(-1)[0] : ''}</span> &nbsp;
Prénom : <span class="e wide" contenteditable="true" data-ph="Prénom">${acqNom ? acqNom.split(' ').slice(0,-1).join(' ') : ''}</span><br>
Demeurant à : <span class="e full" contenteditable="true" data-ph="Adresse">${data.adresse ?? ''}</span>
Ville, code postal : <span class="e wide" contenteditable="true" data-ph="Ville, code postal"></span><br>
Téléphone : <span class="e wide" contenteditable="true" data-ph="Téléphone">${data.tel ?? ''}</span> &nbsp;
Mail : <span class="e wide" contenteditable="true" data-ph="Email">${data.email ?? ''}</span>
</div>

<p class="between" style="font-style:italic">Désignés séparément comme la « Partie »<br>et collectivement comme les « Parties »</p>
<p class="between">Il a été convenu ce qui suit :</p>

<div class="article">
<div class="art-title">Article 1 – Objet du contrat</div>
<div class="block">
Le Futur Acheteur réserve auprès du Vendeur, pour en devenir le futur propriétaire, le ${jeune} désigné :<br>
Nom : <span class="e wide" contenteditable="true" data-ph="Nom de l'animal">${animal.nom ?? ''}</span><br>
Né le : <span class="e wide" contenteditable="true" data-ph="Date de naissance">${dn}</span><br>
Père : <span class="e full" contenteditable="true" data-ph="Nom du père">${data.nomPere ?? ''}</span>
Mère : <span class="e full" contenteditable="true" data-ph="Nom de la mère">${data.nomMere ?? ''}</span>
${animal.identification ? `Puce / Tatouage : <span class="e wide" contenteditable="true">${animal.identification}</span><br>` : ''}
${animal.race ? `Race : <span class="e wide" contenteditable="true">${animal.race}</span><br>` : ''}
</div>
</div>

<div class="article">
<div class="art-title">Article 2 – Réservation</div>
<div class="block">
Le présent contrat de réservation devient valide une fois complété, signé et retourné au Vendeur et accompagné du règlement de l'acompte à hauteur de <span class="e wide" contenteditable="true" data-ph="montant acompte">${acompte}</span>, qui viendra en déduction du prix final.
</div>
</div>

<div class="article">
<div class="art-title">Article 3 – Paiement</div>
<div class="block">
L'acompte sera versé par le Futur Acheteur par <span class="cb" onclick="toggleCb(this)">☐</span> VIREMENT ou <span class="cb" onclick="toggleCb(this)">☐</span> ESPÈCES.<br>
Le solde du paiement total du ${jeune} sera réceptionné comme décrit à l'article 6.
</div>
</div>

<div class="article">
<div class="art-title">Article 4 – Annulation</div>
<div class="block">
En cas d'annulation du contrat de réservation par le Futur Acheteur avant la signature du contrat de vente final, l'acompte ne sera en aucun cas restitué.<br><br>
${eleveur.nom} peut se prévaloir de mettre fin à une réservation dans un ou plusieurs des cas suivants : (i) problème de santé du ${jeune} découvert après le jour de la réservation, (ii) décès du ${jeune}, (iii) découverte d'une difficulté liée aux futures conditions d'accueil du ${jeune} qui pourrait mettre en péril sa santé ou son équilibre.<br><br>
Dans ces cas-là, ${eleveur.nom} procèdera, au choix du Futur Acheteur, soit au remboursement total de l'acompte, soit proposera un autre ${jeune} suivant disponibilité.
</div>
</div>

<div class="article">
<div class="art-title">Article 4bis – Information</div>
<div class="block">
${eleveur.nom} s'engage à donner au Futur Acheteur des nouvelles régulières du ${jeune} tout au long du sevrage.
</div>
</div>

<div class="article">
<div class="art-title">Article 5 – Contrat de vente</div>
<div class="block">
Le Vendeur et le Futur Acheteur finaliseront la vente par la signature du contrat définitif de vente de l'animal, au maximum à ses <span class="e" contenteditable="true" data-ph="10">10</span> semaines sans quoi des frais de gardiennage seront facturés et la vente pourra être annulée au-delà des <span class="e" contenteditable="true" data-ph="12">12</span> semaines du ${jeune} si celui-ci n'a pas été récupéré par sa famille. Dans ce cas, aucun acompte ne sera restitué.
</div>
</div>

<div class="article">
<div class="art-title">Article 6 – Prix – Stérilisation</div>
<div class="block">
Le prix du ${jeune} est fixé à <span class="e wide" contenteditable="true" data-ph="prix total">${prix}</span>. Le prix est décomposé comme suit :<br><br>
— Acompte : <span class="e wide" contenteditable="true" data-ph="montant acompte">${acompte}</span><br>
— Tranche 1 (payable au départ effectif du ${jeune}) : <span class="e wide" contenteditable="true" data-ph="montant tranche 1">${tranche1}</span><br>
— Tranche 2 (payable au terme du délai de stérilisation
[<span class="e" contenteditable="true">${isMasculin ? sterilDelaiM : sterilDelaiF}</span> mois à compter de la date de naissance pour un ${jeune} ${isMasculin ? 'mâle' : 'femelle'}] en cas de non-présentation du certificat de stérilisation par un vétérinaire agréé) : <span class="e wide" contenteditable="true" data-ph="montant tranche 2">2.000 euros</span><br><br>
La Tranche 2 n'est pas due par l'Acheteur si la stérilisation a été effectuée par le Vendeur avant la livraison effective de l'animal.
</div>
</div>

<div class="article">
<div class="block" style="font-size:10px;color:#555;margin-top:16px;border-top:1px solid #eee;padding-top:12px">
Les signataires conviennent expressément de signer électroniquement le présent acte par le biais du service <strong>PetsMatch Signature</strong>, conformément aux termes des articles 1316-4, 1366, 1367 et 1375 du Code civil, les signataires s'accordant pour reconnaître à cette signature électronique la même valeur que celle de sa signature manuscrite.
</div>
</div>

<div class="sign-section">
  <div class="block" style="text-align:right;margin-bottom:8px">
    Le <span class="e" contenteditable="true" data-ph="date">${today}</span>
  </div>
  <div class="copy-banner">📄 Contrat établi en DEUX exemplaires originaux — un pour chaque partie</div>
  <div class="sign-row">
    ${signBlock('vendeur', eleveur.nom)}
    ${signBlock('acheteur', acqNom || 'L\'Acheteur')}
  </div>
</div>

<p class="foot">Document établi en deux exemplaires originaux · ${today} · PetsMatch</p>
</div>

${hasSign ? `
<div class="sig-panel">
  <div class="sig-pad">
    <div class="sig-pad-label">✍️ Vendeur — ${eleveur.nom}</div>
    <canvas id="sigVendeur" class="sig-canvas" width="220" height="80"></canvas>
    <button class="sig-clear" onclick="clearSig(0)">✕ Effacer</button>
  </div>
  <div class="sig-pad">
    <div class="sig-pad-label">✍️ Acheteur — ${acqNom || '…'}</div>
    <canvas id="sigAcheteur" class="sig-canvas" width="220" height="80"></canvas>
    <button class="sig-clear" onclick="clearSig(1)">✕ Effacer</button>
  </div>
  <div style="text-align:center">
    <button class="btn-green" onclick="finaliser()">✅ Finaliser et enregistrer</button>
    <div style="font-size:9px;color:#888;margin-top:4px">Signatures intégrées au document et sauvegardées</div>
  </div>
</div>
` : ''}

</body></html>`;
}
