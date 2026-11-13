'use client';
// Pet-sitter — « Fin de garde » (13/11/2026), comme la fin de séance du
// comportementaliste / du toiletteur : tout envoyer au client en un seul
// e-mail — compte rendu de la garde (PDF : passages, messages et photos
// compressées), facture (acquittée au besoin), acompte, forfait ; contrat et
// devis : lien de signature / consultation par e-mail. Clients sans compte
// compris (adresse saisie). Miroir appli : lib/pages/pro/garde_fin.dart.
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { lienDocument } from '@/lib/document-prive';
import { pdfFacture, type FactureConsultation } from '@/lib/fin-consultation';
import { envoyerPiecesParEmail } from '@/lib/transmission-document';
import { envoyerContratParEmail } from '@/lib/contrat-email';
import { devisDuRdv, envoyerDevisRdv, type DevisRdv } from '@/lib/devis-rdv';
import { acomptesGarde, rattacherForfaitGarde } from '@/lib/forfait-garde';
import { coordonneesClientRdv } from '@/lib/coordonnees-client-rdv';

const TEAL = '#0C5C6C';
const MAX_PHOTOS = 24;

interface RdvFin {
  id: string; pro_uid: string; client_uid: string; client_profile_id?: string | null; animal_id?: string | null;
  date_heure: string; motif?: string | null; statut?: string; animaux_ids?: unknown[] | null;
}
type Message = { note: string | null; photo_url: string | null; created_at: string; incident?: boolean | null };
type Facture = FactureConsultation & { total_ttc?: number | null; type_facture?: string | null; email_client?: string | null };

const eur = (v: unknown) => `${(Number(v) || 0).toFixed(2).replace('.', ',')} €`;

/** Photo compressée (900 px max, JPEG 55 %) pour le PDF. */
async function photoCompressee(url: string): Promise<{ data: string; w: number; h: number } | null> {
  try {
    const blob = await (await fetch(await lienDocument(url))).blob();
    const img = await createImageBitmap(blob);
    const k = Math.min(1, 900 / Math.max(img.width, img.height));
    const c = document.createElement('canvas');
    c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
    c.getContext('2d')!.drawImage(img, 0, 0, c.width, c.height);
    return { data: c.toDataURL('image/jpeg', 0.55), w: c.width, h: c.height };
  } catch { return null; }
}

async function pdfCompteRenduGarde(o: { proNom: string; clientNom: string; animaux: string; rdvs: RdvFin[]; messages: Message[] }): Promise<Blob> {
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight(), M = 40, L = W - 2 * M;
  let y = 50;
  const nouvellePage = (besoin: number) => { if (y + besoin > H - 50) { doc.addPage(); y = 50; } };
  doc.setFont('helvetica', 'bold'); doc.setFontSize(14); doc.setTextColor(12, 92, 108);
  doc.text(o.proNom || 'Pet-sitter', M, y);
  doc.setFontSize(11); doc.text('COMPTE RENDU DE GARDE', W - M, y, { align: 'right' });
  y += 12; doc.setDrawColor(221, 226, 220); doc.line(M, y, W - M, y); y += 22;
  doc.setTextColor(30, 32, 37); doc.setFontSize(13); doc.text(o.animaux || 'Garde', M, y); y += 15;
  doc.setFont('helvetica', 'normal'); doc.setFontSize(10);
  const dates = o.rdvs.map(r => new Date(r.date_heure)).sort((a, b) => a.getTime() - b.getTime());
  const f = (d: Date) => d.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  if (o.clientNom) { doc.text(`Pour ${o.clientNom}`, M, y); y += 13; }
  if (dates.length) { doc.text(dates.length === 1 ? `Le ${f(dates[0])}` : `Du ${f(dates[0])} au ${f(dates[dates.length - 1])}`, M, y); y += 13; }
  doc.text(`${o.rdvs.length} passage${o.rdvs.length > 1 ? 's' : ''} · ${o.rdvs[0]?.motif ?? 'Prestation'}`, M, y); y += 22;
  if (!o.messages.length) { doc.setTextColor(100); doc.text('Aucun message envoyé pendant la garde.', M, y); }
  let nbPhotos = 0;
  for (const m of o.messages) {
    nouvellePage(40);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(12, 92, 108);
    doc.text(`${new Date(m.created_at).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}${m.incident ? '  —  Incident' : ''}`, M, y); y += 13;
    doc.setFont('helvetica', 'normal'); doc.setFontSize(10); doc.setTextColor(30, 32, 37);
    for (const t of doc.splitTextToSize(m.note?.trim() ?? '', L) as string[]) { nouvellePage(14); doc.text(t, M, y); y += 13; }
    if (m.photo_url && nbPhotos < MAX_PHOTOS) {
      const p = await photoCompressee(m.photo_url);
      if (p) {
        const h = Math.min(260, p.h * (L / p.w)), w = p.w * (h / p.h);
        nouvellePage(h + 8);
        doc.addImage(p.data, 'JPEG', M + (L - w) / 2, y, w, h); y += h + 8; nbPhotos++;
      }
    }
    y += 10; doc.setDrawColor(235); doc.line(M, y - 5, W - M, y - 5);
  }
  if (o.messages.filter(m => m.photo_url).length > nbPhotos) {
    nouvellePage(20); doc.setFontSize(9); doc.setTextColor(100);
    doc.text("Toutes les photos sont visibles dans l'application PetsMatch (fiche de l'animal, onglet Pension & Garde).", M, y);
  }
  return doc.output('blob');
}

