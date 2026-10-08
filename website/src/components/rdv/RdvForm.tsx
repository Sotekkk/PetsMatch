'use client';

// Briques du formulaire de prise de rendez-vous, communes à toutes les
// professions : la page du métier fournit ses motifs, ses intervenants et ses
// textes (rien de vétérinaire ici). Utilisées d'abord par le formulaire
// vétérinaire (app/services/pro/[uid]/page.tsx). Miroir app :
// lib/widgets/rdv/rdv_form_widgets.dart.

import { useEffect, useRef, useState, type ReactNode } from 'react';

const INK = '#1E2025';
const MUTED = '#6F767B';
const LINE = '#E4E7E2';
const FONT = { fontFamily: 'Galey, sans-serif' } as const;

// ── Icônes (trait fin, même style partout) ──────────────────────────────────

const PATHS: Record<string, ReactNode> = {
  stethoscope: <><path d="M6 3v5a4 4 0 0 0 8 0V3" /><path d="M10 12v3a5 5 0 0 0 10 0v-2" /><circle cx="20" cy="11" r="2" /></>,
  syringe: <><path d="m18 2 4 4" /><path d="m17 7 3-3" /><path d="M19 9 8.7 19.3a1 1 0 0 1-1.4 0l-2.6-2.6a1 1 0 0 1 0-1.4L15 5" /><path d="m9 11 4 4" /><path d="m5 19-3 3" /><path d="m14 4 6 6" /></>,
  clipboard: <><rect x="8" y="2" width="8" height="4" rx="1" /><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2" /><path d="M9 12h6" /><path d="M9 16h6" /></>,
  alert: <><path d="m10.3 3.9-8.1 14a2 2 0 0 0 1.7 3h16.2a2 2 0 0 0 1.7-3l-8.1-14a2 2 0 0 0-3.4 0Z" /><path d="M12 9v4" /><path d="M12 17h.01" /></>,
  bandage: <><rect x="2" y="7" width="20" height="10" rx="5" transform="rotate(-45 12 12)" /><path d="M10 10h.01" /><path d="M14 14h.01" /><path d="M10 14h.01" /><path d="M14 10h.01" /></>,
  more: <><circle cx="5" cy="12" r="1" /><circle cx="12" cy="12" r="1" /><circle cx="19" cy="12" r="1" /></>,
  user: <><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></>,
  users: <><circle cx="9" cy="8" r="3.5" /><path d="M2.5 20a6.5 6.5 0 0 1 13 0" /><path d="M16 4.5a3.5 3.5 0 0 1 0 7" /><path d="M18 14a6.5 6.5 0 0 1 3.5 6" /></>,
  paw: <><circle cx="6" cy="10" r="2" /><circle cx="10" cy="5.5" r="2" /><circle cx="14" cy="5.5" r="2" /><circle cx="18" cy="10" r="2" /><path d="M8 16.5c0-2.5 1.8-4.5 4-4.5s4 2 4 4.5c0 1.7-1.3 2.5-2.5 2.5-.7 0-1-.3-1.5-.3s-.8.3-1.5.3C9.3 19 8 18.2 8 16.5Z" /></>,
  calendar: <><rect x="3" y="4" width="18" height="18" rx="2" /><path d="M16 2v4" /><path d="M8 2v4" /><path d="M3 10h18" /></>,
  clock: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
  chevronLeft: <path d="m15 18-6-6 6-6" />,
  chevronRight: <path d="m9 18 6-6-6-6" />,
  chevronDown: <path d="m6 9 6 6 6-6" />,
  calendarOff: <><rect x="3" y="4" width="18" height="18" rx="2" /><path d="M3 10h18" /><path d="m9 14 6 6" /><path d="m15 14-6 6" /></>,
};

export type RdvIconName = keyof typeof PATHS;

export function RdvIcon({ name, size = 18, color = 'currentColor', strokeWidth = 1.8 }: { name: RdvIconName; size?: number; color?: string; strokeWidth?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth}
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="flex-shrink-0">
      {PATHS[name]}
    </svg>
  );
}

// ── Types ───────────────────────────────────────────────────────────────────

export interface RdvOption { key: string; label: string; icon: RdvIconName; description?: string; badge?: string }
/** `id` '*' = « Peu importe ». */
export interface RdvIntervenant { id: string; nom: string; sousTitre?: string; photoUrl?: string | null }

