'use client';
// Mise en page commune des formulaires « Modifier l'annonce » (animaux,
// adoption, chevaux, matériel). Purement visuelle : chaque page garde ses
// champs, validations et règles d'enregistrement. Miroir appli :
// lib/widgets/annonces/formulaire_annonce_kit.dart.

import type { ReactNode } from 'react';
import Link from 'next/link';
import { Icone, BORDURE } from '@/components/dashboard/kit';

export const classeChamp = 'w-full min-h-11 border rounded-xl px-3.5 py-2.5 text-[15px] text-[#1E2025] bg-white placeholder:text-gray-400 focus:outline-none focus:border-[#0C5C6C] focus:ring-2 focus:ring-[#0C5C6C]/15';
export const styleChamp = { borderColor: BORDURE };

/** Page de formulaire : retour, titre, erreur, sections, zone d'actions unique. */
export function PageFormulaire({ retourHref, retourLabel = 'Retour à mes annonces', titre, sousTitre, erreur, onSubmit, children, annulerHref, enregistrement, libelleEnregistrer = 'Enregistrer les modifications', desactive }: {
  retourHref: string; retourLabel?: string; titre: string; sousTitre?: string; erreur?: string | null;
  onSubmit: (e: React.FormEvent) => void; children: ReactNode;
  annulerHref?: string; enregistrement: boolean; libelleEnregistrer?: string; desactive?: boolean;
}) {
  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <form onSubmit={onSubmit} noValidate className="max-w-4xl mx-auto px-4 sm:px-6 pt-5 sm:pt-8">
        <Link href={retourHref} className="inline-flex items-center gap-1.5 text-sm font-semibold text-[#0C5C6C] hover:underline">
          <span className="rotate-180 inline-flex"><Icone nom="fleche" taille={16} /></span>{retourLabel}
        </Link>
        <h1 className="text-2xl sm:text-3xl font-bold text-[#1E2025] mt-2">{titre}</h1>
        {sousTitre && <p className="text-sm text-gray-500 mt-1">{sousTitre}</p>}
        {erreur && (
          <div role="alert" className="mt-4 rounded-xl px-4 py-3 text-sm text-[#B91C1C] bg-[#FEF2F2]" style={{ border: '1px solid #FECACA' }}>{erreur}</div>
        )}
        <div className="space-y-4 mt-5 pb-6">{children}</div>
        {/* Zone d'actions unique, fixée en bas sans recouvrir les champs. */}
        <div className="sticky bottom-0 z-20 -mx-4 sm:mx-0 bg-white/95 backdrop-blur px-4 sm:px-5 py-3 sm:rounded-t-2xl flex flex-col-reverse sm:flex-row sm:justify-end gap-2"
          style={{ borderTop: `1px solid ${BORDURE}`, paddingBottom: 'max(0.75rem, env(safe-area-inset-bottom))' }}>
          {annulerHref && (
            <Link href={annulerHref} className="min-h-11 inline-flex items-center justify-center px-5 rounded-xl text-sm font-semibold text-[#1E2025] bg-white hover:bg-gray-50"
              style={{ border: `1px solid ${BORDURE}` }}>
              Annuler
            </Link>
          )}
          <button type="submit" disabled={enregistrement || desactive}
            className="min-h-11 inline-flex items-center justify-center gap-2 px-6 rounded-xl text-sm font-semibold text-white bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60">
            {enregistrement && <span className="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin" />}
            {enregistrement ? 'Enregistrement…' : libelleEnregistrer}
          </button>
        </div>
      </form>
    </div>
  );
}

/** Section blanche du formulaire. */
export function SectionFormulaire({ titre, description, children }: { titre: string; description?: string; children: ReactNode }) {
  return (
    <section className="bg-white rounded-2xl p-4 sm:p-6" style={{ border: `1px solid ${BORDURE}` }}>
      <h2 className="text-lg font-bold text-[#1E2025]">{titre}</h2>
      {description && <p className="text-sm text-gray-500 mt-0.5">{description}</p>}
      <div className="mt-4 space-y-4">{children}</div>
    </section>
  );
}

