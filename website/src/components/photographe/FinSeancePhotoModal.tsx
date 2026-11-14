'use client';
// Photographe — « Fin de séance : tout envoyer au client » (14/11/2026), comme
// la fin de consultation du vétérinaire / la fin de garde : un seul e-mail
// après le shooting — lien de la galerie pour choisir ses photos, facture
// (PDF, acquittée au besoin), contrat et devis (liens). La livraison des
// photos retouchées reste un envoi à part. Serveur : /api/photographe/fin-seance.
// Miroir appli : finSeancePhoto (photographe_dossier_seance.dart).
import { useState } from 'react';
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { pdfFacture, type FactureConsultation } from '@/lib/fin-consultation';

const TEAL = '#0C5C6C';
const MODES = ['Carte bancaire', 'Espèces', 'Chèque', 'Virement'];
const eur = (v: unknown) => `${(Number(v) || 0).toFixed(2).replace('.', ',')} €`;

async function enBase64(blob: Blob): Promise<string> {
  const buf = new Uint8Array(await blob.arrayBuffer());
  let bin = '';
  for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return btoa(bin);
}

export interface FinSeanceInfos {
  rdvId: string; statutRdv: string; dateRdv: string; clientNom: string; emailClient: string;
  galerie: { nbPhotos: number } | null;
  facture: { id: string; statut: string; total_ttc: number | null; numero_affichage?: string | null; numero_facture?: string | null } | null;
  contrat: { statut: string } | null;
  devis: { statut: string; total_ttc: number | null } | null;
}

