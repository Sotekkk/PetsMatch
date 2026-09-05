'use client';

import { useRef, useState } from 'react';

// Miroir web de lib/pages/pro/creneaux_week_grid.dart — mêmes types que
// pro/creneaux/page.tsx (SlotRange/TypePrestation), redéfinis ici en local
// pour rester un composant autonome (typage structurel TS, pas d'import
// croisé nécessaire).
export type TypePrestation = 'individuel' | 'collectif' | null | undefined;
export interface WeekGridRange {
  start: string; // 'HH:MM'
  end: string;
  statut: 'disponible' | 'bloque';
  type?: TypePrestation;
  domicile?: boolean;
}
export interface WeekGridRdv {
  date_heure: string;
  duree_minutes?: number | null;
  motif?: string | null;
}

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';
const ORANGE = '#FF9800';
const JOURS_COURTS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

const HOUR_HEIGHT = 52;
const DAY_COL_WIDTH = 108;
const HEADER_HEIGHT = 28;

function toDateStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function sameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}
function timeToMins(t: string): number {
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
}
function minsToTime(m: number): string {
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

export default function CreneauxWeekGrid({
  days, rangesByDay, rdvsByDay, onCreateRange, onTapRange, startHour = 6, endHour = 22,
}: {
  days: Date[];
  rangesByDay: Record<string, WeekGridRange[]>;
  rdvsByDay: Record<string, WeekGridRdv[]>;
  onCreateRange: (day: Date, start: string, end: string) => void;
  onTapRange: (day: Date, range: WeekGridRange) => void;
  startHour?: number;
  endHour?: number;
}) {
  const totalHeight = (endHour - startHour) * HOUR_HEIGHT;
  const today = new Date();
  const [drag, setDrag] = useState<{ day: Date; startY: number; curY: number } | null>(null);
  const colRefs = useRef<Record<string, HTMLDivElement | null>>({});

  function yToMinutes(y: number): number {
    const minutesFromStart = (y / HOUR_HEIGHT) * 60;
    const snapped = Math.round(minutesFromStart / 15) * 15;
    const total = startHour * 60 + snapped;
    return Math.min(Math.max(total, startHour * 60), endHour * 60);
  }

  function rangeOverlaps(day: Date, startMin: number, endMin: number): boolean {
    const key = toDateStr(day);
    for (const r of rangesByDay[key] ?? []) {
      const rs = timeToMins(r.start), re = timeToMins(r.end);
      if (startMin < re && endMin > rs) return true;
    }
    for (const rdv of rdvsByDay[key] ?? []) {
      const dh = new Date(rdv.date_heure);
      const rs = dh.getHours() * 60 + dh.getMinutes();
      const re = rs + (rdv.duree_minutes ?? 60);
      if (startMin < re && endMin > rs) return true;
    }
    return false;
  }

  function handleMouseDown(day: Date, e: React.MouseEvent<HTMLDivElement>) {
    const rect = e.currentTarget.getBoundingClientRect();
    const y = Math.min(Math.max(e.clientY - rect.top, 0), totalHeight);
    setDrag({ day, startY: y, curY: y });

    function onMove(ev: MouseEvent) {
      const y2 = Math.min(Math.max(ev.clientY - rect.top, 0), totalHeight);
      setDrag(d => (d ? { ...d, curY: y2 } : d));
    }
    function onUp(ev: MouseEvent) {
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup', onUp);
      const y2 = Math.min(Math.max(ev.clientY - rect.top, 0), totalHeight);
      const a = yToMinutes(y);
      const b = yToMinutes(y2);
      const startMin = Math.min(a, b);
      const endMin = Math.max(a, b) <= startMin ? startMin + 15 : Math.max(a, b);
      if (!rangeOverlaps(day, startMin, endMin)) {
        onCreateRange(day, minsToTime(startMin), minsToTime(endMin));
      }
      setDrag(null);
    }
    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
  }

  return (
    <div className="overflow-x-auto">
      <div className="flex items-start" style={{ minWidth: 34 + days.length * DAY_COL_WIDTH }}>
        {/* Colonne des heures — fixe, défile verticalement avec la grille */}
        <div style={{ width: 34, flexShrink: 0 }}>
          <div style={{ height: HEADER_HEIGHT }} />
          <div style={{ height: totalHeight, position: 'relative' }}>
            {Array.from({ length: endHour - startHour }, (_, i) => startHour + i).map(h => (
              <div key={h} style={{ position: 'absolute', top: (h - startHour) * HOUR_HEIGHT - 7, right: 4 }}
                className="text-[10px] font-galey text-gray-400">
                {h}h
              </div>
            ))}
          </div>
        </div>
        {days.map(day => {
          const key = toDateStr(day);
          const ranges = rangesByDay[key] ?? [];
          const rdvs = rdvsByDay[key] ?? [];
          const isDragDay = drag?.day && sameDay(drag.day, day);
          return (
            <div key={key} style={{ width: DAY_COL_WIDTH, flexShrink: 0 }}>
              <div style={{ height: HEADER_HEIGHT }} className="flex items-center justify-center">
                <span className="text-[11px] font-galey font-bold px-2 py-0.5 rounded-full"
                  style={{ background: sameDay(day, today) ? TEAL : 'transparent', color: sameDay(day, today) ? 'white' : '#1F2937' }}>
                  {JOURS_COURTS[day.getDay() === 0 ? 6 : day.getDay() - 1]} {day.getDate()}
                </span>
              </div>
              <div
                ref={el => { colRefs.current[key] = el; }}
                onMouseDown={e => handleMouseDown(day, e)}
                className="relative mx-0.5 rounded-md border border-gray-100 select-none cursor-crosshair"
                style={{ height: totalHeight }}
              >
                {Array.from({ length: endHour - startHour - 1 }, (_, i) => i + 1).map(h => (
                  <div key={h} className="absolute left-0 right-0 border-t border-gray-50" style={{ top: h * HOUR_HEIGHT }} />
                ))}
                {ranges.map((r, i) => {
                  const top = (timeToMins(r.start) - startHour * 60) / 60 * HOUR_HEIGHT;
                  const bottom = (timeToMins(r.end) - startHour * 60) / 60 * HOUR_HEIGHT;
                  const isDisp = r.statut === 'disponible';
                  const color = isDisp ? GREEN : ORANGE;
                  return (
                    <div key={i} onClick={() => onTapRange(day, r)}
                      className="absolute left-0.5 right-0.5 px-1 py-0.5 text-[9px] font-galey font-bold cursor-pointer overflow-hidden"
                      style={{ top, height: Math.max(bottom - top, 10), background: `${color}2E`, borderLeft: `3px solid ${color}`, color: isDisp ? '#4A7A32' : '#E65100' }}>
                      {r.start}{r.domicile ? ' 🏠' : ''}{r.type === 'collectif' ? ' 👥' : r.type === 'individuel' ? ' 🎓' : ''}
                    </div>
                  );
                })}
                {rdvs.map((rdv, i) => {
                  const dh = new Date(rdv.date_heure);
                  const startMin = dh.getHours() * 60 + dh.getMinutes();
                  const endMin = startMin + (rdv.duree_minutes ?? 60);
                  const top = (startMin - startHour * 60) / 60 * HOUR_HEIGHT;
                  const bottom = (endMin - startHour * 60) / 60 * HOUR_HEIGHT;
                  return (
                    <div key={i} className="absolute left-0.5 right-0.5 px-1 py-0.5 text-[9px] font-galey font-bold overflow-hidden pointer-events-none"
                      style={{ top, height: Math.max(bottom - top, 10), background: `${TEAL}22`, borderLeft: `3px solid ${TEAL}`, color: TEAL }}>
                      {rdv.motif || 'RDV'}
                    </div>
                  );
                })}
                {isDragDay && drag && (() => {
                  const a = yToMinutes(drag.startY), b = yToMinutes(drag.curY);
                  const startMin = Math.min(a, b), endMin = Math.max(Math.max(a, b), startMin + 15);
                  const top = (startMin - startHour * 60) / 60 * HOUR_HEIGHT;
                  const bottom = (endMin - startHour * 60) / 60 * HOUR_HEIGHT;
                  return (
                    <div className="absolute left-0.5 right-0.5 flex items-center justify-center text-[9px] font-galey font-bold pointer-events-none"
                      style={{ top, height: Math.max(bottom - top, 10), background: `${TEAL}40`, border: `1.5px solid ${TEAL}`, color: TEAL }}>
                      {minsToTime(startMin)}–{minsToTime(endMin)}
                    </div>
                  );
                })()}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