// ── Section numérotée ───────────────────────────────────────────────────────

export function RdvSection({ etape, titre, sousTitre, color, children }: { etape?: number; titre: string; sousTitre?: string; color: string; children: ReactNode }) {
  return (
    <section>
      <div className="flex items-center gap-2.5">
        {etape != null && (
          <span className="w-[22px] h-[22px] rounded-full flex items-center justify-center text-[11.5px] font-extrabold flex-shrink-0"
            style={{ ...FONT, backgroundColor: `${color}1F`, color }}>{etape}</span>
        )}
        <h3 className="text-[15px] font-bold" style={{ ...FONT, color: INK }}>{titre}</h3>
      </div>
      {sousTitre && <p className={`text-xs mt-0.5 ${etape != null ? 'pl-8' : ''}`} style={{ ...FONT, color: MUTED }}>{sousTitre}</p>}
      <div className="mt-3">{children}</div>
    </section>
  );
}

// ── Cartes de choix (2 colonnes dès que la place le permet) ────────────────

export function RdvChoiceGrid({ options, selected, onSelect, color }: { options: RdvOption[]; selected: string | null; onSelect: (key: string) => void; color: string }) {
  return (
    <div className="grid grid-cols-1 min-[360px]:grid-cols-2 gap-2.5">
      {options.map(o => {
        const sel = o.key === selected;
        return (
          <button key={o.key} type="button" onClick={() => onSelect(o.key)} aria-pressed={sel}
            className="flex items-start gap-2.5 p-2.5 rounded-xl text-left transition-all hover:shadow-sm"
            style={{ ...FONT, backgroundColor: sel ? `${color}0F` : 'white', border: `${sel ? 1.5 : 1}px solid ${sel ? color : LINE}` }}>
            <span className="w-[34px] h-[34px] rounded-[9px] flex items-center justify-center flex-shrink-0 transition-colors"
              style={{ backgroundColor: sel ? color : `${color}14` }}>
              <RdvIcon name={o.icon} color={sel ? 'white' : color} />
            </span>
            <span className="min-w-0 flex-1">
              <span className="flex items-center gap-2">
                <span className="text-[13.5px] font-bold truncate flex-1" style={{ color: sel ? color : INK }}>{o.label}</span>
                {o.badge && <span className="text-[10.5px] flex-shrink-0" style={{ color: MUTED }}>{o.badge}</span>}
              </span>
              {o.description && <span className="block text-[11.5px] leading-snug mt-0.5" style={{ color: MUTED }}>{o.description}</span>}
            </span>
          </button>
        );
      })}
    </div>
  );
}

// ── Choix court en segments ────────────────────────────────────────────────

