'use client';
// Photographe — « Fin de séance » (14/11/2026) : un seul e-mail juste après le
// shooting, comme la fin de consultation du vétérinaire — lien de la galerie
// pour vérifier et choisir ses photos, contrat (lien), et le rappel des tarifs
// (forfait = prix minimum, photos incluses, prix d'une photo supplémentaire).
// Pas de facture ni de montant total ici : la facture se fait une fois la
// sélection confirmée. Serveur : /api/photographe/fin-seance.
// Miroir appli : _finSeance (photographe_dossier_seance.dart).
import { useState } from 'react';
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { texteTarifs, type TarifsSeance } from '@/lib/tarifs-photo';

const TEAL = '#0C5C6C';
export interface FinSeanceInfos {
  rdvId: string; statutRdv: string; dateRdv: string; clientNom: string; emailClient: string;
  galerie: { nbPhotos: number } | null;
  contrat: { statut: string } | null;
  tarifs: TarifsSeance;
}

export default function FinSeancePhotoModal({ infos, onClose, onDone }: {
  infos: FinSeanceInfos; onClose: () => void; onDone: (msg: string) => void;
}) {
  const { galerie, contrat } = infos;
  const tarifs = texteTarifs(infos.tarifs);
  const [coches, setCoches] = useState<Record<string, boolean>>({
    ...(galerie && galerie.nbPhotos > 0 ? { gal: true } : {}),
    ...(contrat ? { ctr: true } : {}),
    ...(tarifs ? { tar: true } : {}),
  });
  const [email, setEmail] = useState(infos.emailClient);
  const [message, setMessage] = useState('');
  const [envoi, setEnvoi] = useState('');
  const [erreur, setErreur] = useState('');
  const nb = (coches.gal ? 1 : 0) + (coches.ctr ? 1 : 0);

  async function envoyer() {
    setErreur(''); setEnvoi('Envoi…');
    try {
      const res = await apiFetch('/api/photographe/fin-seance', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rdvId: infos.rdvId, email: email.trim(), message, galerie: !!coches.gal, contrat: !!coches.ctr, tarifs: !!coches.tar }),
      });
      const j = await res.json().catch(() => ({})) as { error?: string };
      if (!res.ok) { setErreur(j.error ?? 'Envoi impossible'); setEnvoi(''); return; }
      if (infos.statutRdv === 'confirme' && new Date(infos.dateRdv) < new Date()
        && confirm('E-mail envoyé au client. Marquer la séance comme terminée ?')) {
        await supabase.from('rdv').update({ statut: 'termine', termine_at: new Date().toISOString() }).eq('id', infos.rdvId);
      }
      onDone(`Envoyé à ${email.trim() || 'l’adresse du client'}.`);
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
        <p className="text-xs text-gray-600 mb-2">Un seul e-mail au client{infos.clientNom ? ` (${infos.clientNom})` : ''} pour vérifier la galerie et choisir ses photos</p>

        {galerie
          ? (galerie.nbPhotos > 0
            ? ligne('gal', 'Galerie', `${galerie.nbPhotos} photo${galerie.nbPhotos > 1 ? 's' : ''} — lien pour vérifier et choisir ses photos`)
            : <p className="text-xs text-gray-500 py-1.5">Galerie sans photo : ajoutez les photos pour pouvoir l&apos;envoyer.</p>)
          : <p className="text-xs text-gray-500 py-1.5">Pas encore de galerie pour cette séance.</p>}
        {contrat && ligne('ctr', 'Contrat de prestation', contrat.statut === 'signe' ? 'Signé — lien pour le consulter' : 'Pas encore signé par le client — lien pour le signer')}
        {tarifs
          ? ligne('tar', 'Rappel des tarifs', tarifs.charAt(0).toUpperCase() + tarifs.slice(1))
          : <p className="text-xs text-gray-500 py-1.5">Tarifs non renseignés : indiquez le prix et le prix par photo supplémentaire dans Mes prestations (ou dans la galerie).</p>}

        <label className="block text-xs text-gray-600 mt-3">E-mail du client
          <input type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="adresse@exemple.fr"
            className="mt-1 w-full h-10 rounded-lg border border-gray-300 px-3 text-sm text-[#1E2025] focus:outline-none focus:border-[#0C5C6C]" />
        </label>
        <label className="block text-xs text-gray-600 mt-2">Message (facultatif)
          <textarea value={message} onChange={e => setMessage(e.target.value)} rows={2}
            className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm text-[#1E2025] focus:outline-none focus:border-[#0C5C6C]" />
        </label>
        <p className="text-[11px] text-gray-400 mt-1">La facture se fera une fois la sélection confirmée, depuis le dossier. La livraison des photos retouchées reste à part.</p>

        {erreur && <p className="text-sm text-red-600 mt-2">{erreur}</p>}
        {envoi && <p className="text-xs text-gray-600 mt-2">{envoi}</p>}
        <div className="flex gap-2 mt-4">
          <button type="button" onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
          <button type="button" onClick={envoyer} disabled={nb === 0 || !!envoi}
            className="flex-[2] py-2.5 rounded-xl text-sm font-bold text-white disabled:opacity-50" style={{ background: TEAL }}>Envoyer</button>
        </div>
      </div>
    </div>
  );
}
