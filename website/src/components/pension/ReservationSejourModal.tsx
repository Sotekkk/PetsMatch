'use client';
// Pension — réservation d'un séjour par le client (au lieu d'un rendez-vous) :
// animal, dates d'arrivée / départ, date d'essai si la pension l'exige pour un
// premier séjour, estimation (tarifs publics), message. Demande à accepter par
// la pension (route /api/pension/sejour). Miroir appli : pension_reservation_page.dart.
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

interface Animal { id: string; nom: string | null; espece: string | null }
interface InfosPension { nom: string; essai_requis: boolean; essai_info: string | null; tarifs: { especes?: { espece: string; prix_seul?: number }[] } | null }

const CLE_ESPECE: Record<string, string> = { chien: 'chien', chiens: 'chien', chat: 'chat', chats: 'chat', lapin: 'lapin', cheval: 'cheval', equide: 'cheval', nac: 'nac' };

export default function ReservationSejourModal({ pensionProfileId, pensionNom, couleur, onClose, onVisite }: {
  pensionProfileId: string; pensionNom: string; couleur: string; onClose: () => void; onVisite?: () => void;
}) {
  const { user } = useAuth();
  const pid = useActiveProfile();
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [animalId, setAnimalId] = useState('');
  const [arrivee, setArrivee] = useState('');
  const [depart, setDepart] = useState('');
  const [essai, setEssai] = useState('');
  const [message, setMessage] = useState('');
  const [infos, setInfos] = useState<InfosPension | null>(null);
  const [premier, setPremier] = useState<boolean | null>(null);
  const [etat, setEtat] = useState<'' | 'envoi' | 'ok'>('');
  const [erreur, setErreur] = useState('');
  const [aujourdhui, setAujourdhui] = useState('');

  useEffect(() => {
    if (!user) return;
    (async () => {
      let q = supabase.from('animaux_proprietes').select('animal_id').eq('uid_proprio', user.uid).is('date_fin', null);
      if (pid) q = q.eq('profile_id_proprio', pid);
      const { data } = await q;
      const ids = ((data ?? []) as { animal_id: string }[]).map(r => r.animal_id);
      if (ids.length) {
        const { data: an } = await supabase.from('animaux').select('id, nom, espece, statut').in('id', ids).not('statut', 'in', '(sorti,decede)').order('nom');
        setAnimaux((an ?? []) as Animal[]);
      }
      setAujourdhui(new Date().toISOString().slice(0, 10));
    })();
  }, [user, pid]);

  useEffect(() => {
    if (!user) return;
    apiFetch(`/api/pension/sejour?pensionProfileId=${encodeURIComponent(pensionProfileId)}${animalId ? `&animalId=${encodeURIComponent(animalId)}` : ''}`, { cache: 'no-store' })
      .then(r => (r.ok ? r.json() : null))
      .then(j => { if (j) { setInfos(j.pension as InfosPension); setPremier(j.premier_sejour as boolean | null); } })
      .catch(() => {});
  }, [user, pensionProfileId, animalId]);

  const essaiRequis = !!infos?.essai_requis && premier === true;
  const nuits = arrivee && depart ? Math.round((new Date(depart).getTime() - new Date(arrivee).getTime()) / 86400000) : 0;
  const animal = animaux.find(a => a.id === animalId);
  const cle = CLE_ESPECE[(animal?.espece ?? '').toLowerCase()] ?? (animal?.espece ?? '').toLowerCase();
  const prix = infos?.tarifs?.especes?.find(e => e.espece === cle)?.prix_seul;
  const estimation = prix && nuits > 0 ? `${nuits} nuit${nuits > 1 ? 's' : ''} × ${prix} € = ${nuits * prix} € environ (hors réductions et options)` : '';

  async function envoyer() {
    setErreur('');
    if (!animalId || !arrivee || !depart) { setErreur('Choisissez l\'animal et les dates du séjour.'); return; }
    if (depart < arrivee) { setErreur('La date de départ doit suivre l\'arrivée.'); return; }
    if (essaiRequis && (!essai || essai >= arrivee)) { setErreur('Choisissez une date d\'essai avant l\'arrivée.'); return; }
    setEtat('envoi');
    const r = await apiFetch('/api/pension/sejour', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pensionProfileId, animalId, dateArrivee: arrivee, dateDepart: depart, ...(essaiRequis ? { essaiDate: essai } : {}),
        message, ...(pid ? { profileId: pid } : {}) }),
    });
    const j = await r.json().catch(() => ({})) as { error?: string };
    if (!r.ok) { setEtat(''); setErreur(j.error ?? 'Demande impossible'); return; }
    setEtat('ok');
  }

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm';
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5 max-h-[92vh] overflow-y-auto space-y-3" onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <div>
          <p className="font-bold text-lg text-[#1F2A2E]">Réserver un séjour</p>
          <p className="text-sm text-gray-500">{pensionNom}</p>
        </div>
        {etat === 'ok' ? (
          <>
            <p className="text-sm text-gray-700">Demande envoyée. {pensionNom} va l&apos;étudier ; vous serez prévenu dès qu&apos;elle sera acceptée.</p>
            <button onClick={onClose} className="w-full py-2.5 rounded-xl text-sm font-semibold text-white" style={{ background: couleur }}>Fermer</button>
          </>
        ) : (
          <>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Animal</label>
              {animaux.length === 0 ? <p className="text-sm text-gray-500">Ajoutez d&apos;abord votre animal dans « Mes animaux ».</p> : (
                <select value={animalId} onChange={e => { setAnimalId(e.target.value); setEssai(''); }} className={`${champ} bg-white`}>
                  <option value="">Choisir…</option>
                  {animaux.map(a => <option key={a.id} value={a.id}>{a.nom ?? 'Animal'}</option>)}
                </select>
              )}
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div><label className="block text-xs font-semibold text-gray-600 mb-1">Arrivée</label>
                <input type="date" min={aujourdhui} value={arrivee} onChange={e => setArrivee(e.target.value)} className={champ} /></div>
              <div><label className="block text-xs font-semibold text-gray-600 mb-1">Départ</label>
                <input type="date" min={arrivee || aujourdhui} value={depart} onChange={e => setDepart(e.target.value)} className={champ} /></div>
            </div>
            {nuits > 0 && <p className="text-xs text-gray-500">{nuits} nuit{nuits > 1 ? 's' : ''}{estimation ? ` · estimation : ${estimation}` : ''}</p>}
            {essaiRequis && (
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Essai avant le premier séjour</label>
                <p className="text-xs text-gray-500 mb-1">{infos?.essai_info?.trim() || 'Cette pension demande une journée d\'essai avant le premier séjour de votre animal.'}</p>
                <input type="date" min={aujourdhui} max={arrivee || undefined} value={essai} onChange={e => setEssai(e.target.value)} className={champ} />
              </div>
            )}
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Message pour la pension (facultatif)</label>
              <textarea value={message} onChange={e => setMessage(e.target.value)} rows={2} placeholder="Habitudes, horaires d'arrivée, besoins particuliers…" className={`${champ} resize-none`} />
            </div>
            <p className="text-[11px] text-gray-400">La pension aura accès à la fiche de votre animal (santé, alimentation) pour préparer le séjour.</p>
            {erreur && <p className="text-sm text-[#B3261E]">{erreur}</p>}
            <button onClick={envoyer} disabled={etat === 'envoi' || !animaux.length} className="w-full py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: couleur }}>
              {etat === 'envoi' ? 'Envoi…' : 'Envoyer la demande de séjour'}
            </button>
            {onVisite && <button onClick={onVisite} className="w-full text-sm font-semibold" style={{ color: couleur }}>Demander plutôt une visite de la pension</button>}
          </>
        )}
      </div>
    </div>
  );
}
