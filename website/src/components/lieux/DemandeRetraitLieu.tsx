'use client';
// « Demander le retrait de ce lieu » : lieu naturel publié, ou lieu
// pet-friendly publié sans gestionnaire. La demande part à l'équipe PetsMatch,
// qui l'accepte ou la refuse (suivi dans Mes contributions).
// Miroir appli : lib/widgets/demande_retrait_lieu.dart.
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

export const RAISONS_RETRAIT: [string, string, ('naturel' | 'petfriendly' | null)][] = [
  ['ferme', 'Le lieu a fermé définitivement', null],
  ['inexistant', 'Ce lieu n’existe pas ou l’adresse est fausse', null],
  ['doublon', 'Doublon d’un autre lieu', null],
  ['animaux_refuses', 'Les animaux n’y sont plus acceptés', 'petfriendly'],
  ['dangereux', 'Lieu dangereux ou interdit d’accès', 'naturel'],
  ['prive', 'Propriété privée', null],
  ['autre', 'Autre raison', null],
];
export const libelleRaisonRetrait = (r: unknown) => RAISONS_RETRAIT.find(([v]) => v === r)?.[1] ?? String(r ?? '');

export default function DemandeRetraitLieu({ nature, placeId, placeNom, className = '' }: {
  nature: 'naturel' | 'petfriendly'; placeId: string; placeNom: string; className?: string;
}) {
  const { user, activeProfileId } = useAuth();
  const colonne = nature === 'naturel' ? 'natural_place_id' : 'petfriendly_place_id';
  const [enAttente, setEnAttente] = useState(false);
  const [ouvert, setOuvert] = useState(false);
  const [raison, setRaison] = useState('');
  const [commentaire, setCommentaire] = useState('');
  const [message, setMessage] = useState('');
  const [envoi, setEnvoi] = useState(false);

  useEffect(() => {
    if (!user) return;
    supabase.from('lieux_demandes_retrait').select('id').eq('uid', user.uid).eq(colonne, placeId)
      .eq('statut', 'en_attente').limit(1)
      .then(({ data }) => setEnAttente((data ?? []).length > 0));
  }, [user, colonne, placeId]);

  const commentaireRequis = raison === 'autre' || raison === 'doublon';
  const valide = !!raison && (!commentaireRequis || !!commentaire.trim());

  async function envoyer() {
    if (!user || !valide) return;
    setEnvoi(true); setMessage('');
    const { error } = await supabase.from('lieux_demandes_retrait').insert({
      nature, [colonne]: placeId, place_nom: placeNom, uid: user.uid,
      ...(activeProfileId ? { profile_id: activeProfileId } : {}),
      raison, ...(commentaire.trim() ? { commentaire: commentaire.trim() } : {}),
    });
    setEnvoi(false);
    if (error) {
      setMessage(error.code === '23505' ? 'Vous avez déjà une demande de retrait en cours pour ce lieu.' : `Envoi impossible : ${error.message}`);
      return;
    }
    setEnAttente(true); setOuvert(false);
    setMessage('Demande envoyée : l’équipe PetsMatch va l’examiner.');
  }

  return (
    <div className={`bg-white rounded-2xl shadow-sm ${className}`} style={{ fontFamily: 'Galey, sans-serif' }}>
      {enAttente ? (
        <div className="px-4 py-3">
          <p className="text-sm font-bold text-gray-500">Demande de retrait envoyée</p>
          <p className="text-xs text-gray-500">En attente de l&apos;équipe PetsMatch (suivi dans Mes contributions).</p>
        </div>
      ) : (
        <button type="button" onClick={() => { if (user) setOuvert(o => !o); else setMessage('Connectez-vous pour faire cette demande.'); }}
          className="w-full text-left px-4 py-3 text-sm font-bold text-red-600 hover:bg-gray-50 rounded-2xl">
          Demander le retrait de ce lieu
        </button>
      )}
      {ouvert && !enAttente && (
        <div className="px-4 pb-4 space-y-3">
          <p className="text-xs text-gray-500">L&apos;équipe PetsMatch vérifie la demande avant de retirer « {placeNom} ». Vous serez prévenu(e) de sa décision.</p>
          <label className="block">
            <span className="text-xs font-semibold text-gray-500">Raison</span>
            <select value={raison} onChange={e => setRaison(e.target.value)}
              className="w-full mt-1 border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white">
              <option value="">Choisir…</option>
              {RAISONS_RETRAIT.filter(([, , n]) => !n || n === nature).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select>
          </label>
          <textarea value={commentaire} onChange={e => setCommentaire(e.target.value)} rows={3}
            placeholder={raison === 'doublon' ? 'Nom ou adresse du lieu en double (obligatoire)' : commentaireRequis ? 'Précisions (obligatoire)' : 'Précisions (facultatif)'}
            className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
          <button type="button" disabled={!valide || envoi} onClick={envoyer}
            className="w-full py-2.5 rounded-xl bg-[#0C5C6C] text-white font-bold text-sm disabled:opacity-40">
            {envoi ? 'Envoi…' : 'Envoyer la demande'}
          </button>
        </div>
      )}
      {message && <p className="px-4 pb-3 text-sm text-[#0C5C6C]">{message}</p>}
    </div>
  );
}
