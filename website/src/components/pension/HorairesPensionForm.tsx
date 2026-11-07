'use client';
// Pension — réglage des horaires d'arrivée / de départ (page Tarifs) :
// plages possibles, durées (premier séjour / habitué / départ, minutes par
// animal en plus), clients au plus par créneau de 15 min. Le client choisit
// son heure à la réservation parmi les créneaux libres.
// Miroir appli : pension_tarifs_page.dart (_horairesSection).
import { HORAIRES_DEFAUT, enMinutes, heureValide, type HorairesPension, type PlageHoraire } from '@/lib/pension-horaires';

/** Plages horaires (arrivées ou départs). */
function Plages({ titre, liste, onChange }: { titre: string; liste: PlageHoraire[]; onChange: (l: PlageHoraire[]) => void }) {
  const champ = 'px-2 py-1.5 border border-gray-200 rounded-lg text-sm font-galey';
  const majPlage = (i: number, p: Partial<PlageHoraire>) => onChange(liste.map((x, j) => (j === i ? { ...x, ...p } : x)));
  return (
    <div>
      <p className="text-xs font-semibold text-gray-600 mb-1">{titre}</p>
      <div className="space-y-1.5">
        {liste.map((p, i) => {
          const invalide = !heureValide(p.debut) || !heureValide(p.fin) || enMinutes(p.debut) >= enMinutes(p.fin);
          return (
            <div key={i} className="flex items-center gap-2">
              <input type="time" step={900} value={p.debut} onChange={e => majPlage(i, { debut: e.target.value })} className={champ} />
              <span className="text-xs text-gray-500">à</span>
              <input type="time" step={900} value={p.fin} onChange={e => majPlage(i, { fin: e.target.value })} className={champ} />
              <button type="button" onClick={() => onChange(liste.filter((_, j) => j !== i))} className="text-xs font-semibold text-[#B3261E]">Retirer</button>
              {invalide && <span className="text-xs text-[#B3261E]">plage invalide</span>}
            </div>
          );
        })}
        <button type="button" onClick={() => onChange([...liste, { debut: '09:00', fin: '10:00' }])}
          className="text-xs font-semibold text-[#0C5C6C]">+ Ajouter une plage</button>
      </div>
    </div>
  );
}

export default function HorairesPensionForm({ value, onChange }: { value: HorairesPension | null; onChange: (h: HorairesPension | null) => void }) {
  const actif = !!value;
  const h = value ?? HORAIRES_DEFAUT;
  const maj = (p: Partial<HorairesPension>) => onChange({ ...h, ...p });
  const champ = 'px-2 py-1.5 border border-gray-200 rounded-lg text-sm font-galey';

  const nombre = (lib: string, cle: keyof HorairesPension, suffixe: string, min = 0, max = 240) => (
    <label className="flex items-center justify-between gap-3 text-sm font-galey text-[#1E2025]">
      <span>{lib}</span>
      <span className="flex items-center gap-1.5">
        <input type="number" min={min} max={max} step={5} value={h[cle] as number}
          onChange={e => maj({ [cle]: Math.min(max, Math.max(min, Number(e.target.value) || 0)) } as Partial<HorairesPension>)}
          className={`${champ} w-20 text-right`} />
        <span className="text-xs text-gray-500 w-14">{suffixe}</span>
      </span>
    </label>
  );

  return (
    <div className={`bg-white rounded-2xl shadow-sm p-4 border ${actif ? 'border-[#6E9E57]/40' : 'border-gray-100'} space-y-3`}>
      <label className="flex items-start gap-3 cursor-pointer">
        <input type="checkbox" className="mt-1" checked={actif} onChange={e => onChange(e.target.checked ? HORAIRES_DEFAUT : null)} />
        <span>
          <span className="block font-galey font-semibold text-sm text-[#1E2025]">Horaires d&apos;arrivée et de départ</span>
          <span className="block font-galey text-xs text-gray-500 mt-0.5">
            À la réservation, le client choisit son heure d&apos;arrivée et de départ parmi les créneaux encore libres. Vous voyez le planning des arrivées et des départs.
          </span>
        </span>
      </label>
      {actif && (
        <>
          <div className="grid sm:grid-cols-2 gap-4">
            <Plages titre="Arrivées possibles" liste={h.arrivees} onChange={l => maj({ arrivees: l })} />
            <Plages titre="Départs possibles" liste={h.departs} onChange={l => maj({ departs: l })} />
          </div>
          <div className="space-y-2 pt-1">
            {nombre('Durée d\'une arrivée — premier séjour', 'duree_arrivee_nouveau', 'min', 5)}
            {nombre('Durée d\'une arrivée — client habitué', 'duree_arrivee_habitue', 'min', 5)}
            {nombre('Durée d\'un départ', 'duree_depart', 'min', 5)}
            {nombre('En plus par animal supplémentaire', 'minutes_par_animal', 'min', 0, 120)}
            {nombre('Clients au plus par créneau de 15 min', 'max_par_creneau', 'clients', 1, 50)}
          </div>
          <p className="text-xs text-gray-500">Arrivées et départs partagent ce maximum. Les durées sont arrondies au quart d&apos;heure. Vous pourrez ajuster l&apos;heure en acceptant chaque séjour.</p>
        </>
      )}
    </div>
  );
}
