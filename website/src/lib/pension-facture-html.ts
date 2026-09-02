// Rendu HTML d'une facture de pension — partagé entre le modal de facturation
// et la page « Mes factures » (pour rouvrir une facture déjà émise).

const TEAL = '#0C5C6C';
const ESCOMPTE_DEFAUT = 'Escompte pour paiement anticipé : néant.';

export interface PensionFactureEmetteur {
  nom?: string | null;
  adresse?: string | null;         // « rue, CP ville, pays »
  siret?: string | null;
  tva?: string | null;             // n° TVA intracommunautaire
  tel?: string | null;
  email?: string | null;
  formeJuridique?: string | null;  // EI, EURL, SAS, association…
  capital?: string | null;
  rcs?: string | null;
}

export interface PensionFactureData {
  numero: string;
  pensionNom: string;
  emetteur?: PensionFactureEmetteur | null;
  emiseLe?: string | null; // ISO ; défaut = aujourd'hui
  echeance?: string | null;
  animal: { nom?: string | null; espece?: string | null; race?: string | null; puce?: string | null };
  proprietaire: { nom?: string | null; email?: string | null; contact?: string | null; adresse?: string | null };
  sejour: { dateEntree?: string | null; dateSortie?: string | null };
  nuits: number;
  tarifNuit: number;
  suppDesc?: string | null;
  suppMontant?: number | null;
  avecTVA: boolean;
  isAcompte: boolean;
  acomptePct?: number | null;
  escompte?: string | null;
}

