'use client';
// Registre sanitaire : compléter depuis les carnets de santé, au choix (par
// défaut les reproducteurs). Pour chaque animal, nombre de soins du carnet
// pas encore au registre (simulation), puis ajout des animaux cochés — sans
// doublon (RPC pm_registre_completer, migration_registre_depuis_carnet.sql).
// Miroir appli : CompleterRegistreSheet (registre_sanitaire.dart).
import { useEffect, useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';

interface AnimalRegistre { id: string; nom: string | null; espece: string | null; reproducteur: boolean | null }

export default function CompleterRegistreModal({ uid, profileId, onClose, onDone }: {
  uid: string; profileId: string | null; onClose: () => void; onDone: (ajoutes: number) => void;
}) {
  const [animaux, setAnimaux] = useState<AnimalRegistre[] | null>(null);
  const [aAjouter, setAAjouter] = useState<Record<string, number>>({});
  const [coches, setCoches] = useState<Set<string>>(new Set());
  const [reproSeuls, setReproSeuls] = useState(true);
  const [enCours, setEnCours] = useState(false);
  const [erreur, setErreur] = useState('');

  useEffect(() => {
    (async () => {
      // Animaux dont le profil est propriétaire (comme « Mes animaux ») — pas
      // seulement ceux nés à l'élevage : un reproducteur acheté y figure.
      let pq = supabase.from('animaux_proprietes').select('animal_id')
        .eq('uid_proprio', uid).eq('statut', 'actif').is('date_fin', null);
      if (profileId) pq = pq.eq('profile_id_proprio', profileId);
      const { data: props } = await pq;
      const ids = [...new Set(((props ?? []) as { animal_id: string }[]).map(p => String(p.animal_id)))];
      const liste: AnimalRegistre[] = [];
      for (let i = 0; i < ids.length; i += 200) {
        const { data } = await supabase.from('animaux').select('id, nom, espece, reproducteur, statut').in('id', ids.slice(i, i + 200));
        liste.push(...((data ?? []) as (AnimalRegistre & { statut?: string | null })[])
          // Toujours à l'élevage (présent, réservé, disponible, en soin…) ; seuls les partis sont écartés.
          .filter(a => !['sorti', 'adopte', 'decede', 'cede', 'vendu'].includes(a.statut ?? '')));
      }
      liste.sort((a, b) => (a.nom ?? '').localeCompare(b.nom ?? '', 'fr'));
      // Soins du carnet pas encore au registre, par animal (simulation, sans écriture).
      const compte: Record<string, number> = {};
      for (let i = 0; i < liste.length; i += 100) {
        const { data: r, error } = await supabase.rpc('pm_registre_completer', { p_animal_ids: liste.slice(i, i + 100).map(a => a.id), p_simuler: true });
        if (error) { setErreur(`Calcul impossible : ${error.message}`); break; }
        for (const x of (r ?? []) as { id_animal: string; nb_a_ajouter: number }[]) compte[x.id_animal] = x.nb_a_ajouter;
      }
      setAnimaux(liste);
      setAAjouter(compte);
      setCoches(new Set(liste.filter(a => a.reproducteur && (compte[a.id] ?? 0) > 0).map(a => a.id)));
    })();
  }, [uid, profileId]);

  const visibles = useMemo(() => (animaux ?? []).filter(a => !reproSeuls || a.reproducteur), [animaux, reproSeuls]);
  const total = [...coches].reduce((t, id) => t + (aAjouter[id] ?? 0), 0);

  function basculer(id: string) {
    setCoches(prev => { const s = new Set(prev); if (s.has(id)) s.delete(id); else s.add(id); return s; });
  }

  async function ajouter() {
    const ids = [...coches].filter(id => (aAjouter[id] ?? 0) > 0);
    if (!ids.length) return;
    setEnCours(true); setErreur('');
    let ajoutes = 0;
    for (let i = 0; i < ids.length; i += 50) {
      const { data, error } = await supabase.rpc('pm_registre_completer', { p_animal_ids: ids.slice(i, i + 50), p_simuler: false });
      if (error) { setErreur(`Ajout interrompu : ${error.message}`); setEnCours(false); return; }
      ajoutes += ((data ?? []) as { nb_a_ajouter: number }[]).reduce((t, x) => t + x.nb_a_ajouter, 0);
    }
    setEnCours(false);
    onDone(ajoutes);
  }

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[85vh] flex flex-col" onClick={e => e.stopPropagation()}>
        <div className="p-5 border-b border-gray-100">
          <h2 className="font-bold text-lg text-[#1F2A2E]">Compléter depuis les carnets</h2>
          <p className="text-xs text-gray-500 mt-1">
            Vaccins, vermifuges, antiparasitaires, traitements et visites déjà notés au carnet de santé, ajoutés au registre.
            Un soin déjà au registre (ou saisi à la main le même jour pour le même produit) n&apos;est pas ajouté une seconde fois.
          </p>
          <label className="flex items-center gap-2 mt-3 text-sm text-gray-700 cursor-pointer">
            <input type="checkbox" checked={reproSeuls} onChange={e => setReproSeuls(e.target.checked)} />
            Reproducteurs seulement
          </label>
        </div>
        <div className="flex-1 overflow-y-auto p-5 space-y-1.5">
          {!animaux ? <p className="text-center text-gray-400 py-8 text-sm">Calcul des soins à ajouter…</p>
            : visibles.length === 0 ? <p className="text-center text-gray-400 py-8 text-sm">Aucun animal.</p>
            : (
              <>
                <div className="flex justify-end gap-3 text-xs font-semibold text-[#0C5C6C] mb-1">
                  <button onClick={() => setCoches(new Set(visibles.filter(a => (aAjouter[a.id] ?? 0) > 0).map(a => a.id)))}>Tout cocher</button>
                  <button onClick={() => setCoches(new Set())}>Tout décocher</button>
                </div>
                {visibles.map(a => {
                  const n = aAjouter[a.id] ?? 0;
                  return (
                    <label key={a.id} className={`flex items-center gap-3 border rounded-xl px-3 py-2 ${n === 0 ? 'opacity-50' : 'cursor-pointer hover:bg-gray-50'}`}>
                      <input type="checkbox" disabled={n === 0} checked={coches.has(a.id)} onChange={() => basculer(a.id)} />
                      <span className="flex-1 min-w-0">
                        <span className="block text-sm font-semibold text-gray-800 truncate">{a.nom || 'Sans nom'}</span>
                        <span className="block text-xs text-gray-500">{a.espece ?? ''}{a.reproducteur ? ' · reproducteur' : ''}</span>
                      </span>
                      <span className="text-xs font-semibold text-gray-600 whitespace-nowrap">
                        {n === 0 ? 'Registre à jour' : `${n} soin${n > 1 ? 's' : ''} à ajouter`}
                      </span>
                    </label>
                  );
                })}
              </>
            )}
          {erreur && <p className="text-sm text-red-600 mt-2">{erreur}</p>}
        </div>
        <div className="p-5 border-t border-gray-100 flex gap-2">
          <button onClick={onClose} className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600">Annuler</button>
          <button onClick={ajouter} disabled={enCours || total === 0}
            className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white bg-[#0C5C6C] disabled:opacity-50">
            {enCours ? 'Ajout en cours…' : total === 0 ? 'Rien à ajouter' : `Ajouter ${total} soin${total > 1 ? 's' : ''} au registre`}
          </button>
        </div>
      </div>
    </div>
  );
}
