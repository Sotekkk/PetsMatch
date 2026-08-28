// Rendu HTML d'une facture de pension — partagé entre le modal de facturation
// et la page « Mes factures » (pour rouvrir une facture déjà émise).

const TEAL = '#0C5C6C';

export interface PensionFactureData {
  numero: string;
  pensionNom: string;
  emiseLe?: string | null; // ISO ; défaut = aujourd'hui
  animal: { nom?: string | null; espece?: string | null; race?: string | null; puce?: string | null };
  proprietaire: { nom?: string | null; email?: string | null; contact?: string | null };
  sejour: { dateEntree?: string | null; dateSortie?: string | null };
  nuits: number;
  tarifNuit: number;
  suppDesc?: string | null;
  suppMontant?: number | null;
  avecTVA: boolean;
  isAcompte: boolean;
  acomptePct?: number | null;
}

const ESP: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau', cheval: 'Cheval',
  nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin', porcin: 'Porc', ane: 'Âne',
};
const espLabel = (e?: string | null) => ESP[e ?? ''] ?? (e ?? '');
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

  return `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><title>${d.isAcompte ? "Facture d'acompte" : 'Facture'} ${d.numero}</title>
<style>body{font-family:Arial,sans-serif;font-size:12px;margin:24px;color:#222}h1{font-size:18px;margin-bottom:2px}.meta{color:#666;font-size:11px;margin-bottom:20px}
.grid{display:flex;gap:24px;margin-bottom:16px}.box{flex:1;background:#f8f8f6;border-radius:6px;padding:10px 12px}.box b{display:block;font-size:9px;letter-spacing:.5px;color:#888;margin-bottom:4px}
table{width:100%;border-collapse:collapse;margin-bottom:12px}th{background:#f0f0f0;font-weight:bold;text-align:left;padding:6px 8px;border:1px solid #ccc}td{padding:6px 8px;border:1px solid #ddd}
.totals{margin-left:auto;width:260px}.totals div{display:flex;justify-content:space-between;padding:3px 0}.totals .grand{font-weight:bold;font-size:14px;border-top:1px solid #ccc;padding-top:6px;color:${TEAL}}
.foot{margin-top:28px;font-size:10px;color:#999}@media print{body{margin:10px}}</style>
</head><body>
<h1>🧾 ${d.isAcompte ? `Facture d'acompte ${d.numero}` : `Facture ${d.numero}`}</h1>
<p class="meta">${d.pensionNom} — émise le ${emise}${d.isAcompte ? ` · acompte de ${pct}% du séjour` : ''}</p>
<div class="grid">
  <div class="box"><b>ANIMAL</b>${d.animal.nom ?? '—'}${d.animal.espece ? ` · ${espLabel(d.animal.espece)}` : ''}${d.animal.race ? `<br>${d.animal.race}` : ''}${d.animal.puce ? `<br>Puce : ${d.animal.puce}` : ''}</div>
  <div class="box"><b>PROPRIÉTAIRE</b>${d.proprietaire.nom ?? '—'}${d.proprietaire.email ? `<br>${d.proprietaire.email}` : ''}${d.proprietaire.contact ? `<br>${d.proprietaire.contact}` : ''}</div>
  <div class="box"><b>SÉJOUR</b>Entrée : ${fmtD(d.sejour.dateEntree)}<br>Sortie : ${fmtD(d.sejour.dateSortie)}<br><b style="color:${TEAL}">${nuits} nuit${nuits > 1 ? 's' : ''}</b></div>
</div>
<table><thead><tr><th>Description</th><th>Qté</th><th>P.U. HT</th><th>Total HT</th></tr></thead><tbody>
<tr><td>Pension du ${fmtD(d.sejour.dateEntree)} au ${fmtD(d.sejour.dateSortie)}</td><td>${nuits}</td><td>${eur(tarif)}</td><td>${eur(tarif * nuits)}</td></tr>
${supp > 0 ? `<tr><td>${d.suppDesc || 'Suppléments'}</td><td>1</td><td>${eur(supp)}</td><td>${eur(supp)}</td></tr>` : ''}
</tbody></table>
<div class="totals">
${d.avecTVA ? `<div><span>Sous-total HT</span><span>${eur(sousTotal)}</span></div><div><span>TVA 20%</span><span>${eur(tva)}</span></div>` : ''}
<div${d.isAcompte ? '' : ' class="grand"'}><span>${d.avecTVA ? 'TOTAL TTC séjour' : 'TOTAL séjour'}</span><span>${eur(total)}</span></div>
${d.isAcompte ? `<div><span>Acompte ${pct}%</span><span>${eur(montant)}</span></div>
<div class="grand"><span>À RÉGLER MAINTENANT</span><span>${eur(montant)}</span></div>
<div><span>Solde à la sortie</span><span>${eur(total - montant)}</span></div>` : ''}
</div>
<p class="foot">${d.isAcompte ? `Acompte à régler pour confirmer la réservation. Le solde de ${eur(total - montant)} sera facturé à la fin du séjour. ` : 'Paiement à réception de facture. '}Document généré via PetsMatch.</p>
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
