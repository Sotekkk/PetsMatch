'use client';
// Composants communs de la gestion des annonces (« Mes annonces » de tous les
// profils qui publient : élevage, association, particulier, matériel des
// pros). Purement visuels : chaque page garde ses données, statuts, droits,
// quotas et actions. Miroir appli : lib/widgets/annonces/gestion_annonces_kit.dart.

import { useEffect, useRef, useState, type ReactNode } from 'react';
import Link from 'next/link';
import { Icone, BORDURE, OMBRE } from '@/components/dashboard/kit';

export const ENCRE = '#1E2025';
export const TEAL = '#0C5C6C';
export const VERT = '#6E9E57';

/** Action d'une annonce : lien ou bouton. `danger` : rouge (suppression). */
export interface ActionAnnonce {
  label: string;
  icone: string;
  href?: string;
  onClick?: () => void;
  danger?: boolean;
  disabled?: boolean;
  /** Mise en avant (ex. annonce déjà boostée). */
  actif?: boolean;
}

/** En-tête : titre, nombre d'annonces et boutons (Publier, Mes achats…). */
export function EnteteGestion({ total, publierHref, achatsHref }: { total: number; publierHref: string; achatsHref?: string }) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 mb-5">
      <div>
        <h1 className="text-2xl sm:text-[28px] font-bold" style={{ color: ENCRE }}>Mes annonces</h1>
        <p className="text-sm text-gray-500 mt-0.5">{total} annonce{total !== 1 ? 's' : ''}</p>
      </div>
      <div className="flex items-center gap-2">
        <Link href={publierHref}
          className="inline-flex items-center gap-2 bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold px-4 sm:px-5 py-2.5 rounded-xl transition-colors">
          <Icone nom="plus" taille={17} /> Publier une annonce
        </Link>
        {achatsHref && (
          <Link href={achatsHref}
            className="inline-flex items-center gap-2 bg-white border border-[#0C5C6C]/40 text-[#0C5C6C] hover:bg-[#E8F4F6] text-sm font-semibold px-4 py-2.5 rounded-xl transition-colors">
            <Icone nom="sac" taille={16} /> Mes achats
          </Link>
        )}
      </div>
    </div>
  );
}

/** Bandeau de quota : « 1 / 3 annonces actives », barre de progression, lien Gérer. */
export function BandeauQuota({ actives, max, formule, gererHref, changerFormule }: {
  actives: number; max: number; formule: string; gererHref: string; changerFormule?: boolean;
}) {
  const illimite = max === -1;
  const atteinte = !illimite && actives >= max;
  const pct = illimite ? 100 : Math.min(100, max > 0 ? (actives / max) * 100 : 100);
  return (
    <div className="rounded-2xl px-4 sm:px-5 py-3.5 mb-4 flex flex-wrap items-center gap-x-4 gap-y-2"
      style={{ background: atteinte ? '#FEF2F2' : '#F1F6EE', border: `1px solid ${atteinte ? '#FECACA' : '#DCE8D5'}` }}>
      {!illimite && (
        <div className="w-24 sm:w-28 h-2 rounded-full bg-white/80 overflow-hidden" aria-hidden>
          <div className="h-full rounded-full" style={{ width: `${pct}%`, background: atteinte ? '#F87171' : VERT }} />
        </div>
      )}
      <span className="text-sm text-[#1E2025]">
        {illimite ? <>Formule {formule} · <b>annonces illimitées</b></> : <><b className="tabular-nums">{actives} / {max}</b> annonces actives · formule {formule}</>}
        {atteinte && <span className="ml-2 font-semibold text-red-600">Limite atteinte</span>}
      </span>
      <Link href={gererHref}
        className="ml-auto inline-flex items-center gap-1 text-sm font-semibold text-[#0C5C6C] hover:underline">
        {changerFormule ? 'Changer de formule' : 'Gérer'} <Icone nom="fleche" taille={15} />
      </Link>
    </div>
  );
}

const champ = 'h-11 border bg-white rounded-xl text-sm text-[#1E2025] focus:outline-none focus:border-[#0C5C6C]';

/** Recherche + listes déroulantes (type, statut). */
export function BarreFiltres({ recherche, onRecherche, filtres }: {
  recherche: string; onRecherche: (v: string) => void;
  filtres: { label: string; valeur: string; options: { k: string; label: string }[]; onChange: (v: string) => void }[];
}) {
  return (
    <div className="flex flex-col sm:flex-row gap-2.5 mb-5">
      <label className="relative flex-1 min-w-0">
        <span className="absolute left-3.5 top-1/2 -translate-y-1/2 text-gray-400"><Icone nom="recherche" taille={17} /></span>
        <input value={recherche} onChange={e => onRecherche(e.target.value)} type="search"
          placeholder="Rechercher une annonce, une race…" aria-label="Rechercher une annonce"
          className={`${champ} w-full pl-10 pr-3`} style={{ borderColor: BORDURE }} />
      </label>
      <div className="grid grid-cols-2 sm:flex gap-2.5">
        {filtres.map(f => (
          <label key={f.label} className="relative">
            <span className="sr-only">{f.label}</span>
            <select value={f.valeur} onChange={e => f.onChange(e.target.value)} aria-label={f.label}
              className={`${champ} w-full sm:w-auto appearance-none pl-3.5 pr-9`} style={{ borderColor: BORDURE }}>
              {f.options.map(o => <option key={o.k} value={o.k}>{f.label} : {o.label}</option>)}
            </select>
            <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 rotate-90"><Icone nom="fleche" taille={15} /></span>
          </label>
        ))}
      </div>
    </div>
  );
}

