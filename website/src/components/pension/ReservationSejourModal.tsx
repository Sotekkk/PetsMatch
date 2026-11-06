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
import { pensionGroupe, pensionPrixNuit, pensionTarifEquin, pensionTarifKeyForEspece, pensionTarifPourKey, type EspeceTarif } from '@/lib/pension-especes';

interface Animal { id: string; nom: string | null; espece: string | null; race?: string | null; photo_url?: string | null }
interface InfosPension { nom: string; essai_requis: boolean; essai_info: string | null; tarifs: { especes?: EspeceTarif[] } | null; especes?: string[] }

/** L'espèce de l'animal fait partie de celles acceptées par la pension
 *  (aucune renseignée = toutes ; « NAC » accepte un lapin, « Équidés » un âne).
 *  Miroir serveur : api/pension/sejour accepte(). */
function especeAcceptee(acceptees: string[] | undefined, espece: string | null) {
  if (!acceptees?.length) return true;
  const cle = (e: string | null | undefined) => pensionTarifKeyForEspece(e) ?? (e ?? '').trim().toLowerCase();
  const k = cle(espece);
  if (!k) return true;
  return acceptees.some(x => { const c = cle(x); return c === k || pensionGroupe(c) === pensionGroupe(k); });
}

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
  // Équidés : hébergement souhaité pour chaque animal (box / pré).
  const [hebergements, setHebergements] = useState<Record<string, 'box' | 'pre'>>({});
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

  // Seuls les animaux d'une espèce acceptée par la pension sont proposés.
  const proposes = animaux.filter(a => especeAcceptee(infos?.especes, a.espece));
  const nonProposes = animaux.length - proposes.length;
  const choisis = proposes.filter(a => animalIds.includes(a.id));
  const basculer = (id: string) => setAnimalIds(ids => ids.includes(id) ? ids.filter(x => x !== id) : [...ids, id]);
  const equins = choisis.filter(a => pensionTarifEquin(pensionTarifKeyForEspece(a.espece)));
  // Animaux sans historique chez cette pension : « déjà venu ? » pour chacun.
  const aQuestionner = choisis.filter(a => premiers[a.id] === true);
  const nouveaux = aQuestionner.filter(a => dejaVenus[a.id] === false);
  const essaiRequis = !!infos?.essai_requis && nouveaux.length > 0;
  const nuits = arrivee && depart ? Math.round((new Date(depart).getTime() - new Date(arrivee).getTime()) / 86400000) : 0;
  // Estimation : nuits × prix/nuit de l'espèce, pour chaque animal (tarifs publics).
  const prixAnimaux = choisis.map(a => {
    const cle = pensionTarifKeyForEspece(a.espece);
    const tarif = cle ? pensionTarifPourKey(infos?.tarifs?.especes ?? [], cle) : undefined;
    return tarif ? pensionPrixNuit(tarif, { hebergement: hebergements[a.id] ?? null }) : 0;
  });
  const prixTotal = prixAnimaux.length && prixAnimaux.every(p => p > 0) ? prixAnimaux.reduce((t, p) => t + p, 0) : 0;
  const estimation = prixTotal && nuits > 0
    ? `${nuits} nuit${nuits > 1 ? 's' : ''} × ${prixTotal} €${choisis.length > 1 ? ` (${choisis.length} animaux)` : ''} = ${nuits * prixTotal} € environ (hors réductions et options)`
    : '';

  async function envoyer() {
    setErreur('');
    if (!choisis.length || !arrivee || !depart) { setErreur('Cochez les animaux et choisissez les dates du séjour.'); return; }
    if (depart < arrivee) { setErreur('La date de départ doit suivre l\'arrivée.'); return; }
    if (arrivee < aujourdhui) { setErreur('La date d\'arrivée est passée.'); return; }
    const jours = (a: string, b: string) => Math.round((new Date(`${b}T12:00:00`).getTime() - new Date(`${a}T12:00:00`).getTime()) / 86400000);
    if (jours(aujourdhui, arrivee) > 365) { setErreur('La date d\'arrivée est à plus d\'un an : vérifiez l\'année.'); return; }
    if (jours(arrivee, depart) > 180) { setErreur('Séjour de plus de 6 mois : vérifiez les dates ou contactez directement la pension.'); return; }
    if (complet) { setErreur(complet); return; }
    const sansReponse = aQuestionner.find(a => typeof dejaVenus[a.id] !== 'boolean');
    if (sansReponse) { setErreur(`Indiquez si ${sansReponse.nom ?? 'votre animal'} est déjà venu dans cette pension.`); return; }
    if (essaiRequis && (!essai || essai >= arrivee)) { setErreur('Choisissez une date d\'essai avant l\'arrivée.'); return; }
    setEtat('envoi');
    const r = await apiFetch('/api/pension/sejour', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pensionProfileId, animalIds: choisis.map(a => a.id), animalId: choisis[0]?.id, dateArrivee: arrivee, dateDepart: depart,
        ...(aQuestionner.length ? { dejaVenus: Object.fromEntries(aQuestionner.map(a => [a.id, dejaVenus[a.id]])) } : {}),
        ...(equins.some(a => hebergements[a.id]) ? { hebergements: Object.fromEntries(equins.filter(a => hebergements[a.id]).map(a => [a.id, hebergements[a.id]])) } : {}),
        ...(essaiRequis ? { essaiDate: essai } : {}),
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
              <label className="block text-xs font-semibold text-gray-600 mb-1">Animaux à mettre en pension</label>
              {proposes.length === 0 ? (
                <p className="text-sm text-gray-500">{animaux.length === 0
                  ? 'Aucune fiche animal sur votre profil.'
                  : 'Aucun de vos animaux n\'est d\'une espèce accueillie par cette pension.'}</p>
              ) : (
                <div className="border border-gray-200 rounded-xl divide-y divide-gray-100">
                  {proposes.map(a => {
                    const coche = animalIds.includes(a.id);
                    return (
                      <label key={a.id} className="flex items-center gap-3 px-3 py-2 cursor-pointer">
                        <input type="checkbox" checked={coche} onChange={() => basculer(a.id)} className="w-4 h-4" style={{ accentColor: couleur }} />
                        {a.photo_url
                          // eslint-disable-next-line @next/next/no-img-element
                          ? <img src={a.photo_url} alt="" className="w-9 h-9 rounded-lg object-cover flex-shrink-0" />
                          : <span className="w-9 h-9 rounded-lg bg-[#EEF5EA] flex-shrink-0" />}
                        <span className="flex-1 min-w-0">
                          <span className="block text-sm font-semibold text-[#1F2A2E] truncate">{a.nom ?? 'Animal'}</span>
                          <span className="block text-xs text-gray-500 truncate">{[a.espece, a.race].filter(Boolean).join(' · ')}</span>
                        </span>
                      </label>
                    );
                  })}
                </div>
              )}
              {nonProposes > 0 && proposes.length > 0 && (
                <p className="text-xs text-gray-400 mt-1">{nonProposes} animal{nonProposes > 1 ? 'aux' : ''} non proposé{nonProposes > 1 ? 's' : ''} : espèce non accueillie par cette pension.</p>
              )}
              {choisis.length > 1 && <p className="text-xs mt-1" style={{ color: couleur }}>{choisis.length} animaux pour ce séjour.</p>}
              <p className="text-xs text-gray-500 mt-1.5">Votre animal n&apos;est pas dans la liste ? Créez d&apos;abord sa fiche dans « Mes animaux », puis revenez réserver.</p>
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
            {equins.map(a => (
              <div key={`h${a.id}`}>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Hébergement souhaité pour {a.nom ?? 'cet animal'}</label>
                <div className="flex flex-wrap gap-2">
                  {([['box', 'Box'], ['pre', 'Pré']] as const).map(([v, lib]) => (
                    <button key={v} type="button"
                      onClick={() => setHebergements(m => { const n = { ...m }; if (n[a.id] === v) delete n[a.id]; else n[a.id] = v; return n; })}
                      className="px-3 py-1.5 rounded-full text-sm border"
                      style={hebergements[a.id] === v ? { background: couleur, color: '#fff', borderColor: couleur } : { borderColor: '#E5E7EB', color: '#1F2A2E' }}>
                      {lib}
                    </button>
                  ))}
                </div>
              </div>
            ))}
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
            <button onClick={envoyer} disabled={etat === 'envoi' || !choisis.length || !!complet} className="w-full py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: couleur }}>
              {etat === 'envoi' ? 'Envoi…' : 'Envoyer la demande de séjour'}
            </button>
            {onVisite && <button onClick={onVisite} className="w-full text-sm font-semibold" style={{ color: couleur }}>Demander plutôt une visite de la pension</button>}
          </>
        )}
      </div>
    </div>
  );
}
