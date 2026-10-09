'use client';

// Briques communes des tableaux de bord pro (vétérinaire, ostéopathe…) :
// carte indicateur, carte de section, badge, photo d'animal, anneau de
// répartition, barres de la semaine. Le contenu reste propre à chaque métier
// (VetDashboard.tsx, SanteDashboard.tsx). Miroir appli :
// lib/widgets/dashboard/dashboard_kit.dart.

import { useState } from 'react';
import Link from 'next/link';

export const TEAL = '#0C5C6C';
/** Palette catégorielle validée daltonisme (ordre fixe, jamais cyclée). */
export const PALETTE = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300'];

export function Kpi({ valeur, label, icone, href, onClick, teinte = TEAL, actif = false }: {
  valeur: number; label: string; icone: React.ReactNode; href?: string; onClick?: () => void; teinte?: string; actif?: boolean;
}) {
  const contenu = (
    <>
      <div className="flex items-center">
        <span className="w-9 h-9 rounded-xl flex items-center justify-center" style={{ background: `${teinte}1F`, color: teinte }} aria-hidden>{icone}</span>
        <span className="ml-auto text-gray-400">›</span>
      </div>
      <p className="text-3xl font-extrabold text-[#1E2025] leading-tight mt-1">{valeur}</p>
      <p className="text-xs text-gray-500">{label}</p>
    </>
  );
  const cls = 'bg-white rounded-2xl p-4 hover:shadow-md transition-shadow flex flex-col gap-1 text-left w-full';
  const style = { border: actif ? `1.5px solid ${teinte}` : '1px solid #E4E7E2' };
  return href
    ? <Link href={href} className={cls} style={style}>{contenu}</Link>
    : <button type="button" onClick={onClick} className={cls} style={style}>{contenu}</button>;
}

export function Section({ titre, icone, compteur, action, children, className = '' }: {
  titre: string; icone?: React.ReactNode; compteur?: number; action?: React.ReactNode; children: React.ReactNode; className?: string;
}) {
  return (
    <section className={`bg-white rounded-2xl border border-[#E4E7E2] p-4 ${className}`}>
      <div className="flex items-center gap-2 mb-2">
        {icone && <span className="text-[#0C5C6C] flex-shrink-0" aria-hidden>{icone}</span>}
        <h2 className="font-bold text-base text-[#1E2025]">{titre}</h2>
        {!!compteur && <span className="min-w-[18px] h-[18px] px-1 rounded-full bg-red-600 text-white text-[10px] font-bold flex items-center justify-center">{compteur}</span>}
        <span className="flex-1" />
        {action}
      </div>
      {children}
    </section>
  );
}

export function Badge({ texte, fg, bg }: { texte: string; fg: string; bg: string }) {
  return <span className="text-[11px] font-bold px-2 py-0.5 rounded-full whitespace-nowrap" style={{ color: fg, background: bg }}>{texte}</span>;
}

export function PhotoAnimal({ url, taille = 38 }: { url?: string | null; taille?: number }) {
  return (
    <div className="rounded-full overflow-hidden flex-shrink-0 flex items-center justify-center bg-[#E6F2F3]" style={{ width: taille, height: taille }}>
      {url
        // eslint-disable-next-line @next/next/no-img-element
        ? <img src={url} alt="" className="w-full h-full object-cover" />
        : <svg width={taille * 0.45} height={taille * 0.45} viewBox="0 0 24 24" fill={TEAL} aria-hidden><circle cx="6" cy="9" r="2.2" /><circle cx="10" cy="5" r="2.2" /><circle cx="14" cy="5" r="2.2" /><circle cx="18" cy="9" r="2.2" /><path d="M12 11c-3 0-6 4-6 7 0 1.5 1.5 2 3 2 1.2 0 2-.6 3-.6s1.8.6 3 .6c1.5 0 3-.5 3-2 0-3-3-7-6-7z" /></svg>}
    </div>
  );
}

export interface Segment { key: string; label: string; color: string; n: number }