/** Correspondance de recherche (insensible à la casse et aux accents). */
export function correspondRecherche(recherche: string, ...champs: (string | null | undefined)[]): boolean {
  const n = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const q = n(recherche.trim());
  if (!q) return true;
  return champs.some(c => !!c && n(c).includes(q));
}

/** Menu « … » : actions secondaires de l'annonce. */
export function MenuActions({ actions }: { actions: ActionAnnonce[] }) {
  const [ouvert, setOuvert] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!ouvert) return;
    const clic = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOuvert(false); };
    const touche = (e: KeyboardEvent) => { if (e.key === 'Escape') setOuvert(false); };
    document.addEventListener('mousedown', clic);
    document.addEventListener('keydown', touche);
    return () => { document.removeEventListener('mousedown', clic); document.removeEventListener('keydown', touche); };
  }, [ouvert]);
  if (actions.length === 0) return null;
  return (
    <div ref={ref} className="relative">
      <button type="button" onClick={() => setOuvert(o => !o)} aria-label="Autres actions" aria-expanded={ouvert}
        className="w-10 h-10 inline-flex items-center justify-center rounded-xl border bg-white text-[#1E2025] hover:border-[#0C5C6C]/50 transition-colors"
        style={{ borderColor: BORDURE }}>
        <Icone nom="points" taille={20} />
      </button>
      {ouvert && (
        <div className={`absolute right-0 top-11 z-30 w-60 bg-white rounded-xl py-1.5 ${OMBRE} shadow-lg`} style={{ border: `1px solid ${BORDURE}` }} role="menu">
          {actions.map(a => {
            const cls = `w-full flex items-center gap-2.5 px-3.5 py-2.5 text-sm text-left transition-colors disabled:opacity-50 ${a.danger ? 'text-red-600 hover:bg-red-50' : a.actif ? 'text-[#B45309] hover:bg-amber-50' : 'text-[#1E2025] hover:bg-[#F3F6F5]'}`;
            const contenu = <><Icone nom={a.icone} taille={17} />{a.label}</>;
            return a.href
              ? <Link key={a.label} href={a.href} className={cls} role="menuitem" onClick={() => setOuvert(false)}>{contenu}</Link>
              : <button key={a.label} type="button" className={cls} role="menuitem" disabled={a.disabled}
                  onClick={() => { setOuvert(false); a.onClick?.(); }}>{contenu}</button>;
          })}
        </div>
      )}
    </div>
  );
}

function BoutonAction({ a, plein }: { a: ActionAnnonce; plein: boolean }) {
  const cls = `w-full min-h-10 px-3 py-2 inline-flex items-center justify-center gap-2 rounded-xl text-sm font-semibold text-center leading-tight transition-colors disabled:opacity-60 ${plein
    ? (a.danger ? 'bg-red-600 hover:bg-red-700 text-white' : 'bg-[#0C5C6C] hover:bg-[#094F5D] text-white')
    : (a.danger ? 'bg-white border border-red-200 text-red-600 hover:bg-red-50' : 'bg-white border border-[#0C5C6C]/50 text-[#0C5C6C] hover:bg-[#E8F4F6]')}`;
  const contenu = <><Icone nom={a.icone} taille={16} />{a.label}</>;
  return a.href
    ? <Link href={a.href} className={cls}>{contenu}</Link>
    : <button type="button" onClick={a.onClick} disabled={a.disabled} className={cls}>{contenu}</button>;
}

