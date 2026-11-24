'use client';

// ACACED : valable 10 ans après l'obtention (ou la dernière formation
// d'actualisation). À la création d'un profil, si la date d'obtention a plus
// de 10 ans, on demande directement la date de la formation d'actualisation
// et son attestation (miroir appli : AcacedActualisationBloc).

import { useRef } from 'react';

/** Fin de validité : 10 ans après la date (AAAA-MM-JJ), null si pas de date. */
export function acacedFinValidite(date: string | null | undefined): Date | null {
  if (!date) return null;
  const b = new Date(date);
  if (Number.isNaN(b.getTime())) return null;
  return new Date(b.getFullYear() + 10, b.getMonth(), b.getDate());
}

/** Vrai si l'ACACED obtenu à cette date est expiré aujourd'hui. */
export function acacedExpire(obtention: string | null | undefined): boolean {
  const fin = acacedFinValidite(obtention);
  return !!fin && fin.getTime() < Date.now();
}

/** Champs manquants de l'actualisation (vide si rien à demander). */
export function acacedActualisationManquante(
  obtention: string, renouvellement: string, fichier: File | null, fichierRequis: boolean,
): string[] {
  if (!acacedExpire(obtention)) return [];
  const errs: string[] = [];
  if (!renouvellement) errs.push("Date de la formation d'actualisation ACACED");
  else if (acacedExpire(renouvellement)) errs.push("Formation d'actualisation ACACED de moins de 10 ans");
  if (fichierRequis && !fichier) errs.push("Attestation d'actualisation ACACED");
  return errs;
}

export default function AcacedActualisation({ obtention, renouvellement, onRenouvellement, fichier, onFichier, fichierRequis = true }: {
  obtention: string;
  renouvellement: string;
  onRenouvellement: (v: string) => void;
  fichier: File | null;
  onFichier: (f: File | null) => void;
  fichierRequis?: boolean;
}) {
  const ref = useRef<HTMLInputElement>(null);
  if (!acacedExpire(obtention)) return null;
  const fin = acacedFinValidite(obtention);
  return (
    <div className="rounded-xl border border-red-200 bg-red-50/60 p-3 space-y-2.5">
      <input ref={ref} type="file" accept="image/*,application/pdf" className="hidden"
        onChange={e => { const f = e.target.files?.[0]; if (f) onFichier(f); e.target.value = ''; }} />
      <p className="text-sm font-semibold text-red-700">
        ACACED expiré{fin ? ` depuis le ${fin.toLocaleDateString('fr-FR')}` : ''} : actualisation requise
      </p>
      <p className="text-xs text-gray-600">
        L&apos;ACACED est valable 10 ans. Indiquez la date de votre formation d&apos;actualisation des connaissances
        et joignez son attestation.
      </p>
      <div>
        <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">
          Date de la formation d&apos;actualisation <span className="text-red-500">*</span>
        </p>
        <input type="date" value={renouvellement} onChange={e => onRenouvellement(e.target.value)}
          max={new Date().toISOString().slice(0, 10)}
          className="w-full rounded-xl border border-gray-200 bg-white px-3 py-2.5 text-sm" />
      </div>
      <div>
        <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">
          Attestation d&apos;actualisation {fichierRequis ? <span className="text-red-500">*</span> : <span className="normal-case font-normal text-gray-400">(optionnel maintenant, requis avant validation)</span>}
        </p>
        {fichier ? (
          <div className="flex items-center gap-2 bg-green-50 border border-green-200 rounded-xl px-3 py-2">
            <span className="text-xs text-green-700 flex-1 truncate">{fichier.name}</span>
            <button type="button" onClick={() => ref.current?.click()}
              className="text-xs text-[#0C5C6C] font-medium hover:underline">Changer</button>
          </div>
        ) : (
          <button type="button" onClick={() => ref.current?.click()}
            className="w-full rounded-xl py-3 text-sm font-semibold text-white bg-[#0C5C6C] hover:bg-[#094F5D] transition-colors">
            Joindre l&apos;attestation d&apos;actualisation (image ou PDF)
          </button>
        )}
      </div>
    </div>
  );
}
