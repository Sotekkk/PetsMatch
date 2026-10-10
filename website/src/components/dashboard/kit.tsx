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

export const BORDURE = '#E5E8E6';
export const OMBRE = 'shadow-[0_1px_3px_rgba(16,24,40,0.06)]';

/** Icônes professionnelles au trait (aucun émoji). */
const TRACES: Record<string, React.ReactNode> = {
  patte: <><ellipse cx="12" cy="16.5" rx="4.2" ry="3.4" /><circle cx="6.5" cy="10.5" r="1.8" /><circle cx="9.8" cy="6.5" r="1.8" /><circle cx="14.2" cy="6.5" r="1.8" /><circle cx="17.5" cy="10.5" r="1.8" /></>,
  document: <><path d="M14 3H7a2 2 0 00-2 2v14a2 2 0 002 2h10a2 2 0 002-2V8z" /><path d="M14 3v5h5M9 13h6M9 17h4" /></>,
  couronne: <><path d="M4 8l4 4 4-6 4 6 4-4-1.5 10h-13z" /><path d="M6.5 21h11" /></>,
  pin: <><path d="M12 21s7-6.2 7-12a7 7 0 10-14 0c0 5.8 7 12 7 12z" /><circle cx="12" cy="9" r="2.5" /></>,
  oeil: <><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z" /><circle cx="12" cy="12" r="3" /></>,
  reglages: <><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 11-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 110-4h.1a1.7 1.7 0 001.5-1.1 1.7 1.7 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 114 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 110 4h-.1a1.7 1.7 0 00-1.5 1z" /></>,
  calendrier: <><rect x="3" y="5" width="18" height="16" rx="2" /><path d="M16 3v4M8 3v4M3 10h18" /></>,
  horloge: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
  message: <path d="M21 12a8 8 0 01-11.6 7.1L4 20l1-4.4A8 8 0 1121 12z" />,
  boite: <><path d="M3 13l2.5-7h13L21 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2z" /><path d="M3 13h5l1.5 2.5h5L16 13h5" /></>,
  presse: <><rect x="5" y="4" width="14" height="17" rx="2" /><path d="M9 4h6v3H9zM9 12h6M9 16h4" /></>,
  stetho: <><path d="M6 3v6a5 5 0 0010 0V3" /><path d="M11 14v2a5 5 0 0010 0v-3" /><circle cx="21" cy="11" r="2" /></>,
  suivi: <><rect x="3" y="5" width="18" height="16" rx="2" /><path d="M3 10h18M9 15l2 2 4-4" /></>,
  maison: <path d="M3 11l9-7 9 7v9a1 1 0 01-1 1h-5v-6H9v6H4a1 1 0 01-1-1z" />,
  cle: <><circle cx="8" cy="15" r="4" /><path d="M11 12l9-9M17 6l3 3M14 9l2 2" /></>,
  euro: <><path d="M17 6.5A7 7 0 007 12a7 7 0 0010 5.5" /><path d="M4 10h9M4 14h9" /></>,
  livre: <><path d="M4 5a2 2 0 012-2h13v16H6a2 2 0 00-2 2z" /><path d="M4 19V5M19 19v2H6" /></>,
  facture: <><path d="M6 3h12v18l-3-2-3 2-3-2-3 2z" /><path d="M9 8h6M9 12h6M9 16h3" /></>,
  etoile: <path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z" />,
  exercice: <path d="M4 9v6M7 7v10M17 7v10M20 9v6M7 12h10" />,
  recherche: <><circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" /></>,
  crayon: <path d="M4 20h4L19 9l-4-4L4 16zM14 6l4 4" />,
  cloche: <><path d="M6 16V11a6 6 0 1112 0v5l2 2H4z" /><path d="M10 21h4" /></>,
  coeur: <path d="M12 20s-7-4.4-9-9a5 5 0 019-3 5 5 0 019 3c-2 4.6-9 9-9 9z" />,
  soin: <><rect x="3" y="7" width="18" height="13" rx="2" /><path d="M9 7V5a1 1 0 011-1h4a1 1 0 011 1v2M12 10.5v6M9 13.5h6" /></>,
  equipe: <><circle cx="9" cy="8" r="3.2" /><path d="M3 20a6 6 0 0112 0" /><circle cx="17" cy="9" r="2.5" /><path d="M16 14.2A5 5 0 0121 19" /></>,
  valide: <><circle cx="12" cy="12" r="9" /><path d="M8 12.5l2.7 2.7L16 10" /></>,
  pilule: <><rect x="3" y="8" width="18" height="8" rx="4" transform="rotate(-45 12 12)" /><path d="M9.2 9.2l5.6 5.6" /></>,
  seringue: <path d="M18 2l4 4M20 4l-9.5 9.5M15 5l4 4M8 12l4 4-4.5 4.5H4v-3.5zM6 18l-4 4" />,
  logement: <><path d="M3 21V9l9-6 9 6v12" /><path d="M8 21v-7h8v7M3 21h18" /></>,
  fleche: <path d="M9 6l6 6-6 6" />,
};