/** Carte d'une annonce : photo, infos, actions principales et menu « … ». */
export function CarteAnnonce({ href, photo, iconeVide = 'patte', titre, sousTitre, etiquettes, prix, indicateurs, principales, menu, note }: {
  href: string;
  photo?: string | null;
  iconeVide?: string;
  titre: string;
  sousTitre?: string;
  /** Puces (statut, type, boost, expiration…). */
  etiquettes: ReactNode;
  prix?: string | null;
  indicateurs: { icone: string; texte: string }[];
  /** Une ou deux actions affichées en boutons (la première pleine). */
  principales: ActionAnnonce[];
  menu: ActionAnnonce[];
  note?: string | null;
}) {
  return (
    <div className={`bg-white rounded-2xl p-3 sm:p-4 ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
      <div className="flex gap-3 sm:gap-5">
        <Link href={href} className="relative flex-shrink-0 w-24 h-24 sm:w-44 sm:h-32 rounded-xl overflow-hidden bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center">
          {photo
            // eslint-disable-next-line @next/next/no-img-element
            ? <img src={photo} alt={titre} className="w-full h-full object-cover" />
            : <Icone nom={iconeVide} taille={34} />}
        </Link>
        <div className="flex-1 min-w-0 flex flex-col">
          <div className="flex items-start gap-2">
            <Link href={href} className="min-w-0 flex-1">
              <h3 className="font-bold text-[17px] sm:text-xl leading-snug truncate" style={{ color: ENCRE }}>{titre}</h3>
              {sousTitre && <p className="text-[13px] sm:text-sm text-gray-500 truncate capitalize">{sousTitre}</p>}
            </Link>
            <div className="sm:hidden"><MenuActions actions={menu} /></div>
          </div>
          <div className="flex flex-wrap items-center gap-1.5 mt-1.5">{etiquettes}</div>
          {prix && <p className="font-bold text-lg sm:text-2xl mt-1.5 tabular-nums" style={{ color: ENCRE }}>{prix}</p>}
          {indicateurs.length > 0 && (
            <div className="flex flex-wrap items-center gap-x-5 gap-y-1 mt-auto pt-1.5 text-[13px] sm:text-sm text-gray-600 tabular-nums">
              {indicateurs.map(i => <span key={i.texte} className="inline-flex items-center gap-1.5"><Icone nom={i.icone} taille={16} />{i.texte}</span>)}
            </div>
          )}
        </div>
        <div className="hidden sm:flex flex-col gap-2 w-44 flex-shrink-0">
          {principales.map((a, i) => <BoutonAction key={a.label} a={a} plein={i === 0} />)}
          <div className="flex justify-end mt-auto"><MenuActions actions={menu} /></div>
        </div>
      </div>
      {note && <p className="mt-3 text-xs text-gray-500">{note}</p>}
      <div className="sm:hidden grid gap-2 mt-3">
        {principales.map((a, i) => <BoutonAction key={a.label} a={a} plein={i === 0} />)}
      </div>
    </div>
  );
}

/** Rubrique (Animaux, Matériel & équipements) : en-tête sobre, compteur, repliable. */
export function RubriqueAnnonces({ titre, icone, nombre, vide, children, repliable = true }: {
  titre: string; icone: string; nombre: number | null; vide?: string; children: ReactNode; repliable?: boolean;
}) {
  const [ouvert, setOuvert] = useState(true);
  const estVide = nombre === 0;
  return (
    <section className="mb-5">
      <button type="button" onClick={() => repliable && !estVide && setOuvert(o => !o)}
        className={`w-full flex items-center gap-3 bg-white rounded-2xl px-4 sm:px-5 py-3.5 text-left ${OMBRE} ${ouvert && !estVide ? 'mb-3' : ''}`}
        style={{ border: `1px solid ${BORDURE}` }} aria-expanded={ouvert && !estVide}>
        <span className="text-[#1E2025]"><Icone nom={icone} taille={20} /></span>
        <span className="font-semibold text-[15px]" style={{ color: ENCRE }}>{titre}</span>
        <span className="flex-1 text-center text-sm text-gray-400 truncate">
          {estVide ? (vide ?? 'Aucune annonce') : nombre != null ? `${nombre} annonce${nombre > 1 ? 's' : ''}` : ''}
        </span>
        {repliable && !estVide && <span className={`text-gray-500 transition-transform ${ouvert ? '-rotate-90' : 'rotate-90'}`}><Icone nom="fleche" taille={17} /></span>}
      </button>
      {/* Toujours monté (le contenu charge et compte ses annonces), masqué si replié ou vide. */}
      <div className={ouvert && !estVide ? '' : 'hidden'}>{children}</div>
    </section>
  );
}

/** Message d'état vide / chargement, au même style. */
export function EtatVide({ icone, texte, action }: { icone: string; texte: string; action?: { label: string; href: string } }) {
  return (
    <div className={`bg-white rounded-2xl py-10 px-6 text-center ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
      <span className="w-11 h-11 mx-auto mb-3 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center"><Icone nom={icone} /></span>
      <p className="text-sm text-gray-500">{texte}</p>
      {action && (
        <Link href={action.href} className="inline-flex items-center gap-2 mt-4 bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold px-5 py-2.5 rounded-xl transition-colors">
          <Icone nom="plus" taille={16} />{action.label}
        </Link>
      )}
    </div>
  );
}

export function Chargement() {
  return <div className="flex justify-center py-12"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
}

/** Puces de statut communes (point coloré). */
export const TEINTES_STATUT: Record<string, { fg: string; bg: string }> = {
  vert:   { fg: '#2F7D3A', bg: '#EAF5EC' },
  ambre:  { fg: '#B45309', bg: '#FEF3C7' },
  bleu:   { fg: '#1D4ED8', bg: '#EFF6FF' },
  gris:   { fg: '#6B7280', bg: '#F3F4F6' },
  rouge:  { fg: '#B91C1C', bg: '#FEF2F2' },
  teal:   { fg: '#0C5C6C', bg: '#E8F4F6' },
};
