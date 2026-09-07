'use client';

import React from 'react';

export function Badge({ label, color }: { label: string; color: string }) {
  return (
    <span className="text-xs px-2 py-0.5 rounded-full font-medium whitespace-nowrap"
      style={{ background: `${color}1a`, color }}>{label}</span>
  );
}

export function Section({ title, children, right }: { title: string; children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <p className="text-sm font-semibold text-[#6E9E57]" style={{ fontFamily: 'Galey, sans-serif' }}>{title}</p>
        {right}
      </div>
      <div className="space-y-2">{children}</div>
    </div>
  );
}

export function InfoRow({ label, value, mono }: { label: string; value: string | number | null | undefined; mono?: boolean }) {
  const v = value === null || value === undefined || value === '' ? '—' : String(value);
  return (
    <div>
      <p className="text-xs text-gray-400">{label}</p>
      <p className={`text-sm text-gray-800 ${mono ? 'font-mono text-xs break-all' : 'font-medium'}`}
        style={{ fontFamily: mono ? undefined : 'Galey, sans-serif' }}>{v}</p>
    </div>
  );
}

export function ActionBtn({ label, color, onClick, disabled }: { label: string; color: string; onClick: () => void; disabled?: boolean }) {
  return (
    <button onClick={onClick} disabled={disabled}
      className="px-4 py-1.5 rounded-xl text-sm font-semibold border transition-colors disabled:opacity-50"
      style={{ borderColor: `${color}66`, color, background: `${color}18`, fontFamily: 'Galey, sans-serif' }}>
      {label}
    </button>
  );
}

export const TYPE_COLORS: Record<string, string> = {
  particulier: '#0C5C6C', eleveur: '#6E9E57', association: '#7c3aed',
  veterinaire: '#dc2626', sante: '#db2777', education: '#2563eb',
  garde: '#ea580c', pension: '#ca8a04', toilettage: '#0891b2',
  photographe: '#4f46e5', taxi_animalier: '#65a30d', marechal_ferrant: '#78716c',
};

export const TYPE_LABELS: Record<string, string> = {
  particulier: 'Particulier', eleveur: 'Éleveur', association: 'Association',
  veterinaire: 'Vétérinaire', sante: 'Santé', education: 'Éducation',
  garde: 'Garde', pension: 'Pension', toilettage: 'Toilettage',
  photographe: 'Photographe', taxi_animalier: 'Taxi', marechal_ferrant: 'Maréchal-ferrant',
};

export function typeBadge(t: string | null | undefined) {
  if (!t) return null;
  return <Badge label={TYPE_LABELS[t] ?? t} color={TYPE_COLORS[t] ?? '#64748b'} />;
}

export const ESPECES = ['chien', 'chat', 'cheval', 'lapin', 'oiseau', 'nac', 'furet', 'rongeur', 'autre'];

export function fmtDate(d: string | null | undefined) {
  if (!d) return '—';
  try { return new Date(d).toLocaleDateString('fr-FR'); } catch { return '—'; }
}

export function downloadCsv(filename: string, rows: (string | number | null | undefined)[][]) {
  const esc = (v: string | number | null | undefined) => {
    const s = v === null || v === undefined ? '' : String(v);
    return /[";\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const csv = rows.map(r => r.map(esc).join(';')).join('\r\n');
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = filename;
  document.body.appendChild(a); a.click(); a.remove();
  URL.revokeObjectURL(url);
}
