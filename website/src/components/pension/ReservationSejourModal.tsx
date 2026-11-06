'use client';
// Pension — réservation d'un séjour par le client (au lieu d'un rendez-vous) :
// un ou plusieurs animaux (liste à cocher, comme le vétérinaire), dates
// d'arrivée / départ (places libres vérifiées pour le nombre d'animaux), date d'essai si la pension l'exige pour un
// premier séjour, estimation (tarifs publics), message. Demande à accepter par
// la pension (route /api/pension/sejour). Miroir appli : pension_reservation_page.dart.
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { AnimalMultiPickerField } from '@/components/AnimalPickerField';
import { pensionPrixNuit, pensionTarifEquin, pensionTarifKeyForEspece, pensionTarifPourKey, type EspeceTarif } from '@/lib/pension-especes';

interface Animal { id: string; nom: string | null; espece: string | null; race?: string | null; photo_url?: string | null }
interface InfosPension { nom: string; essai_requis: boolean; essai_info: string | null; tarifs: { especes?: EspeceTarif[] } | null }

export default function ReservationSejourModal({ pensionProfileId, pensionNom, couleur, onClose, onVisite }: {
  pensionProfileId: string; pensionNom: string; couleur: string; onClose: () => void; onVisite?: () => void;
}) {
  const { user } = useAuth();
  const pid = useActiveProfile();
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [animalIds, setAnimalIds] = useState<string[]>([]);
  const [arrivee, setArrivee] = useState('');
  const [depart, setDepart] = useState('');
  const [essai, setEssai] = useState('');
  const [message, setMessage] = useState('');
  const [infos, setInfos] = useState<InfosPension | null>(null);
  // Premier séjour de chaque animal chez cette pension.
  const [premiers, setPremiers] = useState<Record<string, boolean>>({});
  // Sans historique chez cette pension : l'animal est-il déjà venu ? (absent = pas répondu)
  const [dejaVenus, setDejaVenus] = useState<Record<string, boolean>>({});
  // Places libres aux dates choisies pour le nombre d'animaux (message si complet).
  const [complet, setComplet] = useState<string | null>(null);
  // Équidés : hébergement souhaité.
  const [hebergement, setHebergement] = useState<'box' | 'pre' | null>(null);
  const [etat, setEtat] = useState<'' | 'envoi' | 'ok'>('');
  const [erreur, setErreur] = useState('');
  const [aujourdhui, setAujourdhui] = useState('');

  // Fiche créée dans un autre onglet (« Créer la fiche de mon animal ») : liste rechargée au retour.
  const [rechargement, setRechargement] = useState(0);
  useEffect(() => {
    const auRetour = () => setRechargement(n => n + 1);
    window.addEventListener('focus', auRetour);
    return () => window.removeEventListener('focus', auRetour);
  }, []);

  useEffect(() => {
    if (!user) return;
    (async () => {
      let q = supabase.from('animaux_proprietes').select('animal_id').eq('uid_proprio', user.uid).is('date_fin', null);
      if (pid) q = q.eq('profile_id_proprio', pid);
      const { data } = await q;
      const ids = ((data ?? []) as { animal_id: string }[]).map(r => r.animal_id);
      if (ids.length) {
        const { data: an } = await supabase.from('animaux').select('id, nom, espece, race, photo_url, statut').in('id', ids).not('statut', 'in', '(sorti,decede)').order('nom');
        setAnimaux((an ?? []) as Animal[]);
      }
      setAujourdhui(new Date().toISOString().slice(0, 10));
    })();
  }, [user, pid, rechargement]);

  const datesOk = !!arrivee && !!depart && depart >= arrivee;
  useEffect(() => {
    if (!user) return;
    const qs = new URLSearchParams({ pensionProfileId });
    if (animalIds.length) qs.set('animalIds', animalIds.join(','));
    if (datesOk) { qs.set('arrivee', arrivee); qs.set('depart', depart); qs.set('nb', String(Math.max(1, animalIds.length))); }
    apiFetch(`/api/pension/sejour?${qs.toString()}`, { cache: 'no-store' })
      .then(r => (r.ok ? r.json() : null))
      .then(j => {
        if (!j) return;
        setInfos(j.pension as InfosPension);
        setPremiers((j.premiers ?? {}) as Record<string, boolean>);
        setComplet((j.dispo?.message as string | null | undefined) ?? null);
      })
      .catch(() => {});
  }, [user, pensionProfileId, animalIds, arrivee, depart, datesOk]);

  const choisis = animaux.filter(a => animalIds.includes(a.id));
  // Animaux sans historique chez cette pension : « déjà venu ? » pour chacun.
  const aQuestionner = choisis.filter(a => premiers[a.id] === true);
  const nouveaux = aQuestionner.filter(a => dejaVenus[a.id] === false);
  const essaiRequis = !!infos?.essai_requis && nouveaux.length > 0;
  const nuits = arrivee && depart ? Math.round((new Date(depart).getTime() - new Date(arrivee).getTime()) / 86400000) : 0;
  const equin = choisis.some(a => pensionTarifEquin(pensionTarifKeyForEspece(a.espece)));
  // Estimation : nuits × prix/nuit de l'espèce, pour chaque animal (tarifs publics).
  const prixAnimaux = choisis.map(a => {
    const cle = pensionTarifKeyForEspece(a.espece);
    const tarif = cle ? pensionTarifPourKey(infos?.tarifs?.especes ?? [], cle) : undefined;
    return tarif ? pensionPrixNuit(tarif, { hebergement }) : 0;
  });
  const prixTotal = prixAnimaux.length && prixAnimaux.every(p => p > 0) ? prixAnimaux.reduce((t, p) => t + p, 0) : 0;
  const estimation = prixTotal && nuits > 0
    ? `${nuits} nuit${nuits > 1 ? 's' : ''} × ${prixTotal} €${choisis.length > 1 ? ` (${choisis.length} animaux)` : ''} = ${nuits * prixTotal} € environ (hors réductions et options)`
    : '';

  async function envoyer() {
    setErreur('');
    if (!animalIds.length || !arrivee || !depart) { setErreur('Choisissez les animaux et les dates du séjour.'); return; }
    if (depart < arrivee) { setErreur('La date de départ doit suivre l\'arrivée.'); return; }
    if (complet) { setErreur(complet); return; }
    const sansReponse = aQuestionner.find(a => typeof dejaVenus[a.id] !== 'boolean');
    if (sansReponse) { setErreur(`Indiquez si ${sansReponse.nom ?? 'votre animal'} est déjà venu dans cette pension.`); return; }
    if (essaiRequis && (!essai || essai >= arrivee)) { setErreur('Choisissez une date d\'essai avant l\'arrivée.'); return; }
    setEtat('envoi');
    const r = await apiFetch('/api/pension/sejour', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pensionProfileId, animalIds, animalId: animalIds[0], dateArrivee: arrivee, dateDepart: depart,
        ...(aQuestionner.length ? { dejaVenus: Object.fromEntries(aQuestionner.map(a => [a.id, dejaVenus[a.id]])) } : {}),
        ...(equin && hebergement ? { hebergement } : {}), ...(essaiRequis ? { essaiDate: essai } : {}),
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
            <p className="text-sm text-gray-700">Demande envoyée{choisis.length > 1 ? ` pour ${choisis.map(a => a.nom ?? 'Animal').join(', ')}` : ''}. {pensionNom} va l&apos;étudier ; vous serez prévenu dès qu&apos;elle sera acceptée.</p>
            <a href="/mes-sejours" className="block text-center text-sm font-semibold" style={{ color: couleur }}>Voir mes demandes</a>
            <button onClick={onClose} className="w-full py-2.5 rounded-xl text-sm font-semibold text-white" style={{ background: couleur }}>Fermer</button>
          </>
        ) : (
          <>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Animaux</label>
              {animaux.length === 0 ? <p className="text-sm text-gray-500">Créez d&apos;abord la fiche de votre animal : la pension y trouvera sa santé et son alimentation.</p> : (
                <AnimalMultiPickerField accentColor={couleur}
                  animaux={animaux.map(a => ({ id: a.id, nom: a.nom ?? 'Animal', espece: a.espece ?? '', race: a.race ?? null, photo_url: a.photo_url ?? null }))}
                  selectedIds={animalIds}
                  onChange={ids => { setAnimalIds(ids.map(String)); setHebergement(null); }} />
              )}
              {choisis.length > 1 && <p className="text-xs mt-1" style={{ color: couleur }}>{choisis.length} animaux pour ce séjour.</p>}
            </div>
            {aQuestionner.map(a => (
              <div key={a.id}>
                <label className="block text-xs font-semibold text-gray-600 mb-1">{a.nom ?? 'Votre animal'} est-il déjà venu dans cette pension ?</label>
                <div className="flex flex-wrap gap-2">
                  {([[false, 'Non, nouveau pensionnaire'], [true, 'Oui, il est déjà venu']] as const).map(([v, lib]) => (
                    <button key={lib} type="button" onClick={() => setDejaVenus(m => ({ ...m, [a.id]: v }))}
                      className="px-3 py-1.5 rounded-full text-sm border"
                      style={dejaVenus[a.id] === v ? { background: couleur, color: '#fff', borderColor: couleur } : { borderColor: '#E5E7EB', color: '#1F2A2E' }}>
                      {lib}
                    </button>
                  ))}
                </div>
              </div>
            ))}
            {equin && (
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Hébergement souhaité</label>
                <div className="flex flex-wrap gap-2">
                  {([['box', 'Box'], ['pre', 'Pré']] as const).map(([v, lib]) => (
                    <button key={v} type="button" onClick={() => setHebergement(h => (h === v ? null : v))}
                      className="px-3 py-1.5 rounded-full text-sm border"
                      style={hebergement === v ? { background: couleur, color: '#fff', borderColor: couleur } : { borderColor: '#E5E7EB', color: '#1F2A2E' }}>
                      {lib}
                    </button>
                  ))}
                </div>
              </div>
            )}
            <a href="/mes-animaux/ajouter" target="_blank" rel="noopener" className="inline-block text-sm font-semibold" style={{ color: couleur }}>
              + {animaux.length === 0 ? 'Créer la fiche de mon animal' : 'Ajouter un autre animal'}
            </a>
            <div className="grid grid-cols-2 gap-2">
              <div><label className="block text-xs font-semibold text-gray-600 mb-1">Arrivée</label>
                <input type="date" min={aujourdhui} value={arrivee} onChange={e => setArrivee(e.target.value)} className={champ} /></div>
              <div><label className="block text-xs font-semibold text-gray-600 mb-1">Départ</label>
                <input type="date" min={arrivee || aujourdhui} value={depart} onChange={e => setDepart(e.target.value)} className={champ} /></div>
            </div>
            {nuits > 0 && <p className="text-xs text-gray-500">{nuits} nuit{nuits > 1 ? 's' : ''}{estimation ? ` · estimation : ${estimation}` : ''}</p>}
            {complet && <p className="text-sm font-semibold text-[#B3261E]">{complet} Choisissez d&apos;autres dates{choisis.length > 1 ? ' ou moins d\'animaux' : ''}.</p>}
            {essaiRequis && (
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Essai avant le premier séjour</label>
                <p className="text-xs text-gray-500 mb-1">{infos?.essai_info?.trim() || 'Cette pension demande une journée d\'essai avant le premier séjour de votre animal.'}{nouveaux.length > 1 ? ` Un seul essai pour ${nouveaux.map(a => a.nom ?? 'Animal').join(', ')}.` : ''}</p>
                <input type="date" min={aujourdhui} max={arrivee || undefined} value={essai} onChange={e => setEssai(e.target.value)} className={champ} />
              </div>
            )}
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Consignes pour le séjour (facultatif)</label>
              <textarea value={message} onChange={e => setMessage(e.target.value)} rows={2} placeholder="Traitement à donner, habitudes, horaires d'arrivée…" className={`${champ} resize-none`} />
            </div>
            <p className="text-[11px] text-gray-400">La pension aura accès à la fiche de votre animal (santé, alimentation) pour préparer le séjour.</p>
            {erreur && <p className="text-sm text-[#B3261E]">{erreur}</p>}
            <button onClick={envoyer} disabled={etat === 'envoi' || !animaux.length || !!complet} className="w-full py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: couleur }}>
              {etat === 'envoi' ? 'Envoi…' : 'Envoyer la demande de séjour'}
            </button>
            {onVisite && <button onClick={onVisite} className="w-full text-sm font-semibold" style={{ color: couleur }}>Demander plutôt une visite de la pension</button>}
          </>
        )}
      </div>
    </div>
  );
}