export function Icone({ nom, taille = 20, className = '' }: { nom: keyof typeof TRACES | string; taille?: number; className?: string }) {
  return (
    <svg width={taille} height={taille} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.7}
      strokeLinecap="round" strokeLinejoin="round" className={className} aria-hidden>
      {TRACES[nom] ?? TRACES.document}
    </svg>
  );
}

/** Carte indicateur : icône dans un cercle teinté, chiffre lisible, libellé. */
export function Kpi({ valeur, label, icone, href, onClick, teinte = TEAL, actif = false }: {
  valeur: number | string; label: string; icone: React.ReactNode; href?: string; onClick?: () => void; teinte?: string; actif?: boolean;
}) {
  const texte = typeof valeur === 'string';
  const contenu = (
    <>
      <span className="w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: `${teinte}17`, color: teinte }} aria-hidden>
        {typeof icone === 'string' ? <Icone nom={icone} /> : icone}
      </span>
      <span className="min-w-0">
        <span className={`block font-bold text-[#1E2025] leading-tight tabular-nums truncate ${texte ? 'text-lg sm:text-xl' : 'text-2xl sm:text-[28px]'}`}>{valeur}</span>
        <span className="block text-[13px] font-medium text-gray-600 leading-snug mt-0.5">{label}</span>
      </span>
    </>
  );
  const cls = `bg-white rounded-2xl p-4 flex flex-col sm:flex-row sm:items-center gap-3 text-left w-full h-full ${OMBRE} ${href || onClick ? 'hover:shadow-md transition-shadow' : ''}`;
  const style = { border: actif ? `1.5px solid ${teinte}` : `1px solid ${BORDURE}` };
  if (href) return <Link href={href} className={cls} style={style}>{contenu}</Link>;
  if (onClick) return <button type="button" onClick={onClick} className={cls} style={style}>{contenu}</button>;
  return <div className={cls} style={style}>{contenu}</div>;
}