export default function FinSeancePhotoModal({ infos, onClose, onPreparerFacture, onDone }: {
  infos: FinSeanceInfos; onClose: () => void; onPreparerFacture: () => void; onDone: (msg: string) => void;
}) {
  const { galerie, facture, contrat, devis } = infos;
  const [coches, setCoches] = useState<Record<string, boolean>>({
    ...(galerie && galerie.nbPhotos > 0 ? { gal: true } : {}),
    ...(facture ? { fac: true } : {}),
    ...(contrat ? { ctr: contrat.statut !== 'signe' } : {}),
    ...(devis ? { dev: devis.statut === 'brouillon' || devis.statut === 'envoye' } : {}),
  });
  const [email, setEmail] = useState(infos.emailClient);
  const [message, setMessage] = useState('');
  const [acquittee, setAcquittee] = useState(false);
  const [mode, setMode] = useState(MODES[0]);
  const [envoi, setEnvoi] = useState('');
  const [erreur, setErreur] = useState('');
  const dejaPayee = facture?.statut === 'payee';
  const nb = Object.values(coches).filter(Boolean).length;

  async function envoyer() {
    setErreur(''); setEnvoi('Préparation…');
    try {
      let pieceFacture: { fichier_nom: string; pdf_base64: string } | null = null;
      if (facture && coches.fac) {
        if (acquittee && !dejaPayee) {
          const { error } = await supabase.from('factures')
            .update({ statut: 'payee', mode_paiement: mode, date_paiement: new Date().toISOString() }).eq('id', facture.id);
          if (error) { setErreur(`Facture non mise à jour : ${error.message}`); setEnvoi(''); return; }
        }
        const { data: f } = await supabase.from('factures').select('*').eq('id', facture.id).maybeSingle();
        if (f) {
          const fc = f as FactureConsultation;
          const n = fc.numero_affichage ?? (fc as { numero_facture?: string | number | null }).numero_facture ?? '';
          pieceFacture = { fichier_nom: `Facture-${n}${fc.statut === 'payee' ? '-acquittee' : ''}.pdf`, pdf_base64: await enBase64(await pdfFacture(fc)) };
        }
      }
      setEnvoi('Envoi…');
      const res = await apiFetch('/api/photographe/fin-seance', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rdvId: infos.rdvId, email: email.trim(), message, galerie: !!coches.gal, contrat: !!coches.ctr, devis: !!coches.dev, facture: pieceFacture }),
      });
      const j = await res.json().catch(() => ({})) as { error?: string };
      if (!res.ok) { setErreur(j.error ?? 'Envoi impossible'); setEnvoi(''); return; }
      if (infos.statutRdv === 'confirme' && new Date(infos.dateRdv) < new Date()
        && confirm('Tout est envoyé au client. Marquer la séance comme terminée ?')) {
        await supabase.from('rdv').update({ statut: 'termine', termine_at: new Date().toISOString() }).eq('id', infos.rdvId);
      }
      onDone(`Envoyé à ${email.trim() || 'l’adresse du client'} en un seul e-mail.`);
    } catch (e) {
      setErreur(e instanceof Error ? e.message : String(e)); setEnvoi('');
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
        <h2 className="font-extrabold text-lg" style={{ color: TEAL }}>Fin de séance</h2>
        <p className="text-xs text-gray-600 mb-2">Tout envoyer au client en un seul e-mail{infos.clientNom ? ` (${infos.clientNom})` : ''}</p>

        {galerie
          ? (galerie.nbPhotos > 0
            ? ligne('gal', 'Galerie', `${galerie.nbPhotos} photo${galerie.nbPhotos > 1 ? 's' : ''} — lien pour choisir ses photos`)
            : <p className="text-xs text-gray-500 py-1.5">Galerie sans photo : ajoutez les photos pour pouvoir l&apos;envoyer.</p>)
          : <p className="text-xs text-gray-500 py-1.5">Pas encore de galerie pour cette séance.</p>}
        {facture ? ligne('fac', `Facture ${facture.numero_affichage ?? facture.numero_facture ?? ''}`, `${eur(facture.total_ttc)} TTC${dejaPayee ? ' — acquittée' : ''} · PDF joint`) : (
          <button type="button" onClick={() => { onClose(); onPreparerFacture(); }}
            className="w-full my-1 py-2 rounded-xl text-sm font-semibold border" style={{ borderColor: TEAL, color: TEAL }}>Préparer la facture</button>
        )}
        {contrat && ligne('ctr', 'Contrat de prestation', contrat.statut === 'signe' ? 'Signé — lien pour le consulter' : 'Pas encore signé par le client — lien pour le signer')}
        {devis && ligne('dev', `Devis — ${eur(devis.total_ttc)} TTC`, devis.statut === 'accepte' ? 'Accepté — lien pour le consulter' : 'Lien pour le consulter et l’accepter')}

        {facture && coches.fac && !dejaPayee && (
          <div className="mt-2">
            <label className="flex items-center gap-2 text-sm font-semibold">
              <input type="checkbox" checked={acquittee} onChange={e => setAcquittee(e.target.checked)} /> Facture acquittée (réglée aujourd&apos;hui)
            </label>
            {acquittee && (
              <div className="flex flex-wrap gap-1.5 mt-1.5">
                {MODES.map(m => (
                  <button key={m} type="button" onClick={() => setMode(m)} className="px-2.5 py-1 rounded-full text-xs font-semibold"
                    style={mode === m ? { background: `${TEAL}26`, color: TEAL } : { background: '#F1F4F3', color: '#1F2A2E' }}>{m}</button>
                ))}
              </div>
            )}
          </div>
        )}

        <label className="block text-xs text-gray-600 mt-3">E-mail du client
          <input type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="adresse@exemple.fr"
            className="mt-1 w-full h-10 rounded-lg border border-gray-300 px-3 text-sm text-[#1E2025] focus:outline-none focus:border-[#0C5C6C]" />
        </label>
        <label className="block text-xs text-gray-600 mt-2">Message (facultatif)
          <textarea value={message} onChange={e => setMessage(e.target.value)} rows={2}
            className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm text-[#1E2025] focus:outline-none focus:border-[#0C5C6C]" />
        </label>
        <p className="text-[11px] text-gray-400 mt-1">La livraison des photos retouchées se fera plus tard, à part.</p>

        {erreur && <p className="text-sm text-red-600 mt-2">{erreur}</p>}
        {envoi && <p className="text-xs text-gray-600 mt-2">{envoi}</p>}
        <div className="flex gap-2 mt-4">
          <button type="button" onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
          <button type="button" onClick={envoyer} disabled={nb === 0 || !!envoi}
            className="flex-[2] py-2.5 rounded-xl text-sm font-bold text-white disabled:opacity-50" style={{ background: TEAL }}>Envoyer ({nb})</button>
        </div>
      </div>
    </div>
  );
}
