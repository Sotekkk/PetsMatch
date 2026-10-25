'use client';
import {
  type CalculRation, type PlanAlimentation, LIBELLES_REPARTITION, LIBELLES_TYPE_ALIMENT,
  calculEnregistre, formatQuantite, libellesRepas, nomAliment, planDepuisLigne, profilEspece,
} from '@/lib/plan-alimentation';

/** Synthèse d'un plan d'alimentation : type, repas, quantités, aliments
 *  (marque + gamme), consignes. Lecture seule — utilisée telle quelle par la
 *  pension, le pet-sitter, le vétérinaire et la page de partage, et dans
 *  l'onglet du propriétaire. Miroir de plan_alimentation_lecture.dart (appli). */
export default function PlanAlimentationLecture({ plan, calcul, espece, consignes = '', vuePro = false, nomAnimal = '', large = false }: {
  plan: PlanAlimentation; calcul: CalculRation; espece: string; consignes?: string;
  vuePro?: boolean; nomAnimal?: string;
  /** Mise en page large (site) : repas et aliments en grille. */
  large?: boolean;
}) {
  const profil = profilEspece(espece);
  const kg = profil.uniteKg;
  const labels = libellesRepas(plan.repas.length);
  const types: string[] = [];
  plan.aliments.forEach(a => { const t = LIBELLES_TYPE_ALIMENT[a.type] ?? a.type; if (!types.includes(t)) types.push(t); });
  const typeTxt = `${plan.aliments.length > 1 ? 'Mixte : ' : ''}${types.join(' + ')}`;
  let energie: string | null = null;
  if (profil.methode === 'energie') {
    energie = calcul.kcalServies != null
      ? calcul.kcalEstimees.length
        ? `≈ ${Math.round(calcul.kcalServies)} kcal/jour (estimation pour ${calcul.kcalEstimees.join(', ')})`
        : `${Math.round(calcul.kcalServies)} kcal/jour`
      : calcul.sansKcal.length ? `Non calculable (${calcul.sansKcal.join(', ')} sans valeur énergétique)` : null;
  }
  const aVolonte = plan.aliments.filter((_, i) => calcul.alimentLibre[i]).map(nomAliment);
  const totalTxt = calcul.totalG > 0
    ? `${formatQuantite(calcul.totalG, kg)}/jour${aVolonte.length ? ` + ${aVolonte.join(', ')} à volonté` : ''}`
    : aVolonte.length ? `${aVolonte.join(', ')} à volonté` : 'non renseignée';

  const carte = 'bg-white border border-gray-300 rounded-xl';
  const titre = 'text-[16px] font-extrabold text-[#1F2A2E] mt-5 mb-2';
  const grille = large ? 'grid gap-3 sm:grid-cols-2' : 'flex flex-col gap-2.5';

  return (
    <div className="text-[#1F2A2E]">
      {vuePro && (
        <div className="mb-3 p-3 rounded-[10px] bg-[#E8F0F2] border border-[#B9CDD3] text-[14px]">
          <b>Lecture seule.</b> Consignes renseignées par le propriétaire{nomAnimal ? ` de ${nomAnimal}` : ''}.
        </div>
      )}
      <div className={`${carte} ${large ? 'grid sm:grid-cols-2 lg:grid-cols-4 divide-y sm:divide-y-0 sm:divide-x divide-gray-200' : 'divide-y divide-gray-200'}`}>
        {[['Type', typeTxt], ['Repas', `${plan.repas.length} repas par jour`], ['Quantité totale', totalTxt], ...(energie ? [['Énergie servie', energie]] : [])].map(([l, v]) => (
          large ? (
            <div key={l} className="px-4 py-3"><p className="text-[13px] text-gray-600">{l}</p><p className="text-[15px] font-bold">{v}</p></div>
          ) : (
            <div key={l} className="flex justify-between gap-3 px-4 py-3 text-[15px]">
              <span className="text-gray-600">{l}</span><span className="font-bold text-right">{v}</span>
            </div>
          )
        ))}
      </div>

      <h3 className={titre}>Aliments</h3>
      <div className={grille}>
        {plan.aliments.map((a, i) => (
          <div key={i} className={`${carte} px-4 py-3 text-[15px]`}>
            <p><span className="text-gray-600">Marque : </span><b>{a.marque}</b></p>
            {a.gamme.trim() && <p><span className="text-gray-600">Gamme : </span><b>{a.gamme}</b></p>}
            <p className="text-[13px] text-gray-600">{LIBELLES_TYPE_ALIMENT[a.type] ?? a.type}</p>
            {a.repartition && (
              <p className="text-[13px] text-gray-600">
                Composition : {Object.entries(a.repartition).map(([k, v]) => `${LIBELLES_REPARTITION[k] ?? k} ${Math.round(v)} %`).join(' · ')}
              </p>
            )}
          </div>
        ))}
      </div>

      <h3 className={titre}>Détail par repas</h3>
      <div className={grille}>
        {plan.repas.map((r, i) => (
          <div key={i} className={`${carte} px-4 py-3`}>
            <div className="flex justify-between items-baseline gap-2">
              <b className="text-[15.5px]">{labels[i]}</b>
              {r.heure && <span className="text-[14px] text-gray-600">{r.heure.replace(':', ' h ')}</span>}
            </div>
            {calcul.lignes[i].map((x, j) => {
              const a = plan.aliments[x.a];
              return (
                <div key={j} className="mt-1.5">
                  <div className="flex justify-between gap-3 text-[15px]">
                    <span>{nomAliment(a)}</span>
                    <b className="text-[#0C5C6C] whitespace-nowrap">
                      {x.libre ? 'à volonté' : x.eff != null ? formatQuantite(x.eff, kg) : 'non précisée'}
                    </b>
                  </div>
                  {a.repartition && x.eff != null && (
                    <p className="text-[13px] text-gray-600">
                      {Object.entries(a.repartition).map(([k, v]) => `${LIBELLES_REPARTITION[k] ?? k} ${formatQuantite(x.eff! * v / 100)}`).join(' · ')}
                    </p>
                  )}
                </div>
              );
            })}
          </div>
        ))}
      </div>

      {plan.aliments.length > 1 && (
        <>
          <h3 className={titre}>Total par aliment</h3>
          <div className={`${carte} divide-y divide-gray-200`}>
            {plan.aliments.map((a, i) => (
              <div key={i} className="flex justify-between gap-3 px-4 py-2.5 text-[15px]">
                <span>{nomAliment(a)}</span>
                <b className="whitespace-nowrap">{calcul.alimentLibre[i] ? 'à volonté' : `${formatQuantite(calcul.totalParAliment[i], kg)}/jour`}</b>
              </div>
            ))}
          </div>
        </>
      )}

      <h3 className={titre}>Consignes alimentaires</h3>
      <div className={`${carte} px-4 py-3 text-[15px] whitespace-pre-line`}>
        {consignes.trim() || 'Aucune consigne particulière.'}
      </div>
    </div>
  );
}

/** Plan enregistré d'une ligne `alimentations`, sans recalcul (pros). */
export function PlanAlimentationDepuisLigne({ row, espece, vuePro = true, nomAnimal = '', large = false, vide = 'Plan d’alimentation non renseigné par le propriétaire.' }: {
  row: Record<string, unknown> | null | undefined; espece: string; vuePro?: boolean; nomAnimal?: string; large?: boolean; vide?: string;
}) {
  const plan = planDepuisLigne(row, espece);
  if (!plan) return <p className="text-sm text-gray-500 py-2">{vide}</p>;
  return (
    <PlanAlimentationLecture plan={plan} calcul={calculEnregistre(plan)} espece={espece}
      consignes={String(row?.consignes ?? '')} vuePro={vuePro} nomAnimal={nomAnimal} large={large} />
  );
}
