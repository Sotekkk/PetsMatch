'use client';

import { useRef, useState } from 'react';
import { SILHOUETTE_ASSETS, CATEGORIES_OSTEO, colorPointEffectif, vuesDisponibles, TEAL, type MorphoPoint } from '@/lib/morpho';

interface Props {
  espece: string;
  vue: string;
  points: MorphoPoint[];
  onTapEmpty?: (xPct: number, yPct: number) => void;
  onTapPoint?: (point: MorphoPoint) => void;
  enableZoom?: boolean;
  onVueChange?: (vue: string) => void;
}

export function MorphoLegende({ dark = false }: { dark?: boolean }) {
  return (
    <div className="flex flex-wrap justify-center gap-x-3 gap-y-1.5">
      {CATEGORIES_OSTEO.map(c => (
        <div key={c.key} className="flex items-center gap-1.5">
          <span className="w-2.5 h-2.5 rounded-full inline-block" style={{ background: c.color }} />
          <span className="text-[11px] font-galey" style={{ color: dark ? 'rgba(255,255,255,0.7)' : '#6B7280' }}>{c.label}</span>
        </div>
      ))}
    </div>
  );
}

function SilhouetteCanvas({ espece, vue, points, onTapEmpty, onTapPoint, dotSize = 22 }: {
  espece: string; vue: string; points: MorphoPoint[];
  onTapEmpty?: (x: number, y: number) => void;
  onTapPoint?: (p: MorphoPoint) => void;
  dotSize?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const asset = SILHOUETTE_ASSETS[espece]?.[vue] ?? SILHOUETTE_ASSETS.chien[vue];
  if (!asset) return null;

  function handleClick(e: React.MouseEvent<HTMLDivElement>) {
    if (!onTapEmpty || !ref.current) return;
    const rect = ref.current.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width) * 100;
    const y = ((e.clientY - rect.top) / rect.height) * 100;
    onTapEmpty(Math.max(0, Math.min(100, x)), Math.max(0, Math.min(100, y)));
  }

  return (
    <div
      ref={ref}
      onClick={handleClick}
      className="relative w-full rounded-2xl overflow-hidden bg-black select-none"
      style={{ aspectRatio: asset.ratio, cursor: onTapEmpty ? 'crosshair' : 'default' }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={asset.src} alt={`Silhouette ${vue}`} className="absolute inset-0 w-full h-full object-cover pointer-events-none" draggable={false} />
      {points.filter(p => p.vue === vue).map(p => (
        <button
          key={p.id}
          onClick={(e) => { e.stopPropagation(); onTapPoint?.(p); }}
          className="absolute rounded-full border-2 border-white shadow"
          style={{
            left: `calc(${p.x_pct}% - ${dotSize / 2}px)`,
            top: `calc(${p.y_pct}% - ${dotSize / 2}px)`,
            width: dotSize, height: dotSize,
            background: colorPointEffectif(p.categorie, p.couleur),
            cursor: onTapPoint ? 'pointer' : 'default',
          }}
        />
      ))}
    </div>
  );
}

export default function MorphoSilhouette({ espece, vue, points, onTapEmpty, onTapPoint, enableZoom = true, onVueChange }: Props) {
  const [zoomOpen, setZoomOpen] = useState(false);
  const [zoomVue, setZoomVue] = useState(vue);

  return (
    <div className="relative">
      <SilhouetteCanvas espece={espece} vue={vue} points={points} onTapEmpty={onTapEmpty} onTapPoint={onTapPoint} />
      {enableZoom && (
        <button
          type="button"
          onClick={() => { setZoomVue(vue); setZoomOpen(true); }}
          className="absolute bottom-2 right-2 bg-black/60 hover:bg-black/75 text-white rounded-full p-1.5"
          aria-label="Agrandir"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <circle cx="11" cy="11" r="7" /><path d="M21 21l-4.3-4.3" /><path d="M11 8v6M8 11h6" />
          </svg>
        </button>
      )}

      {zoomOpen && (
        <div className="fixed inset-0 z-50 bg-black flex flex-col" onClick={() => setZoomOpen(false)}>
          <div className="flex items-center justify-between px-4 py-3" onClick={e => e.stopPropagation()}>
            <div className="flex gap-2 flex-wrap">
              {vuesDisponibles(espece).map(v => (
                <button
                  key={v.key}
                  onClick={() => { setZoomVue(v.key); onVueChange?.(v.key); }}
                  className="px-3 py-1.5 rounded-full text-xs font-galey font-semibold"
                  style={{ background: zoomVue === v.key ? TEAL : 'rgba(255,255,255,0.1)', color: 'white' }}
                >
                  {v.label}
                </button>
              ))}
            </div>
            <button onClick={() => setZoomOpen(false)} className="text-white text-2xl leading-none px-2">×</button>
          </div>
          {/* Pas de flex items-center ici : centrer verticalement un contenu qui
              déborde avec items-center rend la partie du haut inaccessible au
              scroll (bug CSS connu flexbox+overflow) — d'où le problème
              signalé sur les vues face/dos (portrait, plus hautes que l'écran).
              mx-auto centre horizontalement sans casser le scroll vertical. */}
          <div className="flex-1 overflow-auto p-4" onClick={e => e.stopPropagation()}>
            <div className="w-full max-w-3xl mx-auto">
              <SilhouetteCanvas espece={espece} vue={zoomVue} points={points} onTapEmpty={onTapEmpty} onTapPoint={onTapPoint} dotSize={28} />
            </div>
          </div>
          <div className="px-4 py-3" onClick={e => e.stopPropagation()}>
            <MorphoLegende dark />
          </div>
        </div>
      )}
    </div>
  );
}
