'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { maSignaturePro } from '@/lib/signature-pro';
import { envoyerPiecesParEmail } from '@/lib/transmission-document';
import {
  chargerDocsConsultation, pdfCompteRendu, pdfFacture, pdfOrdonnance, type DocsConsultation,
} from '@/lib/fin-consultation';

const MODES = ['Carte bancaire', 'Espèces', 'Chèque', 'Virement'];

// Fin de consultation : compte(s) rendu(s), ordonnance(s) et facture du RDV
// envoyés au propriétaire en un seul e-mail ; facture marquée acquittée.
// Miroir appli : _terminerConsultation (compte_rendu_page.dart).
export default function FinConsultationModal({ rdvId, proProfileId, clientNom, onClose, onDone }: {
  rdvId: string; proProfileId: string | null; clientNom?: string; onClose: () => void; onDone: () => void;
}) {
  const { user, userData } = useAuth();
  const [docs, setDocs] = useState<DocsConsultation | null>(null);
  const [coches, setCoches] = useState<Record<string, boolean>>({});
  const [acquittee, setAcquittee] = useState(false);
  const [mode, setMode] = useState('Carte bancaire');
  const [envoi, setEnvoi] = useState(false);

  useEffect(() => {
    chargerDocsConsultation(rdvId).then(d => {
      setDocs(d);
      setCoches(Object.fromEntries([...d.crs.map(c => [`cr:${c.id}`, true]), ...d.ordos.map(o => [`ordo:${o.id}`, !!o.doc_url]),
        ...(d.facture ? [[`fac:${d.facture.id}`, true]] : [])]));
    });
  }, [rdvId]);

  const nom = (animalId: string) => docs?.noms[animalId] ?? 'Animal';
  const dejaPayee = docs?.facture?.statut === 'payee';
  const nbCoches = Object.values(coches).filter(Boolean).length;

  async function valider(envoyer: boolean) {
    if (!docs || !user) return;
    setEnvoi(true);
    try {
      let facture = docs.facture;
      if (facture && acquittee && !dejaPayee) {
        const maj = { statut: 'payee', mode_paiement: mode, date_paiement: new Date().toISOString() };
        const { error } = await supabase.from('factures').update(maj).eq('id', facture.id);
        if (error) { alert(`Facture non mise à jour : ${error.message}`); return; }
        facture = { ...facture, ...maj };
      }
      if (envoyer && nbCoches > 0) {
        const signature = await maSignaturePro(user.uid).catch(() => null);
        const praticien = `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim();
        const pieces: { type: 'ordonnance' | 'compte_rendu' | 'facture'; blob: Blob; nomFichier: string }[] = [];
        for (const c of docs.crs) if (coches[`cr:${c.id}`]) {
          pieces.push({ type: 'compte_rendu', nomFichier: `Compte-rendu-${nom(c.animal_id)}.pdf`,
            blob: await pdfCompteRendu(c, { proProfileId, praticien, signature, emailCompte: user.email }) });
        }
        for (const o of docs.ordos) if (coches[`ordo:${o.id}`]) {
          pieces.push({ type: 'ordonnance', nomFichier: `Ordonnance-${nom(o.animal_id)}.pdf`, blob: await pdfOrdonnance(o) });
        }
        if (facture && coches[`fac:${facture.id}`]) {
          pieces.push({ type: 'facture', nomFichier: `Facture-${facture.numero_affichage ?? ''}${facture.statut === 'payee' ? '-acquittee' : ''}.pdf`,
            blob: await pdfFacture(facture) });
        }
        const noms = [...new Set(docs.crs.map(c => nom(c.animal_id)))];
        const ok = await envoyerPiecesParEmail(pieces, {
          emailParDefaut: (facture?.email_client as string | null) ?? null, destinataireNom: clientNom,
          expediteur: userData?.nameElevage || praticien, animalNom: noms.join(', '),
          animalId: docs.animalIdPrincipal ?? docs.crs[0]?.animal_id ?? null,
        });
        if (!ok) return;
      }
      onDone();
    } catch (e) {
      alert(`Impossible : ${(e as Error).message}`);
    } finally { setEnvoi(false); }
  }

  const ligne = (cle: string, titre: string, sous?: string, desactive = false) => (
    <label key={cle} className={`flex items-center gap-3 px-3 py-2 rounded-xl border ${desactive ? 'opacity-50' : 'cursor-pointer'} border-gray-200`}>
      <input type="checkbox" disabled={desactive} checked={!!coches[cle]} onChange={e => setCoches(c => ({ ...c, [cle]: e.target.checked }))}
        className="w-4 h-4" style={{ accentColor: '#0C5C6C' }} />
      <span className="flex-1 min-w-0">
        <span className="block text-sm font-semibold text-[#1E2025]">{titre}</span>
        {sous && <span className="block text-xs text-gray-500">{sous}</span>}
      </span>
    </label>
  );

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-5 space-y-4 max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <h2 className="font-bold text-lg text-[#1E2025]">Fin de consultation</h2>
        {!docs ? <p className="text-sm text-gray-500">Chargement…</p> : (<>
          <div className="space-y-2">
            <p className="text-xs font-semibold text-gray-500">Envoyer au propriétaire par e-mail</p>
            {docs.crs.length === 0 && docs.ordos.length === 0 && !docs.facture && (
              <p className="text-sm text-gray-500">Aucun document pour ce rendez-vous pour l&apos;instant (compte rendu validé, ordonnance ou facture).</p>
            )}
            {docs.crs.map(c => ligne(`cr:${c.id}`, `Compte rendu — ${nom(c.animal_id)}`))}
            {docs.ordos.map(o => ligne(`ordo:${o.id}`, `Ordonnance — ${nom(o.animal_id)}`, o.doc_url ? undefined : 'PDF indisponible', !o.doc_url))}
            {docs.facture && ligne(`fac:${docs.facture.id}`, `Facture ${docs.facture.numero_affichage ?? ''}`,
              `${Number(docs.facture.total_ttc ?? 0).toFixed(2)} € TTC${dejaPayee ? ' — acquittée' : ''}`)}
          </div>
          {docs.facture && !dejaPayee && (
            <div className="space-y-2 rounded-xl bg-[#0C5C6C]/5 px-3 py-2.5">
              <label className="flex items-center gap-3 cursor-pointer">
                <input type="checkbox" checked={acquittee} onChange={e => setAcquittee(e.target.checked)} className="w-4 h-4" style={{ accentColor: '#0C5C6C' }} />
                <span className="text-sm font-semibold text-[#1E2025]">Facture acquittée (réglée aujourd&apos;hui)</span>
              </label>
              {acquittee && (
                <div className="flex flex-wrap gap-1.5">
                  {MODES.map(m => (
                    <button key={m} type="button" onClick={() => setMode(m)}
                      className="px-3 py-1.5 rounded-full text-xs font-semibold border"
                      style={mode === m ? { background: '#0C5C6C', color: 'white', borderColor: '#0C5C6C' } : { color: '#0C5C6C', borderColor: '#0C5C6C' }}>
                      {m}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
          <div className="flex gap-2">
            <button type="button" onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm border border-gray-200 text-gray-600">Fermer</button>
            {acquittee && (
              <button type="button" disabled={envoi} onClick={() => valider(false)}
                className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-[#0C5C6C] text-[#0C5C6C] disabled:opacity-40">
                Acquitter sans envoyer
              </button>
            )}
            <button type="button" disabled={envoi || nbCoches === 0} onClick={() => valider(true)}
              className="flex-[2] py-2.5 rounded-xl text-sm font-semibold text-white bg-[#0C5C6C] disabled:opacity-40">
              {envoi ? '…' : `Envoyer (${nbCoches})`}
            </button>
          </div>
        </>)}
      </div>
    </div>
  );
}
