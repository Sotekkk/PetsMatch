'use client';
import { useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { auth } from '@/lib/firebase';
import {
  type AlimentPlan, CHAMPS_COMPOSITION, LIBELLES_REPARTITION, LIBELLES_TYPE_ALIMENT, REPARTITION_BARF, REPARTITION_MENAGERE,
  evaluerEnergie, lireNombre, profilEspece, typeVersCatalogue,
} from '@/lib/plan-alimentation';

const chip = (on: boolean) =>
  `h-10 px-3.5 rounded-full border text-sm font-bold transition-colors ${on ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white' : 'bg-white border-gray-300 text-[#1F2A2E] hover:border-[#0C5C6C]'}`;
const input = 'w-full h-11 px-3 rounded-[10px] border border-gray-300 bg-white text-[15px] outline-none focus:border-[#0C5C6C] focus:ring-1 focus:ring-[#0C5C6C]';

/** « Mon aliment n'est pas dans la liste » : saisie progressive (marque et
 *  nom, puis type / stade, puis énergie pour le chien et le chat). Un aliment
 *  du commerce rejoint le catalogue (visible des autres membres) ; une
 *  préparation maison ou un aliment sans marque reste propre à l'animal.
 *  Miroir de ajout_aliment_plan_page.dart (appli). */
export default function AjoutAlimentModal({ espece, typeInitial, types: typesPlan = [], marqueInitiale = '', onCreated, onClose }: {
  espece: string; typeInitial?: string; marqueInitiale?: string;
  /** Types proposés : ceux choisis à l'étape 1 (pas de croquettes pour un
   *  plan BARF ou ration ménagère). Tous les types de l'espèce si vide. */
  types?: string[];
  onCreated: (a: AlimentPlan) => void; onClose: () => void;
}) {
  const profil = profilEspece(espece);
  const energie = profil.methode === 'energie';
  const libSansMarque = energie ? 'Préparation maison' : 'Sans marque';
  const [marque, setMarque] = useState(marqueInitiale);
  const [nom, setNom] = useState('');
  const typesFiltres = profil.types.filter(t => !typesPlan.length || typesPlan.includes(t));
  const types = typesFiltres.length ? typesFiltres : profil.types;
  const [type, setType] = useState(typeInitial && types.includes(typeInitial) ? typeInitial : types[0]);
  const [especeAliment, setEspeceAliment] = useState(espece);
  const [stade, setStade] = useState('adulte');
  const [methode, setMethode] = useState('');
  const [kcal, setKcal] = useState('');
  const [unite, setUnite] = useState<'100g' | 'kg'>('100g');
  const [compo, setCompo] = useState<Record<string, string>>({});
  const [repartition, setRepartition] = useState<Record<string, string>>({});
  const [table, setTable] = useState<{ age: string; poids: string; g: string }[]>([{ age: '', poids: '', g: '' }]);
  const [warnOk, setWarnOk] = useState(false);
  const [matiereSeche, setMatiereSeche] = useState(false);
  const [saving, setSaving] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  const prive = marque.trim() === libSansMarque;
  const repere = type === 'barf' ? REPARTITION_BARF : type === 'menagere' ? REPARTITION_MENAGERE : null;
  const ev = useMemo(() => evaluerEnergie({ methode, type, kcalTexte: kcal, unite, compo, surMatiereSeche: matiereSeche }),
    [methode, type, kcal, unite, compo, matiereSeche]);
  const identiteOk = !!(marque.trim() && nom.trim());
  const toucher = () => { setErreur(null); setWarnOk(false); };

  function preremplir(t: string, estPrive: boolean) {
    const r = t === 'barf' ? REPARTITION_BARF : t === 'menagere' ? REPARTITION_MENAGERE : null;
    if (!r || !estPrive) return;
    setRepartition(prev => {
      const n = { ...prev };
      Object.entries(r).forEach(([k, v]) => { if (!n[k]) n[k] = String(v); });
      return n;
    });
  }

  function lireRepartition(): [Record<string, number> | null, string | null] {
    if (!repere) return [null, null];
    const vals: Record<string, number> = {};
    for (const k of Object.keys(repere)) {
      const l = lireNombre(repartition[k], true);
      if (l.err) return [null, `Composition : ${l.err}`];
      if (l.v != null) vals[k] = l.v;
    }
    if (!Object.keys(vals).length) return [null, null];
    const s = Object.values(vals).reduce((a, b) => a + b, 0);
    if (Math.abs(s - 100) > 1) return [null, `Composition : la somme fait ${Math.round(s)} % au lieu de 100 %.`];
    return [vals, null];
  }

  async function enregistrer() {
    const m = marque.trim(), n = nom.trim();
    if (!m || !n) return setErreur('Indiquez la marque et le nom de l’aliment.');
    if (energie) {
      if (!methode) return setErreur('Choisissez comment renseigner la valeur énergétique.');
      if (ev.err) return setErreur(ev.err);
      if (Object.keys(ev.erreursChamps).length) return setErreur('Corrigez les valeurs signalées en rouge.');
      if (!ev.ok) return setErreur(methode === 'A' ? 'Indiquez la valeur énergétique.' : 'Complétez la composition analytique.');
      if (ev.warn && !warnOk) return setErreur('Confirmez la valeur énergétique signalée ci-dessus.');
    }
    const [rep, errRep] = prive ? lireRepartition() : [null, null];
    if (errRep) return setErreur(errRep);
    const tableau: Record<string, number>[] = [];
    if (energie && stade === 'croissance') {
      for (const r of table) {
        if (!r.age.trim() && !r.poids.trim() && !r.g.trim()) continue;
        const age = lireNombre(r.age), pa = lireNombre(r.poids), g = lireNombre(r.g);
        const err = age.err ?? pa.err ?? g.err;
        if (err) return setErreur(`Tableau de rationnement : ${err}`);
        if (age.v == null || g.v == null) return setErreur('Tableau de rationnement : chaque ligne demande au moins l’âge et la quantité.');
        tableau.push({ age_mois: age.v, ...(pa.v != null ? { poids_adulte_kg: pa.v } : {}), g_jour: g.v });
      }
    }
    const aliment: AlimentPlan = {
      marque: m, gamme: n, type,
      kcal: energie && methode !== 'C' ? ev.kcal ?? null : null,
      source: !energie || methode === 'C' ? null : (ev.estime ? 'composition' : 'fabricant'),
      repartition: rep, tableauCroissance: tableau,
    };
    if (prive) { onCreated(aliment); return; }
    setSaving(true); setErreur(null);
    try {
      const { data: existant } = await supabase.from('marques_aliments').select('id')
        .eq('espece', especeAliment).ilike('marque', m).ilike('gamme', n).eq('type_aliment', typeVersCatalogue(type)).limit(1);
      if (existant && existant.length) { setErreur('Cet aliment existe déjà dans le catalogue : sélectionnez-le dans la liste.'); return; }
      const { data, error } = await supabase.from('marques_aliments').insert({
        marque: m, gamme: n, espece: especeAliment, type_aliment: typeVersCatalogue(type),
        age_categorie: stade === 'croissance' ? 'junior' : stade,
        densite_kcal_100g: aliment.kcal ?? null,
        kcal_estime: aliment.source === 'composition',
        kcal_source: aliment.source ?? null,
        ...(methode === 'B' ? { composition: ev.composition } : {}),
        ...(tableau.length ? { tableau_croissance: tableau } : {}),
        doses: [], notes: 'Ajouté par un membre',
        ajoute_par_uid: auth.currentUser?.uid ?? null,
      }).select('id').single();
      if (error || !data) {
        setErreur(error?.code === '23505' || error?.code === '23514' ? error.message
          : error?.code === 'PGRST204' ? 'Enregistrement impossible : la base de données doit être mise à jour (migration alimentation).'
          : 'Enregistrement impossible, réessayez.');
        return;
      }
      onCreated({ ...aliment, id: String(data.id) });
    } finally { setSaving(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-white w-full max-w-2xl rounded-t-2xl sm:rounded-2xl max-h-[90vh] flex flex-col" onClick={e => e.stopPropagation()}>
        <div className="px-5 pt-5 pb-3 border-b border-gray-100">
          <h2 className="text-[19px] font-extrabold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Ajouter mon aliment</h2>
        </div>
        <div className="overflow-y-auto flex-1 px-5 py-4 space-y-4 text-[15px] text-[#1F2A2E]">
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block">
              <span className="block text-sm font-bold mb-1">Marque</span>
              <input value={marque} onChange={e => { setMarque(e.target.value); toucher(); }}
                placeholder={energie ? 'Ex. Easy BARF, Josera…' : 'Ex. Cavalor, Versele-Laga…'} className={input} />
              <button type="button" onClick={() => { setMarque(libSansMarque); preremplir(type, true); toucher(); }}
                className="mt-2 h-9 px-3 rounded-full border border-gray-300 text-[13px] font-bold text-[#0C5C6C] hover:border-[#0C5C6C]">
                {libSansMarque}
              </button>
            </label>
            <label className="block">
              <span className="block text-sm font-bold mb-1">Nom de l&apos;aliment ou de la recette</span>
              <input value={nom} onChange={e => { setNom(e.target.value); toucher(); }}
                placeholder={energie ? 'Ex. Bœuf menu complet' : 'Ex. Foin de prairie, Sport Mix…'} className={input} />
            </label>
          </div>
          <div>
            <p className="text-sm font-bold mb-2">Type</p>
            <div className="flex flex-wrap gap-2">
              {types.map(t => (
                <button key={t} type="button" className={chip(type === t)}
                  onClick={() => { setType(t); preremplir(t, prive); toucher(); }}>{LIBELLES_TYPE_ALIMENT[t]}</button>
              ))}
            </div>
          </div>
          {energie && (
            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <p className="text-sm font-bold mb-2">Espèce</p>
                <div className="flex flex-wrap gap-2">
                  {[['chien', 'Chien'], ['chat', 'Chat']].map(([v, l]) => (
                    <button key={v} type="button" className={chip(especeAliment === v)} onClick={() => setEspeceAliment(v)}>{l}</button>
                  ))}
                </div>
              </div>
              <div>
                <p className="text-sm font-bold mb-2">Stade de vie</p>
                <div className="flex flex-wrap gap-2">
                  {[['croissance', 'Croissance'], ['adulte', 'Adulte'], ['senior', 'Senior'], ['tous', 'Tous âges']].map(([v, l]) => (
                    <button key={v} type="button" className={chip(stade === v)} onClick={() => setStade(v)}>{l}</button>
                  ))}
                </div>
              </div>
            </div>
          )}
          {repere && prive && (
            <div>
              <p className="text-sm font-bold">Composition de votre préparation (facultatif)</p>
              <p className="text-[13px] text-gray-600 mb-2">Détaillée en grammes à chaque repas. Repère proposé, à adapter à votre recette.</p>
              <div className="grid gap-2 sm:grid-cols-2">
                {Object.keys(repere).map(k => (
                  <label key={k} className="flex items-center justify-between gap-3">
                    <span className="text-sm">{LIBELLES_REPARTITION[k]}</span>
                    <span className="flex h-10 w-28 rounded-[10px] border border-gray-300 overflow-hidden">
                      <input inputMode="decimal" value={repartition[k] ?? ''} onChange={e => { setRepartition(r => ({ ...r, [k]: e.target.value })); toucher(); }}
                        className="flex-1 min-w-0 px-2 outline-none font-bold" aria-label={LIBELLES_REPARTITION[k]} />
                      <span className="px-2 flex items-center bg-gray-100 border-l border-gray-300 text-sm">%</span>
                    </span>
                  </label>
                ))}
              </div>
            </div>
          )}
          {energie && identiteOk && (
            <div className="space-y-3">
              <p className="text-[16px] font-extrabold">Valeur énergétique</p>
              <div className="grid gap-2 sm:grid-cols-3">
                {[['A', 'Je connais les kcal', 'Indiquées sur l’emballage, pour 100 g ou pour 1 kg'],
                  ['B', 'J’ai la composition analytique', 'Protéines, matières grasses, fibres, cendres, humidité'],
                  ['C', 'Je n’ai aucune information', 'Je saisirai les grammes moi-même']].map(([c, t, s]) => (
                  <button key={c} type="button" onClick={() => { setMethode(c); toucher(); }}
                    className={`text-left p-3 rounded-xl border-2 ${methode === c ? 'border-[#0C5C6C] bg-[#E8F0F2]' : 'border-gray-200 bg-white hover:border-[#0C5C6C]/40'}`}>
                    <b className="block text-[14.5px]">{t}</b><span className="text-[13px] text-gray-600">{s}</span>
                  </button>
                ))}
              </div>
              {methode === 'A' && (
                <div className="max-w-sm">
                  <div className="flex h-12 rounded-[10px] border border-gray-300 overflow-hidden">
                    <input inputMode="decimal" value={kcal} onChange={e => { setKcal(e.target.value); toucher(); }} aria-label="Valeur énergétique"
                      placeholder={unite === 'kg' ? 'Ex. 3700' : 'Ex. 370'} className="flex-1 min-w-0 px-3 outline-none text-base font-bold" />
                    {(['100g', 'kg'] as const).map(u => (
                      <button key={u} type="button" onClick={() => { setUnite(u); toucher(); }}
                        className={`px-3 border-l border-gray-300 text-[13px] font-extrabold ${unite === u ? 'bg-[#0C5C6C] text-white' : 'bg-gray-100 text-gray-700'}`}>
                        {u === 'kg' ? 'kcal/kg' : 'kcal/100 g'}
                      </button>
                    ))}
                  </div>
                </div>
              )}
              {methode === 'B' && (
                <div>
                  <p className="text-[14px] text-gray-700 mb-2">Recopiez la « composition analytique » de l&apos;emballage (pas le tableau des quantités par poids). Les glucides sont facultatifs : ils sont estimés par différence.</p>
                  <label className="flex items-start gap-2 mb-3 min-h-[44px]">
                    <input type="checkbox" checked={matiereSeche} onChange={e => { setMatiereSeche(e.target.checked); toucher(); }} className="w-5 h-5 mt-0.5" />
                    <span><b className="text-[14px]">Valeurs données sur matière sèche</b><br />
                      <span className="text-[13px] text-gray-600">Cochez si les pourcentages font 100 % sans l&apos;humidité (ex. « *Teneur en humidité : 66 % » à part).</span></span>
                  </label>
                  <div className="grid gap-x-6 gap-y-2 sm:grid-cols-2">
                    {CHAMPS_COMPOSITION.map(([k, l]) => (
                      <div key={k}>
                        <label className="flex items-center justify-between gap-3">
                          <span className="text-sm">{l}</span>
                          <span className={`flex h-10 w-28 rounded-[10px] border overflow-hidden ${ev.erreursChamps[k] ? 'border-red-600' : 'border-gray-300'}`}>
                            <input inputMode="decimal" value={compo[k] ?? ''} onChange={e => { setCompo(c => ({ ...c, [k]: e.target.value })); toucher(); }}
                              className="flex-1 min-w-0 px-2 outline-none font-bold" aria-label={l} />
                            <span className="px-2 flex items-center bg-gray-100 border-l border-gray-300 text-sm">%</span>
                          </span>
                        </label>
                        {ev.erreursChamps[k] && <p className="text-[13px] text-red-700 text-right">{ev.erreursChamps[k]}</p>}
                      </div>
                    ))}
                  </div>
                </div>
              )}
              {methode === 'C' && (
                <p className="p-3 rounded-[10px] bg-gray-100 text-[14px]">Valeur énergétique non renseignée — ration personnalisée. Vous indiquerez les grammes vous-même ; vous pourrez compléter plus tard.</p>
              )}
              {ev.info && <p className="p-3 rounded-[10px] bg-[#E8F0F2] text-[14px]">{ev.info}</p>}
              {ev.err && <p className="p-3 rounded-[10px] bg-red-50 text-red-800 text-[14px]">{ev.err}</p>}
              {ev.warn && (
                <div className="p-3 rounded-[10px] bg-[#FFF4E0] border border-[#E9C27A] text-[14px] space-y-2">
                  <p>{ev.warn}</p>
                  <label className="flex items-center gap-2 font-bold min-h-[44px]">
                    <input type="checkbox" checked={warnOk} onChange={e => { setWarnOk(e.target.checked); setErreur(null); }} className="w-5 h-5" />
                    La valeur est bien celle de l&apos;emballage
                  </label>
                </div>
              )}
              {stade === 'croissance' && methode && (
                <div className="p-3 rounded-xl border border-gray-200 space-y-2">
                  <p className="font-bold">Tableau de rationnement du fabricant (facultatif)</p>
                  <p className="text-[13px] text-gray-600">Recopiez seulement les colonnes présentes sur l&apos;emballage. Il sert à afficher la recommandation du fabricant ; il n&apos;est pas converti en kcal.</p>
                  <div className="grid grid-cols-3 gap-2 text-[13px] font-extrabold text-gray-700"><span>Âge (mois)</span><span>Poids adulte (kg)</span><span>Quantité (g/jour)</span></div>
                  {table.map((r, i) => (
                    <div key={i} className="grid grid-cols-3 gap-2">
                      {(['age', 'poids', 'g'] as const).map(c => (
                        <input key={c} inputMode="decimal" value={r[c]} aria-label={c === 'age' ? 'Âge en mois' : c === 'poids' ? 'Poids adulte en kg' : 'Quantité en grammes par jour'}
                          onChange={e => setTable(t => t.map((x, j) => (j === i ? { ...x, [c]: e.target.value } : x)))}
                          className="h-10 min-w-0 px-2 rounded-lg border border-gray-300 outline-none" />
                      ))}
                    </div>
                  ))}
                  <button type="button" onClick={() => setTable(t => [...t, { age: '', poids: '', g: '' }])}
                    className="h-10 text-[#0C5C6C] font-extrabold">+ Ajouter une ligne</button>
                </div>
              )}
            </div>
          )}
          {!prive && identiteOk && (
            <p className="text-[13px] text-gray-600">L&apos;aliment rejoindra le catalogue PetsMatch, visible des autres membres (« ajouté par un membre »).</p>
          )}
          {erreur && <p className="text-[14px] font-bold text-red-700">{erreur}</p>}
        </div>
        <div className="p-4 border-t border-gray-100 flex gap-3">
          <button type="button" onClick={onClose} className="flex-1 h-12 rounded-[10px] border border-gray-300 font-bold">Annuler</button>
          <button type="button" onClick={enregistrer} disabled={saving}
            className="flex-[2] h-12 rounded-[10px] bg-[#0C5C6C] text-white font-extrabold disabled:opacity-50">
            {saving ? 'Enregistrement…' : 'Ajouter et sélectionner'}
          </button>
        </div>
      </div>
    </div>
  );
}
