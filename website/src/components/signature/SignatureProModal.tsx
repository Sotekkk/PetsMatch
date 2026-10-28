'use client';

import { useEffect, useRef, useState } from 'react';

// Pavé de signature (souris / doigt), comme pour les contrats. Renvoie la
// data-URL PNG. Miroir appli : SignatureFullScreen (lib/widgets/signature_pad.dart).
export default function SignatureProModal({ onClose, onValider }: {
  onClose: () => void; onValider: (dataUrl: string) => void | Promise<void>;
}) {
  const ref = useRef<HTMLCanvasElement>(null);
  const dessin = useRef(false);
  const [vide, setVide] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const c = ref.current; if (!c) return;
    const ctx = c.getContext('2d'); if (!ctx) return;
    ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, c.width, c.height);
    ctx.strokeStyle = '#1E2025'; ctx.lineWidth = 2.5; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  }, []);

  const point = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const c = ref.current!; const r = c.getBoundingClientRect();
    return { x: (e.clientX - r.left) * (c.width / r.width), y: (e.clientY - r.top) * (c.height / r.height) };
  };
  const debut = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const ctx = ref.current?.getContext('2d'); if (!ctx) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    dessin.current = true; const p = point(e); ctx.beginPath(); ctx.moveTo(p.x, p.y);
  };
  const trace = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (!dessin.current) return;
    const ctx = ref.current?.getContext('2d'); if (!ctx) return;
    const p = point(e); ctx.lineTo(p.x, p.y); ctx.stroke(); setVide(false);
  };
  const effacer = () => {
    const c = ref.current; const ctx = c?.getContext('2d'); if (!c || !ctx) return;
    ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, c.width, c.height); setVide(true);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-lg p-5 space-y-3" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <h2 className="font-bold text-lg text-[#1E2025]">Ma signature</h2>
        <p className="text-xs text-gray-500">Signez dans le cadre : elle sera apposée sur vos comptes rendus et ordonnances.</p>
        <canvas ref={ref} width={900} height={360}
          className="w-full rounded-xl border-2 border-[#0C5C6C]/20 bg-white touch-none cursor-crosshair"
          onPointerDown={debut} onPointerMove={trace} onPointerUp={() => { dessin.current = false; }} onPointerLeave={() => { dessin.current = false; }} />
        <div className="flex gap-2">
          <button type="button" onClick={effacer} className="flex-1 py-2.5 rounded-xl text-sm border border-gray-200 text-gray-600">Effacer</button>
          <button type="button" onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm border border-gray-200 text-gray-600">Annuler</button>
          <button type="button" disabled={vide || saving}
            onClick={async () => { setSaving(true); await onValider(ref.current!.toDataURL('image/png')); setSaving(false); }}
            className="flex-[2] py-2.5 rounded-xl text-sm font-semibold text-white bg-[#6E9E57] disabled:opacity-40">
            {saving ? '…' : 'Valider ma signature'}
          </button>
        </div>
      </div>
    </div>
  );
}