/** Bloc professionnel de l'accueil : avatar rond, nom, lieu, statut, action. */
export function EnteteAccueil({ nom, avatar, avatarHref, surTitre, sousTitre, lieu, statut, actions }: {
  nom: string; avatar: string | null; avatarHref?: string; surTitre?: string; sousTitre?: React.ReactNode;
  lieu?: string; statut?: React.ReactNode; actions?: React.ReactNode;
}) {
  const rond = (
    <span className="w-16 h-16 sm:w-20 sm:h-20 rounded-full overflow-hidden flex-shrink-0 flex items-center justify-center bg-white" style={{ border: `1px solid ${BORDURE}` }}>
      {avatar
        // eslint-disable-next-line @next/next/no-img-element
        ? <img src={avatar} alt="" className="w-full h-full object-contain" />
        : <span className="w-full h-full flex items-center justify-center bg-[#E8F4F6] text-2xl font-bold text-[#0C5C6C]">{nom[0]?.toUpperCase() ?? '?'}</span>}
    </span>
  );
  return (
    <section className={`bg-white rounded-2xl p-4 sm:p-6 flex flex-col sm:flex-row sm:items-center gap-4 ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
      <div className="flex items-center gap-4 min-w-0 flex-1">
        {avatarHref ? <Link href={avatarHref} className="flex-shrink-0">{rond}</Link> : rond}
        <div className="min-w-0">
          {surTitre && <p className="text-sm text-gray-500">{surTitre}</p>}
          <h1 className="text-xl sm:text-2xl font-bold text-[#1E2025] leading-tight line-clamp-2">{nom}</h1>
          {sousTitre && <p className="text-sm text-gray-600 mt-0.5">{sousTitre}</p>}
          {lieu && (
            <p className="flex items-center gap-1.5 text-sm text-gray-600 mt-1">
              <Icone nom="pin" taille={15} className="text-[#0C5C6C] flex-shrink-0" /><span className="truncate">{lieu}</span>
            </p>
          )}
          {statut && <div className="flex flex-wrap items-center gap-2 mt-2">{statut}</div>}
        </div>
      </div>
      {actions && <div className="flex flex-wrap gap-2 sm:justify-end sm:flex-shrink-0">{actions}</div>}
    </section>
  );
}

/** Pastille de statut / d'abonnement (contour fin, couleurs réelles). */
export function Puce({ texte, fg, bg, icone, point = false, href }: {
  texte: string; fg: string; bg: string; icone?: string; point?: boolean; href?: string;
}) {
  const cls = 'inline-flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1 rounded-full whitespace-nowrap';
  const style = { color: fg, background: bg, border: `1px solid ${fg}26` };
  const contenu = <>{point && <span className="w-1.5 h-1.5 rounded-full" style={{ background: fg }} />}{icone && <Icone nom={icone} taille={13} />}{texte}</>;
  return href
    ? <Link href={href} className={`${cls} hover:opacity-80 transition-opacity`} style={style}>{contenu}</Link>
    : <span className={cls} style={style}>{contenu}</span>;
}

/** Bouton pilule (plein teal ou contour). */
export function BoutonPilule({ href, icone, children, contour = false }: { href: string; icone?: string; children: React.ReactNode; contour?: boolean }) {
  return (
    <Link href={href} className={`inline-flex items-center gap-2 rounded-full text-sm font-semibold px-4 py-2.5 transition-colors ${contour
      ? 'border border-[#0C5C6C]/40 text-[#0C5C6C] hover:bg-[#E8F4F6]'
      : 'bg-[#0C5C6C] text-white hover:bg-[#094F5D]'}`}>
      {icone && <Icone nom={icone} taille={16} />}{children}
    </Link>
  );
}

/** Titre de rubrique de l'accueil + lien « Voir tout ». */
export function TitreRubrique({ titre, lien, libelleLien = 'Voir tout' }: { titre: string; lien?: string; libelleLien?: string }) {
  return (
    <div className="flex items-center justify-between gap-3 mb-3">
      <h2 className="text-lg font-bold text-[#1E2025]">{titre}</h2>
      {lien && <Link href={lien} className="text-sm font-semibold text-[#0C5C6C] hover:underline whitespace-nowrap">{libelleLien} →</Link>}
    </div>
  );
}

/** Tuile d'accès rapide : icône dans un cercle teinté + libellé. */
export function Tuile({ label, icone, href, onClick, teinte = TEAL }: { label: string; icone: string; href?: string; onClick?: () => void; teinte?: string }) {
  const cls = `h-24 bg-white rounded-2xl flex flex-col items-center justify-center gap-2 px-2 text-center hover:shadow-md transition-shadow ${OMBRE}`;
  const style = { border: `1px solid ${BORDURE}` };
  const contenu = (
    <>
      <span className="w-9 h-9 rounded-full flex items-center justify-center" style={{ background: `${teinte}17`, color: teinte }} aria-hidden><Icone nom={icone} taille={18} /></span>
      <span className="text-xs font-semibold text-[#1E2025] leading-tight line-clamp-2">{label}</span>
    </>
  );
  return href
    ? <Link href={href} className={cls} style={style}>{contenu}</Link>
    : <button type="button" onClick={onClick} className={cls} style={style}>{contenu}</button>;
}

export function Section({ titre, icone, compteur, action, children, className = '' }: {
  titre: string; icone?: React.ReactNode; compteur?: number; action?: React.ReactNode; children: React.ReactNode; className?: string;
}) {
  return (
    <section className={`bg-white rounded-2xl border border-[#E5E8E6] p-4 ${OMBRE} ${className}`}>
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
        : <span className="text-[#0C5C6C]"><Icone nom="patte" taille={Math.round(taille * 0.5)} /></span>}
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