/** Anneau + légende (libellé, nombre, %) ; survol = segment en avant. */
export function Donut({ segments, libelleCentre = 'RDV' }: { segments: Segment[]; libelleCentre?: string }) {
  const [actif, setActif] = useState<string | null>(null);
  const segs = segments.filter(s => s.n > 0);
  const total = segs.reduce((a, s) => a + s.n, 0);
  const R = 60, EP = 20, C = 2 * Math.PI * R;
  const ecart = segs.length > 1 ? 2 : 0;
  const decalages = segs.map((_, i) => segs.slice(0, i).reduce((a, x) => a + (x.n / total) * C, 0));
  const seg = segs.find(s => s.key === actif);
  return (
    <div className="flex flex-col sm:flex-row items-center gap-5">
      <svg viewBox="0 0 160 160" width={160} height={160} role="img" aria-label="Répartition" className="flex-shrink-0">
        <g transform="rotate(-90 80 80)">
          {segs.map((s, i) => (
            <circle key={s.key} cx={80} cy={80} r={R} fill="none" stroke={s.color}
              strokeWidth={actif === s.key ? EP + 6 : EP}
              strokeDasharray={`${Math.max(0.5, (s.n / total) * C - ecart)} ${C}`} strokeDashoffset={-decalages[i]}
              opacity={actif && actif !== s.key ? 0.35 : 1}
              onMouseEnter={() => setActif(s.key)} onMouseLeave={() => setActif(null)}
              style={{ cursor: 'pointer', transition: 'opacity .15s' }}>
              <title>{`${s.label} : ${s.n} (${Math.round(s.n * 100 / total)} %)`}</title>
            </circle>
          ))}
        </g>
        <text x={80} y={78} textAnchor="middle" fontSize={24} fontWeight={800} fill="#1E2025">{seg?.n ?? total}</text>
        <text x={80} y={96} textAnchor="middle" fontSize={11} fill="#6B7280">{(seg?.label ?? libelleCentre).slice(0, 18)}</text>
      </svg>
      <table className="w-full text-sm">
        <tbody>
          {segs.map(s => (
            <tr key={s.key} onMouseEnter={() => setActif(s.key)} onMouseLeave={() => setActif(null)}
              className={actif === s.key ? 'font-extrabold' : ''}>
              <td className="py-1 pr-2 w-4"><span className="inline-block w-2.5 h-2.5 rounded-[3px] align-middle" style={{ background: s.color }} /></td>
              <td className="py-1 text-[#1E2025]">{s.label}</td>
              <td className="py-1 text-right font-bold text-[#1E2025]">{s.n}</td>
              <td className="py-1 pl-3 text-right text-gray-500 w-14">{Math.round(s.n * 100 / total)} %</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

const JOURS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const JOURS_LONGS = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

/** Barres par jour, empilées si plusieurs séries ([série][jour], 2 px
 *  d'écart) ; valeur sur aujourd'hui / au survol ; légende si plusieurs séries. */
export function BarresSemaine({ series, couleurs, libelles = [], aujourdhui }: {
  series: number[][]; couleurs: string[]; libelles?: string[]; aujourdhui: number;
}) {
  const [survol, setSurvol] = useState<number | null>(null);
  const total = (j: number) => series.reduce((a, s) => a + s[j], 0);
  const max = Math.max(0, ...JOURS.map((_, j) => total(j)));
  const unique = series.length === 1;
  return (
    <div>
      <div className="flex items-end gap-2 h-40">
        {JOURS.map((jour, j) => {
          const fort = j === aujourdhui || j === survol;
          return (
            <div key={j} className="flex-1 h-full flex flex-col items-center justify-end"
              onMouseEnter={() => setSurvol(j)} onMouseLeave={() => setSurvol(null)}
              title={`${JOURS_LONGS[j]} : ${series.map((s, i) => `${libelles[i] ?? 'RDV'} ${s[j]}`).join(' · ')}`}>
              <span className={`text-xs font-bold text-[#1E2025] mb-1 ${fort ? '' : 'invisible'}`}>{total(j)}</span>
              {total(j) === 0
                ? <div className="w-full max-w-[28px] h-[2px] bg-[#E4E7E2]" />
                : (
                  <div className="w-full max-w-[28px] flex flex-col-reverse gap-[2px] rounded-t overflow-hidden">
                    {series.map((s, i) => s[j] > 0 && (
                      <div key={i} style={{
                        height: Math.max(2, (s[j] / max) * 110),
                        background: unique && !fort ? `${couleurs[i]}73` : couleurs[i],
                      }} />
                    ))}
                  </div>
                )}
              <span className={`text-[11px] mt-1.5 ${j === aujourdhui ? 'font-extrabold text-[#1E2025]' : 'text-gray-500'}`}>{jour}</span>
            </div>
          );
        })}
      </div>
      {!unique && libelles.length > 0 && (
        <div className="flex flex-wrap gap-x-4 gap-y-1 mt-2">
          {libelles.map((l, i) => (
            <span key={l} className="flex items-center gap-1.5 text-xs text-[#1E2025]">
              <span className="inline-block w-2.5 h-2.5 rounded-[3px]" style={{ background: couleurs[i] }} />{l}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}
