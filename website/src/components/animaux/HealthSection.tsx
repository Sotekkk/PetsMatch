'use client';

import { useState, ReactNode } from 'react';

interface Props {
  title: string;
  icon: string;
  color: string;
  count: number;
  children: ReactNode;
  onAdd?: () => void;
  addForm?: ReactNode;
  addFormOpen?: boolean;
}

export default function HealthSection({ title, icon, color, count, children, onAdd, addForm, addFormOpen }: Props) {
  const [open, setOpen] = useState(false);

  return (
    <div className="bg-white rounded-2xl overflow-hidden shadow-sm">
      <div
        role="button" tabIndex={0}
        onClick={() => setOpen(!open)}
        onKeyDown={e => e.key === 'Enter' && setOpen(!open)}
        className="w-full flex items-center gap-3 p-4 hover:bg-gray-50 transition-colors cursor-pointer">
        <div className="w-10 h-10 rounded-xl flex items-center justify-center text-xl flex-shrink-0"
          style={{ backgroundColor: color + '20' }}>
          {icon}
        </div>
        <div className="flex-1 text-left">
          <p className="font-semibold text-[#1F2A2E] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>{title}</p>
          <p className="text-xs" style={{ color }}>{count} enregistrement{count !== 1 ? 's' : ''}</p>
        </div>
        <div className="flex items-center gap-2">
          {onAdd && (
            <button
              onClick={(e) => { e.stopPropagation(); onAdd(); }}
              className="w-7 h-7 rounded-full flex items-center justify-center text-white text-sm transition-colors hover:opacity-80"
              style={{ backgroundColor: color }}>
              +
            </button>
          )}
          <svg className={`w-4 h-4 text-gray-400 transition-transform ${open ? 'rotate-180' : ''}`}
            fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
          </svg>
        </div>
      </div>

      {open && (
        <div className="border-t border-gray-100">
          {addFormOpen && addForm && (
            <div className="p-4 bg-gray-50 border-b border-gray-100">{addForm}</div>
          )}
          <div className="divide-y divide-gray-50">{children}</div>
        </div>
      )}
    </div>
  );
}