const ESP: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau', cheval: 'Cheval',
  nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin', porcin: 'Porc', ane: 'Âne',
};
const esc = (s?: string | null) => String(s ?? '').replace(/[&<>"']/g, c =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string));
const espLabel = (e?: string | null) => ESP[e ?? ''] ?? esc(e ?? '');
const fmtD = (iso?: string | null) => {
  if (!iso) return '—';
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso; }
};
const eur = (v: number) => `${v.toFixed(2).replace('.', ',')} €`;

export function pensionInvoiceHtml(d: PensionFactureData): string {
  const nuits = Math.max(1, Math.round(d.nuits || 1));
  const tarif = d.tarifNuit || 0;
  const supp = d.suppMontant || 0;
  const sousTotal = tarif * nuits + supp;
  const tva = d.avecTVA ? sousTotal * 0.2 : 0;
  const total = sousTotal + tva;
  const pct = Math.min(100, Math.max(1, Math.round(d.acomptePct || 30)));
  const montant = d.isAcompte ? Math.round(total * pct) / 100 : total;
  const emise = d.emiseLe ? fmtD(d.emiseLe) : new Date().toLocaleDateString('fr-FR');
  const annee = new Date().getFullYear();
  const em = d.emetteur ?? {};
  const escompte = (d.escompte ?? '').trim() || ESCOMPTE_DEFAUT;

  const emetteurLines = [
    em.formeJuridique ? `${esc(em.formeJuridique)}${em.capital ? ` — capital ${esc(em.capital)}` : ''}` : '',
    em.adresse ? esc(em.adresse) : '',
    em.tel ? `Tél. : ${esc(em.tel)}` : '',
    em.email ? esc(em.email) : '',
    em.siret ? `SIRET : ${esc(em.siret)}` : '',
    em.tva ? `N° TVA : ${esc(em.tva)}` : '',
    em.rcs ? esc(em.rcs) : '',
  ].filter(Boolean).join('<br>');

  return `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><title>${d.isAcompte ? "Facture d'acompte" : 'Facture'} ${esc(d.numero)}</title>
<style>body{font-family:Arial,sans-serif;font-size:12px;margin:24px;color:#222;line-height:1.5}h1{font-size:18px;margin-bottom:2px;color:${TEAL}}.meta{color:#666;font-size:11px;margin-bottom:18px}
.grid{display:flex;gap:24px;margin-bottom:16px}.box{flex:1;background:#f8f8f6;border-radius:6px;padding:10px 12px}.box b{display:block;font-size:9px;letter-spacing:.5px;color:#888;margin-bottom:4px}
table{width:100%;border-collapse:collapse;margin-bottom:12px}th{background:#f0f0f0;font-weight:bold;text-align:left;padding:6px 8px;border:1px solid #ccc}td{padding:6px 8px;border:1px solid #ddd}
.totals{margin-left:auto;width:260px}.totals div{display:flex;justify-content:space-between;padding:3px 0}.totals .grand{font-weight:bold;font-size:14px;border-top:1px solid #ccc;padding-top:6px;color:${TEAL}}
.pay{background:#f8f8f6;border-radius:6px;padding:10px 12px;font-size:11px;color:#555;margin-top:14px}
.mentions{border:1px solid #ccc;border-radius:6px;padding:10px 12px;font-size:10px;color:#555;margin-top:12px}.mentions b{color:#222}
.foot{margin-top:22px;font-size:10px;color:#999}@media print{body{margin:10px}}</style>
</head><body>
<div class="grid" style="align-items:flex-start">
  <div style="flex:1">
    <h1>${esc(em.nom || d.pensionNom)}</h1>
    <p class="meta">${emetteurLines || 'Coordonnées de facturation à compléter dans votre profil.'}</p>
  </div>
  <div style="text-align:right">
    <div style="font-size:16px;font-weight:bold;color:${TEAL}">${d.isAcompte ? "FACTURE D'ACOMPTE" : 'FACTURE'}</div>
    <div style="font-weight:bold">N° ${esc(d.numero)}</div>
    <div class="meta">Émise le ${emise}${d.echeance ? `<br>Échéance : ${fmtD(d.echeance)}` : ''}${d.isAcompte ? `<br>acompte de ${pct}% du séjour` : ''}</div>
  </div>
</div>
<div class="grid">
  <div class="box"><b>ANIMAL</b>${esc(d.animal.nom) || '—'}${d.animal.espece ? ` · ${espLabel(d.animal.espece)}` : ''}${d.animal.race ? `<br>${esc(d.animal.race)}` : ''}${d.animal.puce ? `<br>Puce : ${esc(d.animal.puce)}` : ''}</div>
  <div class="box"><b>CLIENT</b>${esc(d.proprietaire.nom) || '—'}${d.proprietaire.adresse ? `<br>${esc(d.proprietaire.adresse)}` : ''}${d.proprietaire.email ? `<br>${esc(d.proprietaire.email)}` : ''}${d.proprietaire.contact ? `<br>${esc(d.proprietaire.contact)}` : ''}</div>
  <div class="box"><b>SÉJOUR</b>Entrée : ${fmtD(d.sejour.dateEntree)}<br>Sortie : ${fmtD(d.sejour.dateSortie)}<br><b style="color:${TEAL}">${nuits} nuit${nuits > 1 ? 's' : ''}</b></div>
</div>
<table><thead><tr><th>Désignation</th><th>Qté</th><th>P.U. HT</th><th>Total HT</th></tr></thead><tbody>
<tr><td>Pension pour animal — du ${fmtD(d.sejour.dateEntree)} au ${fmtD(d.sejour.dateSortie)}</td><td>${nuits}</td><td>${eur(tarif)}</td><td>${eur(tarif * nuits)}</td></tr>
${supp > 0 ? `<tr><td>${esc(d.suppDesc) || 'Suppléments'}</td><td>1</td><td>${eur(supp)}</td><td>${eur(supp)}</td></tr>` : ''}
</tbody></table>
<div class="totals">
${d.avecTVA ? `<div><span>Sous-total HT</span><span>${eur(sousTotal)}</span></div><div><span>TVA 20%</span><span>${eur(tva)}</span></div>` : ''}
<div${d.isAcompte ? '' : ' class="grand"'}><span>${d.avecTVA ? 'TOTAL TTC séjour' : 'TOTAL séjour'}</span><span>${eur(total)}</span></div>
${d.isAcompte ? `<div><span>Acompte ${pct}%</span><span>${eur(montant)}</span></div>
<div class="grand"><span>À RÉGLER MAINTENANT</span><span>${eur(montant)}</span></div>
<div><span>Solde à la sortie</span><span>${eur(total - montant)}</span></div>` : ''}
</div>
<div class="pay">${d.isAcompte
  ? `Acompte à régler pour confirmer la réservation. Le solde de ${eur(total - montant)} sera facturé à la fin du séjour.`
  : d.echeance ? `Paiement dû au plus tard le ${fmtD(d.echeance)}.` : 'Paiement à réception de facture.'}</div>
<div class="mentions">
${d.avecTVA ? '' : '<b>TVA non applicable, art. 293 B du CGI.</b><br>'}
${esc(escompte)}<br>
En cas de retard de paiement : pénalités au taux de 3 fois le taux d'intérêt légal en vigueur (${annee}), exigibles sans rappel le lendemain de la date d'échéance, et indemnité forfaitaire de recouvrement de 40 € (art. L441-10 et D441-5 du Code de commerce).
</div>
<p class="foot">Facture émise via PetsMatch.</p>
</body></html>`;
}

/** Ouvre la facture dans un nouvel onglet. */
export function openPensionInvoice(d: PensionFactureData) {
  const win = window.open('', '_blank');
  if (!win) return false;
  win.document.write(pensionInvoiceHtml(d));
  win.document.close();
  return true;
}
