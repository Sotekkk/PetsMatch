'use client';

// Élevage : créer un RDV vétérinaire à venir depuis l'agenda, et le valider
// (date réelle, animaux réellement vus). Miroir appli : widgets/agenda/rdv_veto_sheets.dart.
import { useEffect, useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { aujourdhuiLocal, creerRdvVeto, validerRdvVeto, type TacheRdvVeto } from '@/lib/rdv-veto';

const TEAL = '#0C5C6C';
const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]';
const etiquette = 'block text-xs font-bold text-[#0C5C6C] mb-1';

function Cadre({ titre, onClose, children }: { titre: string; onClose: () => void; children: React.ReactNode }) {
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto p-5" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <div className="flex items-center gap-3 mb-4">
          <p className="flex-1 font-bold text-base text-[#1F2A2E]">{titre}</p>
          <button type="button" onClick={onClose} className="text-sm text-gray-400">Fermer</button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function NouveauRdvVetoModal({ uid, myUid, profileId, animaux, jour, onClose, onSaved }: {
  uid: string; myUid: string; profileId: string | null;
  animaux: { id: string; nom: string; espece?: string | null }[];
  /** Jour affiché dans l'agenda (repris s'il est à venir). */
  jour?: string; onClose: () => void; onSaved: () => void;
}) {
  const [date, setDate] = useState(jour && jour > aujourdhuiLocal() ? jour : '');
  const [heure, setHeure] = useState('');
  const [cabinet, setCabinet] = useState('');
  const [motif, setMotif] = useState('');
  const [notes, setNotes] = useState('');
  const [recherche, setRecherche] = useState('');
  const [ids, setIds] = useState<Set<string>>(new Set());
  const [erreur, setErreur] = useState('');
  const [enCours, setEnCours] = useState(false);
  const visibles = useMemo(() => animaux.filter(a => a.nom.toLowerCase().includes(recherche.trim().toLowerCase())), [animaux, recherche]);

  async function enregistrer() {
    setEnCours(true); setErreur('');
    const e = await creerRdvVeto({ uid, myUid, profileId, date, heure, cabinet, motif, notes, animaux: animaux.filter(a => ids.has(a.id)) });
    setEnCours(false);
    if (e) setErreur(e); else onSaved();
  }

  return (
    <Cadre titre="RDV vétérinaire à venir" onClose={onClose}>
      <div className="space-y-3">
        <div>
          <label htmlFor="rv-cabinet" className={etiquette}>Cabinet vétérinaire *</label>
          <input id="rv-cabinet" value={cabinet} onChange={e => setCabinet(e.target.value)} placeholder="Nom du cabinet" className={champ} />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label htmlFor="rv-date" className={etiquette}>Date *</label>
            <input id="rv-date" type="date" min={aujourdhuiLocal()} value={date} onChange={e => setDate(e.target.value)} className={champ} />
          </div>
          <div>
            <label htmlFor="rv-heure" className={etiquette}>Heure *</label>
            <input id="rv-heure" type="time" step={300} value={heure} onChange={e => setHeure(e.target.value)} className={champ} />
          </div>
        </div>
        <div>
          <label htmlFor="rv-motif" className={etiquette}>Motif</label>
          <input id="rv-motif" value={motif} onChange={e => setMotif(e.target.value)} placeholder="Vaccins, contrôle de portée…" className={champ} />
        </div>
        <div>
          <div className="flex items-center gap-2 mb-1">
            <p className={`${etiquette} flex-1 mb-0`}>Animaux concernés * ({ids.size})</p>
            <button type="button" onClick={() => setIds(new Set(visibles.map(a => a.id)))} className="text-xs font-semibold text-[#0C5C6C]">Tout cocher</button>
            <button type="button" onClick={() => setIds(new Set())} className="text-xs font-semibold text-gray-500">Aucun</button>
          </div>
          <input type="search" value={recherche} onChange={e => setRecherche(e.target.value)} placeholder="Rechercher un animal" aria-label="Rechercher un animal" className={`${champ} mb-1`} />
          <div className="border border-gray-100 rounded-xl max-h-44 overflow-y-auto p-1">
            {visibles.length === 0 ? <p className="text-xs text-gray-400 p-2">Aucun animal.</p> : visibles.map(a => (
              <label key={a.id} className="flex items-center gap-2 px-2 py-1.5 text-sm rounded-lg hover:bg-gray-50 cursor-pointer">
                <input type="checkbox" checked={ids.has(a.id)} onChange={() => setIds(p => { const n = new Set(p); if (n.has(a.id)) n.delete(a.id); else n.add(a.id); return n; })} />
                <span className="flex-1 truncate">{a.nom}</span>
                {a.espece && <span className="text-xs text-gray-400">{a.espece}</span>}
              </label>
            ))}
          </div>
        </div>
        <div>
          <label htmlFor="rv-notes" className={etiquette}>Notes</label>
          <textarea id="rv-notes" rows={2} value={notes} onChange={e => setNotes(e.target.value)} className={`${champ} resize-none`} />
        </div>
        <p className="text-xs text-gray-500">Le RDV apparaît dans votre agenda. Le carnet et le registre sont remplis quand vous le validez.</p>
        {erreur && <p role="alert" className="text-xs text-red-600">{erreur}</p>}
        <button type="button" disabled={enCours} onClick={enregistrer}
          className="w-full py-2.5 rounded-xl text-sm font-bold text-white disabled:opacity-50" style={{ background: TEAL }}>
          {enCours ? 'Enregistrement…' : 'Ajouter à l’agenda'}
        </button>
      </div>
    </Cadre>
  );
}

export function ValiderRdvVetoModal({ tache, faitPar, faitParProfil, onClose, onDone }: {
  tache: TacheRdvVeto; faitPar: string; faitParProfil: string | null; onClose: () => void; onDone: () => void;
}) {
  const ids = useMemo(() => (tache.animaux_ids?.length ? tache.animaux_ids : tache.animal_id ? [tache.animal_id] : []).map(String), [tache]);
  const [animaux, setAnimaux] = useState<{ id: string; nom: string }[] | null>(null);
  const [coches, setCoches] = useState<Set<string>>(new Set(ids));
  const j = aujourdhuiLocal();
  const prevu = tache.date.slice(0, 10);
  const [date, setDate] = useState(prevu <= j ? prevu : j);
  const [erreur, setErreur] = useState('');
  const [enCours, setEnCours] = useState(false);

  useEffect(() => {
    if (!ids.length) { setAnimaux([]); return; }
    supabase.from('animaux').select('id, nom').in('id', ids).then(({ data }) => {
      const noms = new Map(((data ?? []) as { id: string; nom: string | null }[]).map(a => [String(a.id), a.nom ?? 'Animal']));
      setAnimaux(ids.map(id => ({ id, nom: noms.get(id) ?? 'Animal' })));
    });
  }, [ids]);

  async function valider() {
    setEnCours(true); setErreur('');
    const e = await validerRdvVeto(tache, date, (animaux ?? []).filter(a => coches.has(a.id)), faitPar, faitParProfil);
    setEnCours(false);
    if (e) setErreur(e); else onDone();
  }

  return (
    <Cadre titre="Valider le RDV vétérinaire" onClose={onClose}>
      <div className="space-y-3">
        <p className="text-sm text-[#1F2A2E]"><strong>{tache.rdv_veto_cabinet}</strong>{tache.rdv_veto_motif ? ` · ${tache.rdv_veto_motif}` : ''}</p>
        <div>
          <label htmlFor="rv-date-reelle" className={etiquette}>Date réelle de la visite</label>
          <input id="rv-date-reelle" type="date" max={j} value={date} onChange={e => setDate(e.target.value)} className={champ} />
        </div>
        <div>
          <p className={etiquette}>Animaux vus ({coches.size})</p>
          {animaux === null ? <p className="text-xs text-gray-400">Chargement…</p> : (
            <div className="border border-gray-100 rounded-xl max-h-52 overflow-y-auto p-1">
              {animaux.map(a => (
                <label key={a.id} className="flex items-center gap-2 px-2 py-1.5 text-sm rounded-lg hover:bg-gray-50 cursor-pointer">
                  <input type="checkbox" checked={coches.has(a.id)} onChange={() => setCoches(p => { const n = new Set(p); if (n.has(a.id)) n.delete(a.id); else n.add(a.id); return n; })} />
                  <span className="truncate">{a.nom}</span>
                </label>
              ))}
            </div>
          )}
        </div>
        <p className="text-xs text-gray-500">Une visite vétérinaire est ajoutée au carnet de chaque animal coché et au registre sanitaire.</p>
        {erreur && <p role="alert" className="text-xs text-red-600">{erreur}</p>}
        <button type="button" disabled={enCours || animaux === null} onClick={valider}
          className="w-full py-2.5 rounded-xl text-sm font-bold text-white disabled:opacity-50" style={{ background: TEAL }}>
          {enCours ? 'Validation…' : `Valider pour ${coches.size} ${coches.size > 1 ? 'animaux' : 'animal'}`}
        </button>
      </div>
    </Cadre>
  );
}