export function RdvSegmented<T extends string | boolean>({ options, selected, onSelect, color }: { options: { value: T; label: string }[]; selected: T | null; onSelect: (v: T) => void; color: string }) {
  return (
    <div className="flex p-[3px] rounded-xl" style={{ backgroundColor: '#F2F3F1' }}>
      {options.map(o => {
        const sel = o.value === selected;
        return (
          <button key={String(o.value)} type="button" onClick={() => onSelect(o.value)} aria-pressed={sel}
            className="flex-1 py-2 rounded-[10px] text-[13px] font-semibold transition-all"
            style={{ ...FONT, backgroundColor: sel ? 'white' : 'transparent', color: sel ? color : MUTED,
              border: `1px solid ${sel ? `${color}80` : 'transparent'}`, boxShadow: sel ? '0 1px 4px rgba(0,0,0,.05)' : 'none' }}>
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

// ── Intervenants (avatar ou icône neutre) ──────────────────────────────────

function Avatar({ url, color, tous }: { url?: string | null; color: string; tous: boolean }) {
  const [broken, setBroken] = useState(false);
  return (
    <span className="w-[38px] h-[38px] rounded-full overflow-hidden flex items-center justify-center flex-shrink-0" style={{ backgroundColor: `${color}14` }}>
      {url && !broken
        // eslint-disable-next-line @next/next/no-img-element
        ? <img src={url} alt="" className="w-full h-full object-cover" onError={() => setBroken(true)} />
        : <RdvIcon name={tous ? 'users' : 'user'} color={color} size={19} />}
    </span>
  );
}

export function RdvIntervenantList({ intervenants, selected, onSelect, color }: { intervenants: RdvIntervenant[]; selected: string; onSelect: (id: string) => void; color: string }) {
  return (
    <div className="space-y-2" role="radiogroup">
      {intervenants.map(p => {
        const sel = p.id === selected;
        return (
          <button key={p.id} type="button" role="radio" aria-checked={sel} onClick={() => onSelect(p.id)}
            className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-left transition-all hover:shadow-sm"
            style={{ ...FONT, backgroundColor: sel ? `${color}0F` : 'white', border: `${sel ? 1.5 : 1}px solid ${sel ? color : LINE}` }}>
            <Avatar url={p.photoUrl} color={color} tous={p.id === '*'} />
            <span className="flex-1 min-w-0">
              <span className="block text-sm font-bold truncate" style={{ color: sel ? color : INK }}>{p.nom}</span>
              {p.sousTitre && <span className="block text-[11.5px]" style={{ color: MUTED }}>{p.sousTitre}</span>}
            </span>
            <span className="w-5 h-5 rounded-full flex-shrink-0 transition-all"
              style={{ border: sel ? `6px solid ${color}` : '1.5px solid #C9CDC7' }} />
          </button>
        );
      })}
    </div>
  );
}

// ── Bandeau de dates : cartes compactes + flèches, sans barre visible ──────

const JOURS = ['DIM', 'LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM'];
const MOIS = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

export function RdvDateStrip({ dates, selected, onSelect, color, disponible }: { dates: string[]; selected: string | null; onSelect: (d: string) => void; color: string; disponible?: (d: string) => boolean }) {
  const ref = useRef<HTMLDivElement>(null);
  const [debut, setDebut] = useState(true);
  const [fin, setFin] = useState(false);

  const maj = () => {
    const el = ref.current;
    if (!el) return;
    setDebut(el.scrollLeft <= 1);
    setFin(el.scrollLeft + el.clientWidth >= el.scrollWidth - 1);
  };
  useEffect(() => {
    maj();
    window.addEventListener('resize', maj);
    return () => window.removeEventListener('resize', maj);
  }, [dates.length]);

  const defiler = (sens: number) => {
    const el = ref.current;
    if (el) el.scrollBy({ left: sens * (el.clientWidth - 54), behavior: 'smooth' });
  };

  const fleche = (sens: number, actif: boolean) => (
    <button type="button" onClick={() => defiler(sens)} disabled={!actif}
      aria-label={sens < 0 ? 'Dates précédentes' : 'Dates suivantes'}
      className="w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 transition-colors hover:bg-gray-100 disabled:hover:bg-transparent">
      <RdvIcon name={sens < 0 ? 'chevronLeft' : 'chevronRight'} size={20} color={actif ? INK : '#CDD1CB'} />
    </button>
  );

  return (
    <div className="flex items-center gap-1">
      {fleche(-1, !debut)}
      <div ref={ref} onScroll={maj}
        className="flex-1 flex gap-2 overflow-x-auto scroll-smooth [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {dates.map(d => {
          const dt = new Date(d + 'T00:00:00');
          const sel = d === selected;
          const dispo = disponible?.(d) ?? true;
          return (
            <button key={d} type="button" onClick={() => onSelect(d)} aria-pressed={sel}
              className="flex-shrink-0 w-[54px] h-[70px] rounded-xl flex flex-col items-center justify-center transition-all"
              style={{ ...FONT, backgroundColor: sel ? color : 'white', border: `1px solid ${sel ? color : LINE}`, opacity: dispo || sel ? 1 : 0.4 }}>
              <span className="text-[10px] font-semibold tracking-wide" style={{ color: sel ? 'rgba(255,255,255,.85)' : MUTED }}>{JOURS[dt.getDay()]}</span>
              <span className="text-lg font-extrabold leading-tight" style={{ color: sel ? 'white' : INK }}>{dt.getDate()}</span>
              <span className="text-[10px]" style={{ color: sel ? 'rgba(255,255,255,.85)' : MUTED }}>{MOIS[dt.getMonth()]}</span>
            </button>
          );
        })}
      </div>
      {fleche(1, !fin)}
    </div>
  );
}

// ── Horaires groupés Matin / Après-midi / Soir ─────────────────────────────

export function RdvTimeGrid({ horaires, selected, onSelect, color }: { horaires: string[]; selected: string | null; onSelect: (h: string) => void; color: string }) {
  const groupes: [string, string[]][] = [['Matin', []], ['Après-midi', []], ['Soir', []]];
  for (const h of horaires) {
    const heure = parseInt(h.split(':')[0] ?? '0', 10);
    groupes[heure < 12 ? 0 : heure < 18 ? 1 : 2][1].push(h);
  }
  return (
    <div className="space-y-3">
      {groupes.filter(g => g[1].length > 0).map(([nom, liste]) => (
        <div key={nom}>
          <p className="text-[11.5px] font-semibold mb-1.5" style={{ ...FONT, color: MUTED }}>{nom}</p>
          <div className="grid grid-cols-4 sm:grid-cols-5 gap-2">
            {liste.map(h => {
              const sel = h === selected;
              return (
                <button key={h} type="button" onClick={() => onSelect(h)} aria-pressed={sel}
                  className="py-2 rounded-[10px] text-[13.5px] font-bold transition-all hover:shadow-sm"
                  style={{ ...FONT, backgroundColor: sel ? color : 'white', color: sel ? 'white' : INK, border: `1px solid ${sel ? color : LINE}` }}>
                  {h}
                </button>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}

// ── Champ libre discret ────────────────────────────────────────────────────

export function RdvTextArea({ value, onChange, placeholder, color, rows = 3 }: { value: string; onChange: (v: string) => void; placeholder: string; color: string; rows?: number }) {
  const [focus, setFocus] = useState(false);
  return (
    <textarea value={value} onChange={e => onChange(e.target.value)} rows={rows} placeholder={placeholder}
      onFocus={() => setFocus(true)} onBlur={() => setFocus(false)}
      className="w-full rounded-xl px-3 py-2.5 text-sm leading-snug resize-y focus:outline-none placeholder:text-[#9AA09C]"
      style={{ ...FONT, color: INK, border: `${focus ? 1.5 : 1}px solid ${focus ? color : LINE}` }} />
  );
}

// ── Récapitulatif ──────────────────────────────────────────────────────────

export function RdvRecap({ lignes, color }: { lignes: { icon: RdvIconName; label: string; valeur: string }[]; color: string }) {
  return (
    <div className="rounded-2xl px-4 pt-3 pb-1.5" style={{ ...FONT, backgroundColor: `${color}0D`, border: `1px solid ${color}2E` }}>
      <p className="text-[13.5px] font-bold mb-2" style={{ color: INK }}>Récapitulatif</p>
      {lignes.map(l => (
        <div key={l.label} className="flex items-start gap-2.5 mb-2">
          <RdvIcon name={l.icon} size={16} color={color} />
          <span className="w-[92px] flex-shrink-0 text-[12.5px]" style={{ color: MUTED }}>{l.label}</span>
          <span className="flex-1 text-[13px] font-semibold" style={{ color: INK }}>{l.valeur}</span>
        </div>
      ))}
    </div>
  );
}

// ── Bouton principal ───────────────────────────────────────────────────────

export function RdvPrimaryButton({ label, onClick, disabled, loading, color }: { label: string; onClick: () => void; disabled?: boolean; loading?: boolean; color: string }) {
  return (
    <button type="button" onClick={onClick} disabled={disabled || loading}
      className="w-full h-[52px] rounded-[14px] text-white font-bold text-[15.5px] transition-opacity disabled:opacity-40 hover:opacity-95 flex items-center justify-center"
      style={{ ...FONT, backgroundColor: color }}>
      {loading
        ? <span className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
        : label}
    </button>
  );
}

export function RdvVide({ titre, detail }: { titre: string; detail?: string }) {
  return (
    <div className="text-center py-6 px-4 rounded-xl bg-white" style={{ ...FONT, border: `1px solid ${LINE}` }}>
      <span className="inline-flex mb-2"><RdvIcon name="calendarOff" size={28} color="#C9CDC7" /></span>
      <p className="text-[13px]" style={{ color: MUTED }}>{titre}</p>
      {detail && <p className="text-xs mt-0.5 text-gray-400">{detail}</p>}
    </div>
  );
}