/** Champ : libellé au-dessus, mention obligatoire, aide et erreur. */
export function Champ({ label, requis, aide, erreur, children, htmlFor }: {
  label: string; requis?: boolean; aide?: string; erreur?: string | null; children: ReactNode; htmlFor?: string;
}) {
  return (
    <div>
      <label htmlFor={htmlFor} className="block text-sm font-semibold text-[#1E2025] mb-1.5">
        {label}{requis && <span className="text-[#B91C1C]"> *</span>}
      </label>
      {children}
      {aide && !erreur && <p className="text-xs text-gray-500 mt-1">{aide}</p>}
      {erreur && <p className="text-xs font-semibold text-[#B91C1C] mt-1">{erreur}</p>}
    </div>
  );
}

/** Deux colonnes sur ordinateur, une sur mobile. */
export function Colonnes({ children, trois = false }: { children: ReactNode; trois?: boolean }) {
  return <div className={`grid grid-cols-1 sm:grid-cols-2 ${trois ? 'lg:grid-cols-3' : ''} gap-4`}>{children}</div>;
}

/** Case à cocher lisible. */
export function CaseACocher({ label, checked, onChange }: { label: string; checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="flex items-center gap-2.5 min-h-11 cursor-pointer select-none text-[15px] text-[#1E2025]">
      <input type="checkbox" checked={checked} onChange={e => onChange(e.target.checked)}
        className="w-5 h-5 rounded accent-[#0C5C6C] flex-shrink-0" />
      {label}
    </label>
  );
}

/** Bloc des informations non modifiables (lecture seule). */
export function InfosVerrouillees({ titre = 'Identité de l’annonce', note = 'non modifiable', lignes }: {
  titre?: string; note?: string; lignes: { label: string; valeur?: string | null }[];
}) {
  const visibles = lignes.filter(l => l.valeur);
  if (visibles.length === 0) return null;
  return (
    <section className="rounded-2xl p-4 sm:p-6 bg-[#F3F6F5]" style={{ border: `1px solid ${BORDURE}` }}>
      <h2 className="text-[15px] font-bold text-[#1E2025]">{titre} <span className="font-normal text-gray-500">· {note}</span></h2>
      <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-1.5 mt-3 text-[15px]">
        {visibles.map(l => (
          <div key={l.label} className="grid grid-cols-[minmax(0,8.5rem)_1fr] gap-3">
            <dt className="text-gray-500">{l.label}</dt>
            <dd className="text-[#1E2025] break-words">{l.valeur}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

/** Grille de photos (existantes + nouvelles) avec retrait et ajout. */
export function GrillePhotos({ photos, max, onRetirer, onAjouter, multiple = true }: {
  photos: { url: string; cle: string }[]; max: number; onRetirer: (i: number) => void;
  onAjouter: (e: React.ChangeEvent<HTMLInputElement>) => void; multiple?: boolean;
}) {
  return (
    <div>
      <p className="text-sm text-gray-500 mb-2 tabular-nums">{photos.length} / {max} photos{multiple ? ' · sélection multiple possible' : ''}</p>
      <div className="grid grid-cols-3 sm:grid-cols-5 gap-3">
        {photos.map((p, i) => (
          <div key={p.cle} className="relative aspect-square rounded-xl overflow-hidden bg-[#EEF1EF]">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={p.url} alt="" className="w-full h-full object-cover" />
            <button type="button" onClick={() => onRetirer(i)} aria-label={`Retirer la photo ${i + 1}`}
              className="absolute top-1.5 right-1.5 w-8 h-8 rounded-full bg-white/95 text-[#B91C1C] flex items-center justify-center shadow">
              <Icone nom="corbeille" taille={15} />
            </button>
            {i === 0 && <span className="absolute bottom-1.5 left-1.5 text-[11px] font-semibold bg-white/95 text-[#1E2025] px-2 py-0.5 rounded-full">Principale</span>}
          </div>
        ))}
        {photos.length < max && (
          <label className="aspect-square rounded-xl border-2 border-dashed flex flex-col items-center justify-center gap-1 cursor-pointer text-gray-500 hover:text-[#0C5C6C] hover:border-[#0C5C6C]/50 transition-colors"
            style={{ borderColor: BORDURE }}>
            <Icone nom="plus" taille={22} />
            <span className="text-xs font-semibold text-center px-1">{photos.length === 0 ? 'Choisir des photos' : 'Ajouter des photos'}</span>
            <input type="file" accept="image/*" multiple={multiple} className="hidden" onChange={onAjouter} />
          </label>
        )}
      </div>
    </div>
  );
}
