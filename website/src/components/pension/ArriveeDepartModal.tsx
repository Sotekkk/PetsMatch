'use client';
// Pension — enregistrer l'arrivée / le départ d'un séjour (pension_entrees) :
// heure réelle, personne qui dépose / récupère (autorisée ?), hébergement,
// effets personnels, consignes du séjour, observations. Miroir appli :
// lib/pages/pro/pension_arrivee_depart.dart.
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

const TEAL = '#0C5C6C';

export interface SejourPension {
  id: string; animal_id?: string | null; animal_nom?: string | null; proprietaire_nom?: string | null;
  logement_id?: string | null; effets_personnels?: string | null; consignes_sejour?: string | null;
}

const hhmm = (d: Date) => `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;

export default function ArriveeDepartModal({ sejour, mode, uid, onClose, onDone }: {
  sejour: SejourPension; mode: 'arrivee' | 'depart'; uid: string; onClose: () => void; onDone: () => void;
}) {
  const [connus, setConnus] = useState<string[]>([]);
  const [logements, setLogements] = useState<{ id: string; nom: string; type: string | null }[]>([]);
  const [heure, setHeure] = useState(() => hhmm(new Date()));
  const [personne, setPersonne] = useState('');
  const [logementId, setLogementId] = useState(sejour.logement_id ?? '');
  const [alim, setAlim] = useState('');
  const [trait, setTrait] = useState('');
  const [effets, setEffets] = useState(sejour.effets_personnels ?? '');
  const [consignes, setConsignes] = useState(sejour.consignes_sejour ?? '');
  const [obs, setObs] = useState('');
  const [effetsRendus, setEffetsRendus] = useState(false);
  const [traitRendus, setTraitRendus] = useState(false);
  const [reglement, setReglement] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let annule = false;
    (async () => {
      const noms: string[] = sejour.proprietaire_nom?.trim() ? [sejour.proprietaire_nom.trim()] : [];
      if (sejour.animal_id) {
        const { data } = await supabase.from('animaux').select('personnes_autorisees').eq('id', sejour.animal_id).maybeSingle();
        for (const c of ((data as { personnes_autorisees?: { nom?: string }[] } | null)?.personnes_autorisees ?? [])) {
          const n = c?.nom?.trim(); if (n && !noms.includes(n)) noms.push(n);
        }
      }
      const { data: l } = await supabase.from('enclos_chenil').select('id, nom, type').eq('uid_eleveur', uid).order('nom');
      if (annule) return;
      setConnus(noms); setPersonne(noms[0] ?? '');
      setLogements((l ?? []) as { id: string; nom: string; type: string | null }[]);
    })();
    return () => { annule = true; };
  }, [sejour.animal_id, sejour.proprietaire_nom, uid]);

  const autorise = connus.some(n => n.toLowerCase() === personne.trim().toLowerCase());

  async function valider() {
    setSaving(true);
    const [h, m] = heure.split(':').map(Number);
    const d = new Date(); d.setHours(h || 0, m || 0, 0, 0);
    const v = (x: string) => x.trim() || null;
    let complet: Record<string, unknown>, minimal: Record<string, unknown>;
    if (mode === 'arrivee') {
      const c = [consignes.trim(), alim.trim() ? `Alimentation apportée : ${alim.trim()}` : '', trait.trim() ? `Traitements apportés : ${trait.trim()}` : '']
        .filter(Boolean).join('\n');
      complet = {
        statut: 'en_pension', arrivee_reelle_le: d.toISOString(), depose_par: v(personne),
        logement_id: logementId || null, effets_personnels: v(effets), consignes_sejour: c || null, observations_arrivee: v(obs),
      };
      minimal = { logement_id: logementId || null };
    } else {
      const o = [obs.trim(), effetsRendus ? '' : 'Effets personnels non cochés comme restitués.', reglement ? '' : 'Règlement non vérifié au départ.']
        .filter(Boolean).join('\n');
      const jour = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
      complet = { statut: 'sorti', date_sortie_effective: jour, depart_reel_le: d.toISOString(), recupere_par: v(personne), observations_depart: o || null };
      minimal = { statut: 'sorti', date_sortie_effective: jour };
    }
    const { error } = await supabase.from('pension_entrees').update(complet).eq('id', sejour.id);
    if (error) {
      // migration_pension_fiche.sql pas encore passée : on garde l'essentiel.
      await supabase.from('pension_entrees').update(minimal).eq('id', sejour.id);
      alert('Enregistré sans le détail (migration_pension_fiche.sql à passer).');
    }
    setSaving(false);
    onDone();
  }

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm';
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5 max-h-[90vh] overflow-y-auto space-y-3" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <h2 className="font-extrabold text-lg" style={{ color: TEAL }}>{mode === 'arrivee' ? 'Arrivée' : 'Départ'} — {sejour.animal_nom ?? 'Animal'}</h2>
        <label className="flex items-center gap-2 text-sm">Heure réelle
          <input type="time" value={heure} onChange={e => setHeure(e.target.value)} className="border border-gray-200 rounded-lg px-2 py-1" />
        </label>
        {connus.length > 0 && (
          <div>
            <p className="text-xs font-semibold text-gray-500 mb-1">{mode === 'arrivee' ? 'Propriétaire / personnes connues' : 'Personnes autorisées'}</p>
            <div className="flex flex-wrap gap-1.5">
              {connus.map(n => <button key={n} type="button" onClick={() => setPersonne(n)} className="text-xs px-2.5 py-1 rounded-full border border-gray-200">{n}</button>)}
            </div>
          </div>
        )}
        <input value={personne} onChange={e => setPersonne(e.target.value)} placeholder={mode === 'arrivee' ? 'Déposé par' : 'Récupéré par'} className={champ} />
        {mode === 'depart' && personne.trim() && !autorise && (
          <p className="text-xs text-red-700">Cette personne n&apos;est ni le propriétaire ni une personne autorisée : vérifiez son identité.</p>
        )}
        {mode === 'arrivee' ? (
          <>
            {logements.length > 0 && (
              <select value={logementId} onChange={e => setLogementId(e.target.value)} className={`${champ} bg-white`}>
                <option value="">Sans hébergement attribué</option>
                {logements.map(l => <option key={l.id} value={l.id}>{l.nom}{l.type ? ` (${l.type})` : ''}</option>)}
              </select>
            )}
            <input value={alim} onChange={e => setAlim(e.target.value)} placeholder="Alimentation apportée" className={champ} />
            <input value={trait} onChange={e => setTrait(e.target.value)} placeholder="Traitements apportés" className={champ} />
            <input value={effets} onChange={e => setEffets(e.target.value)} placeholder="Effets personnels (panier, laisse, jouets…)" className={champ} />
            <textarea value={consignes} onChange={e => setConsignes(e.target.value)} rows={2} placeholder="Consignes pour ce séjour" className={champ} />
            <textarea value={obs} onChange={e => setObs(e.target.value)} rows={2} placeholder="Observations à l'arrivée" className={champ} />
          </>
        ) : (
          <>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={effetsRendus} onChange={e => setEffetsRendus(e.target.checked)} />
              Effets personnels restitués{sejour.effets_personnels ? ` (${sejour.effets_personnels})` : ''}</label>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={traitRendus} onChange={e => setTraitRendus(e.target.checked)} />
              Alimentation et traitements restants restitués</label>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={reglement} onChange={e => setReglement(e.target.checked)} />
              Situation administrative vérifiée (règlement)</label>
            <textarea value={obs} onChange={e => setObs(e.target.value)} rows={3} placeholder="Observations finales" className={champ} />
          </>
        )}
        <div className="flex gap-2 pt-1">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Annuler</button>
          <button onClick={valider} disabled={saving} className="flex-[2] py-2.5 rounded-xl text-sm font-bold text-white disabled:opacity-50" style={{ background: TEAL }}>
            {saving ? '…' : mode === 'arrivee' ? "Enregistrer l'arrivée" : 'Enregistrer le départ'}
          </button>
        </div>
      </div>
    </div>
  );
}
