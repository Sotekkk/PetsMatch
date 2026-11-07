'use client';
// Pension — accepter une demande de séjour (un ou plusieurs animaux du même
// client) en attribuant un logement à chaque animal : seuls les logements qui
// acceptent son espèce sont proposés, avec leur occupation sur la période
// (les logements pleins sont grisés). Le séjour (et l'essai) part au registre
// avec ce logement (route /api/pension/sejour, action decider + logements).
// Sans logement configuré (pension familiale) : acceptation directe.
// Miroir appli : pension_dashboard.dart _accepterAvecLogements.
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { logementAccepteEspece } from '@/lib/pension-especes';
import { dureePassage, heureValide, lireHoraires, type HorairesPension } from '@/lib/pension-horaires';
import { PensionFacturationModal } from '@/components/PensionFacturationModal';
import type { PensionEntree } from '@/components/PensionEntreeModal';

export interface DemandeSejour {
  id: string; animal_id: string; animal_nom: string | null; espece?: string | null;
  date_arrivee: string; date_depart: string; essai_date: string | null; hebergement?: string | null;
  heure_arrivee?: string | null; heure_depart?: string | null; nouveau_pensionnaire?: boolean | null;
}
interface Logement { id: string; nom: string; type: string | null; capacite: number | null; especes: string[] | null }
interface Occupation { date_entree: string; date_sortie_prevue: string | null; logement_id: string | null }

/** Nuits du séjour (le jour du départ n'est pas compté ; séjour d'un jour = ce jour). */
function nuits(arrivee: string, depart: string) {
  const out: string[] = [];
  const d = new Date(`${arrivee}T12:00:00Z`);
  const fin = new Date(`${depart}T12:00:00Z`);
  while (d < fin && out.length < 400) { out.push(d.toISOString().slice(0, 10)); d.setUTCDate(d.getUTCDate() + 1); }
  return out.length ? out : [arrivee];
}
const occupe = (e: Occupation, j: string) =>
  e.date_entree <= j && (!e.date_sortie_prevue || e.date_sortie_prevue > j || (e.date_sortie_prevue === e.date_entree && j === e.date_entree));