export default function FinGardeModal({ rdvs, proProfileId, proNom, clientNom, animalNom, onClose, onPreparerFacture, onChanged }: {
  rdvs: RdvFin[]; proProfileId: string | null; proNom: string; clientNom: string; animalNom: string;
  onClose: () => void; onPreparerFacture: () => void; onChanged?: () => void;
}) {
  const first = rdvs[0];
  const ids = rdvs.map(r => r.id);
  const [charge, setCharge] = useState(false);
  const [facture, setFacture] = useState<Facture | null>(null);
  const [acomptes, setAcomptes] = useState<Facture[]>([]);
  const [factureForfait, setFactureForfait] = useState<Facture | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [contrat, setContrat] = useState<{ token: string | null; statut: string; titre: string | null } | null>(null);
  const [devis, setDevis] = useState<DevisRdv[]>([]);
  const [coches, setCoches] = useState<Record<string, boolean>>({});
  const [acquittee, setAcquittee] = useState(false);
  const [mode, setMode] = useState('Carte bancaire');
  const [envoi, setEnvoi] = useState('');

  useEffect(() => {
    let alive = true;
    (async () => {
      const [fa, pu, ct] = await Promise.all([
        supabase.from('factures').select('*').in('source_rdv_id', ids).neq('statut', 'annulee').order('created_at', { ascending: false }),
        supabase.from('pension_updates').select('note, photo_url, created_at, incident').in('rdv_id', ids).order('created_at'),
        supabase.from('documents_animaux').select('token, statut, titre').eq('uid_eleveur', first.pro_uid).eq('type', 'contrat_garde')
          .eq('metadata->>client_uid', first.client_uid)
          .or(proProfileId ? `pro_profile_id.eq.${proProfileId},pro_profile_id.is.null` : 'pro_profile_id.is.null')
          .order('created_at', { ascending: false }).limit(1).maybeSingle(),
      ]);
      const fac = ((fa.data ?? []) as Facture[]).find(x => x.type_facture !== 'acompte' && x.type_facture !== 'avoir') ?? null;
      // Un même message est posté sur chaque animal gardé : une seule fois ici.
      const vus = new Set<string>();
      const msgs = ((pu.data ?? []) as Message[]).filter(m => {
        const k = `${m.note ?? ''}|${m.photo_url ?? ''}|${m.created_at.slice(0, 16)}`;
        if (vus.has(k)) return false; vus.add(k); return true;
      });
      const lies = await acomptesGarde(ids);
      const acs = lies.length ? ((await supabase.from('factures').select('*').in('id', lies.map(a => a.id))).data ?? []) as Facture[] : [];
      const fg = await rattacherForfaitGarde(ids);
      const ff = fg?.factureId ? ((await supabase.from('factures').select('*').eq('id', fg.factureId).neq('statut', 'annulee').maybeSingle()).data as Facture | null) : null;
      const dv = (await Promise.all(ids.map(id => devisDuRdv(id)))).flat();
      if (!alive) return;
      const c = ct.data as { token: string | null; statut: string; titre: string | null } | null;
      setFacture(fac); setMessages(msgs); setAcomptes(acs); setFactureForfait(ff); setContrat(c); setDevis(dv);
      setCoches({
        cr: true, ...(fac ? { fac: true } : {}),
        ...Object.fromEntries(acs.map(a => [`acp:${a.id}`, false])),
        ...(ff ? { ff: false } : {}),
        ...(c ? { ctr: c.statut !== 'signe' } : {}),
        ...Object.fromEntries(dv.map(d => [`dev:${d.id}`, d.statut === 'brouillon'])),
      });
      setCharge(true);
    })();
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ids.join(',')]);

  const nb = Object.values(coches).filter(Boolean).length;
  const nbPhotos = messages.filter(m => m.photo_url).length;
  const dejaPayee = facture?.statut === 'payee';

  async function envoyer() {
    setEnvoi('Préparation des documents…');
    try {
      let fac = facture;
      if (fac && acquittee && !dejaPayee) {
        const maj = { statut: 'payee', mode_paiement: mode, date_paiement: new Date().toISOString() };
        const { error } = await supabase.from('factures').update(maj).eq('id', fac.id);
        if (error) { alert(`Facture non mise à jour : ${error.message}`); setEnvoi(''); return; }
        fac = { ...fac, ...maj };
      }
      const coord = await coordonneesClientRdv(first.id, first.client_profile_id).catch(() => null);
      const email = coord?.email || (fac?.email_client as string | null) || '';
      const pieces: { type: 'compte_rendu' | 'facture'; blob: Blob; nomFichier: string }[] = [];
      if (coches.cr) pieces.push({ type: 'compte_rendu', nomFichier: `Compte-rendu-garde${animalNom ? `-${animalNom}` : ''}.pdf`,
        blob: await pdfCompteRenduGarde({ proNom, clientNom, animaux: animalNom, rdvs, messages }) });
      const nomFac = (f: Facture, forfait = false) => `Facture-${forfait ? 'forfait-' : ''}${f.numero_affichage ?? ''}${f.statut === 'payee' ? '-acquittee' : ''}.pdf`;
      if (fac && coches.fac) pieces.push({ type: 'facture', nomFichier: nomFac(fac), blob: await pdfFacture(fac) });
      for (const a of acomptes) if (coches[`acp:${a.id}`]) pieces.push({ type: 'facture', nomFichier: nomFac(a), blob: await pdfFacture(a) });
      if (factureForfait && coches.ff) pieces.push({ type: 'facture', nomFichier: nomFac(factureForfait, true), blob: await pdfFacture(factureForfait) });
      setEnvoi('Envoi…');
      const ids0 = (first.animaux_ids ?? []).map(x => String(x ?? '')).filter(Boolean);
      const ok = pieces.length === 0 ? true : await envoyerPiecesParEmail(pieces, {
        emailParDefaut: email || null, destinataireNom: clientNom, expediteur: proNom, animalNom,
        animalId: ids0[0] ?? first.animal_id ?? null, contexte: 'garde',
      });
      if (!ok) { setEnvoi(''); return; }
      if (contrat?.token && coches.ctr) {
        if (!(email && await envoyerContratParEmail({ email, clientNom, proProfileId, token: contrat.token, titre: contrat.titre ?? undefined }))) {
          alert("Contrat : pas d'adresse e-mail pour ce client.");
        }
      }
      for (const d of devis) if (coches[`dev:${d.id}`]) await envoyerDevisRdv(d, { proNom, emailSecours: email || null, uid: first.pro_uid });
      await supabase.from('rdv').update({ documents_envoyes_le: new Date().toISOString() }).in('id', ids);
      const aClore = rdvs.filter(r => r.statut === 'confirme' && new Date(r.date_heure) < new Date()).map(r => r.id);
      if (aClore.length && confirm(`Documents envoyés. Marquer ${aClore.length > 1 ? `les ${aClore.length} passages` : 'la garde'} comme terminé${aClore.length > 1 ? 's' : 'e'} ?`)) {
        await supabase.from('rdv').update({ statut: 'termine', termine_at: new Date().toISOString() }).in('id', aClore);
      }
      onChanged?.();
      onClose();
    } catch (e) {
      alert(`Impossible : ${e instanceof Error ? e.message : String(e)}`);
      setEnvoi('');
    }
  }

  const ligne = (cle: string, titre: string, sous?: string) => (
    <label key={cle} className="flex items-start gap-2 py-1.5 text-sm cursor-pointer">
      <input type="checkbox" className="mt-1" checked={!!coches[cle]} onChange={e => setCoches(c => ({ ...c, [cle]: e.target.checked }))} />
      <span><span className="font-semibold text-[#1E2025]">{titre}</span>{sous && <span className="block text-xs text-gray-500">{sous}</span>}</span>
    </label>
  );

  return (
    <div className="fixed inset-0 z-[60] flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-5 max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <h2 className="font-extrabold text-lg" style={{ color: TEAL }}>Fin de garde</h2>
        <p className="text-xs text-gray-600 mb-2">Tout envoyer au client en un seul e-mail{clientNom ? ` (${clientNom})` : ''}</p>
        {!charge ? <p className="text-sm text-gray-500 py-6">Chargement…</p> : (
          <>
            {ligne('cr', 'Compte rendu de la garde',
              `${rdvs.length} passage${rdvs.length > 1 ? 's' : ''} · ${messages.length} message${messages.length > 1 ? 's' : ''}${nbPhotos ? ` · ${Math.min(nbPhotos, MAX_PHOTOS)} photo${nbPhotos > 1 ? 's' : ''} (compressées)` : ''}`)}
            {facture ? ligne('fac', `Facture ${facture.numero_affichage ?? ''}`, `${eur(facture.total_ttc)} TTC${dejaPayee ? ' — acquittée' : ''}`) : (
              <button type="button" onClick={() => { onClose(); onPreparerFacture(); }}
                className="w-full my-1 py-2 rounded-xl text-sm font-semibold border" style={{ borderColor: TEAL, color: TEAL }}>Préparer la facture</button>
            )}
            {acomptes.map(a => ligne(`acp:${a.id}`, `Facture d'acompte ${a.numero_affichage ?? ''}`, `${eur(a.total_ttc)} TTC${a.statut === 'payee' ? ' — payée' : ''} · déjà envoyée à son émission`))}
            {factureForfait && ligne('ff', `Facture du forfait ${factureForfait.numero_affichage ?? ''}`, `${eur(factureForfait.total_ttc)} TTC · déjà envoyée à son émission`)}
            {contrat && ligne('ctr', 'Contrat de garde', contrat.statut === 'signe' ? 'Signé — lien pour le consulter' : 'Lien pour le signer')}
            {devis.map(d => ligne(`dev:${d.id}`, `Devis — ${eur(d.total_ttc)} TTC`, d.statut === 'brouillon' ? 'Lien pour le signer' : 'Déjà envoyé — renvoyer le lien'))}
            {facture && !dejaPayee && (
              <div className="mt-2">
                <label className="flex items-center gap-2 text-sm font-semibold">
                  <input type="checkbox" checked={acquittee} onChange={e => setAcquittee(e.target.checked)} /> Facture acquittée (réglée aujourd&apos;hui)
                </label>
                {acquittee && (
                  <div className="flex flex-wrap gap-1.5 mt-1.5">
                    {['Carte bancaire', 'Espèces', 'Chèque', 'Virement'].map(m => (
                      <button key={m} type="button" onClick={() => setMode(m)} className="px-2.5 py-1 rounded-full text-xs font-semibold"
                        style={mode === m ? { background: `${TEAL}26`, color: TEAL } : { background: '#F1F4F3', color: '#1F2A2E' }}>{m}</button>
                    ))}
                  </div>
                )}
              </div>
            )}
          </>
        )}
        {envoi && <p className="text-xs text-gray-600 mt-2">{envoi}</p>}
        <div className="flex gap-2 mt-4">
          <button type="button" onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
          <button type="button" onClick={envoyer} disabled={!charge || nb === 0 || !!envoi}
            className="flex-[2] py-2.5 rounded-xl text-sm font-bold text-white disabled:opacity-50" style={{ background: TEAL }}>Envoyer ({nb})</button>
        </div>
      </div>
    </div>
  );
}