export default function AccepterSejourModal({ groupe, uid, proProfileId, couleur, onClose, onDone }: {
  groupe: DemandeSejour[]; uid: string; proProfileId?: string | null; couleur: string; onClose: () => void; onDone: () => void;
}) {
  const [logements, setLogements] = useState<Logement[] | null>(null);
  const [occupations, setOccupations] = useState<Occupation[]>([]);
  const [choix, setChoix] = useState<Record<string, string>>({});
  const [envoi, setEnvoi] = useState(false);
  // Après acceptation : séjour réservé au planning ; facture d'arrhes proposée.
  const [accepte, setAccepte] = useState(false);
  const [arrhesPct, setArrhesPct] = useState<number | null>(null);
  const [sejourArrhes, setSejourArrhes] = useState<PensionEntree | null>(null);
  const [pensionNom, setPensionNom] = useState('Votre pension');
  const [erreur, setErreur] = useState('');
  const d0 = groupe[0];
  const jours = nuits(d0.date_arrivee, d0.date_depart);
  // Heures prévues : celles demandées par le client, ajustables (nombre
  // d'animaux, premier séjour…), avec la durée de l'arrivée / du départ.
  const [horaires, setHoraires] = useState<HorairesPension | null>(null);
  const [hA, setHA] = useState(d0.heure_arrivee ?? '');
  const [hD, setHD] = useState(d0.heure_depart ?? '');
  const [dA, setDA] = useState<number | ''>('');
  const [dD, setDD] = useState<number | ''>('');
  useEffect(() => {
    if (!proProfileId) return;
    supabase.from('user_profiles').select('pension_horaires').eq('id', proProfileId).maybeSingle().then(({ data }) => {
      const h = lireHoraires((data as { pension_horaires?: unknown } | null)?.pension_horaires);
      setHoraires(h);
      if (h) {
        setDA(dureePassage(h, 'arrivee', groupe.length, groupe.some(d => d.nouveau_pensionnaire === true)));
        setDD(dureePassage(h, 'depart', groupe.length, false));
      }
    });
  }, [proProfileId, groupe]);

  useEffect(() => {
    (async () => {
      const [{ data: lg }, { data: oc }] = await Promise.all([
        supabase.from('enclos_chenil').select('id, nom, type, capacite, especes').eq('uid_eleveur', uid).order('nom'),
        supabase.from('pension_entrees').select('date_entree, date_sortie_prevue, logement_id')
          .eq('pro_uid', uid).eq('statut', 'en_pension').not('logement_id', 'is', null).lte('date_entree', d0.date_depart),
      ]);
      setLogements((lg ?? []) as Logement[]);
      setOccupations((oc ?? []) as Occupation[]);
    })();
  }, [uid, d0.date_depart]);

  /** Places prises au pire jour du séjour dans ce logement (hors animal `sauf`). */
  function pris(l: Logement, sauf: string) {
    const autres = Object.entries(choix).filter(([id, lid]) => lid === l.id && id !== sauf).length;
    return Math.max(0, ...jours.map(j => occupations.filter(o => o.logement_id === l.id && occupe(o, j)).length)) + autres;
  }

  async function accepter(forcer = false) {
    setErreur('');
    if (logements?.length && groupe.some(d => !choix[d.id])) { setErreur('Attribuez un logement à chaque animal.'); return; }
    setEnvoi(true);
    const r = await apiFetch('/api/pension/sejour', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'decider', demandeId: d0.id, demandeIds: groupe.map(d => d.id), accepter: true, logements: choix,
        heures: { arrivee: heureValide(hA) ? hA : null, depart: heureValide(hD) ? hD : null, dureeArrivee: dA || null, dureeDepart: dD || null },
        ...(forcer ? { forcer: true } : {}) }) });
    const j = await r.json().catch(() => ({})) as { error?: string; complet?: boolean };
    setEnvoi(false);
    if (r.status === 409 && j.complet && !forcer) {
      if (window.confirm(`${j.error}\nAccepter quand même ${groupe.length > 1 ? 'ces séjours' : 'ce séjour'} ?`)) accepter(true);
      return;
    }
    if (!r.ok) { setErreur(j.error ?? 'Acceptation impossible'); return; }
    // Arrhes prévues au règlement : facture d'acompte proposée tout de suite.
    let pct: number | null = null;
    if (proProfileId) {
      const { data: p } = await supabase.from('user_profiles').select('nom, tarifs_pension').eq('id', proProfileId).maybeSingle();
      const reg = (p as { tarifs_pension?: { reglement?: { arrhes_pct?: number | null } } } | null)?.tarifs_pension?.reglement;
      pct = reg?.arrhes_pct && reg.arrhes_pct > 0 ? reg.arrhes_pct : null;
      setPensionNom((p as { nom?: string | null } | null)?.nom || 'Votre pension');
    }
    if (!pct) { onDone(); return; }
    setArrhesPct(pct);
    setAccepte(true);
  }

  /** Séjour créé à l'acceptation (pension_demandes.entree_id) : facture d'arrhes. */
  async function facturerArrhes() {
    const { data: dm } = await supabase.from('pension_demandes').select('entree_id').eq('id', d0.id).maybeSingle();
    const eid = (dm as { entree_id?: string | null } | null)?.entree_id;
    if (!eid) { setErreur('Séjour introuvable : facturez depuis le registre.'); return; }
    const { data: en } = await supabase.from('pension_entrees').select('*').eq('id', eid).maybeSingle();
    if (en) setSejourArrhes(en as PensionEntree);
  }

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white';
  if (accepte) {
    return (
      <>
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={onDone}>
          <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5 space-y-3" onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
            <p className="font-bold text-lg text-[#1F2A2E]">{groupe.length > 1 ? 'Séjours acceptés' : 'Séjour accepté'}</p>
            <p className="text-sm text-gray-600">La place est bloquée au planning, le client est prévenu. Envoyez maintenant la facture d&apos;arrhes ({arrhesPct} %){groupe.length > 1 ? ` pour les ${groupe.length} animaux` : ''} ?</p>
            {erreur && <p className="text-sm text-[#B3261E]">{erreur}</p>}
            <div className="flex gap-2">
              <button onClick={onDone} className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-gray-200 text-gray-600">Plus tard</button>
              <button onClick={() => { void facturerArrhes(); }} className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white" style={{ background: couleur }}>Facturer les arrhes</button>
            </div>
          </div>
        </div>
        {sejourArrhes && (
          <PensionFacturationModal entree={sejourArrhes} proProfileId={proProfileId ?? null} pensionNom={pensionNom} acompte={arrhesPct}
            onClose={() => { setSejourArrhes(null); onDone(); }} />
        )}
      </>
    );
  }
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5 max-h-[92vh] overflow-y-auto space-y-3" onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <div>
          <p className="font-bold text-lg text-[#1F2A2E]">Accepter {groupe.length > 1 ? `les ${groupe.length} séjours` : 'le séjour'}</p>
          <p className="text-sm text-gray-500">Du {new Date(`${d0.date_arrivee}T12:00:00`).toLocaleDateString('fr-FR')} au {new Date(`${d0.date_depart}T12:00:00`).toLocaleDateString('fr-FR')}</p>
        </div>
        {(horaires || d0.heure_arrivee || d0.heure_depart) && (
          <div className="grid grid-cols-2 gap-2 border border-gray-100 rounded-xl p-3">
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Arrivée prévue{d0.heure_arrivee ? ` (demandée : ${d0.heure_arrivee.replace(':', 'h')})` : ''}</label>
              <input type="time" step={900} value={hA} onChange={e => setHA(e.target.value)} className={champ} />
              <label className="block text-[11px] text-gray-500 mt-1">Durée (min)</label>
              <input type="number" min={5} max={240} step={5} value={dA} onChange={e => setDA(e.target.value ? Number(e.target.value) : '')} className={champ} />
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Départ prévu{d0.heure_depart ? ` (demandé : ${d0.heure_depart.replace(':', 'h')})` : ''}</label>
              <input type="time" step={900} value={hD} onChange={e => setHD(e.target.value)} className={champ} />
              <label className="block text-[11px] text-gray-500 mt-1">Durée (min)</label>
              <input type="number" min={5} max={240} step={5} value={dD} onChange={e => setDD(e.target.value ? Number(e.target.value) : '')} className={champ} />
            </div>
            <p className="col-span-2 text-[11px] text-gray-500">{groupe.length} animal{groupe.length > 1 ? 'aux' : ''}{groupe.some(d => d.nouveau_pensionnaire === true) ? ' · premier séjour' : ''} : ajustez l&apos;heure et la durée si besoin.</p>
          </div>
        )}
        {logements === null ? (
          <p className="text-sm text-gray-500">Chargement des logements…</p>
        ) : logements.length === 0 ? (
          <p className="text-sm text-gray-500">Aucun logement configuré : le séjour sera accepté sans logement attribué.</p>
        ) : groupe.map(d => {
          const proposes = logements.filter(l => logementAccepteEspece(l.especes, d.espece));
          return (
            <div key={d.id}>
              <label className="block text-xs font-semibold text-gray-600 mb-1">
                Logement pour {d.animal_nom ?? 'l\'animal'}{d.espece ? ` (${d.espece})` : ''}{d.hebergement ? ` · ${d.hebergement === 'pre' ? 'pré' : 'box'} souhaité` : ''}
              </label>
              {proposes.length === 0 ? (
                <p className="text-xs text-[#B45309]">Aucun logement n&apos;accepte cette espèce : cochez-la sur un logement (Chenil / logements).</p>
              ) : (
                <select value={choix[d.id] ?? ''} onChange={e => setChoix(c => ({ ...c, [d.id]: e.target.value }))} className={champ}>
                  <option value="">Choisir un logement…</option>
                  {proposes.map(l => {
                    const cap = l.capacite ?? 1;
                    const n = pris(l, d.id);
                    const plein = n >= cap;
                    return <option key={l.id} value={l.id} disabled={plein}>{l.nom}{l.type ? ` (${l.type})` : ''} — {plein ? 'complet' : `${cap - n} place${cap - n > 1 ? 's' : ''} libre${cap - n > 1 ? 's' : ''}`}</option>;
                  })}
                </select>
              )}
            </div>
          );
        })}
        {erreur && <p className="text-sm text-[#B3261E]">{erreur}</p>}
        <div className="flex gap-2 pt-1">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-gray-200 text-gray-600">Annuler</button>
          <button onClick={() => accepter()} disabled={envoi || logements === null} className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: couleur }}>
            {envoi ? 'Enregistrement…' : 'Accepter'}
          </button>
        </div>
      </div>
    </div>
  );
}
