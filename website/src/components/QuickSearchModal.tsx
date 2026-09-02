'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';

const TEAL = '#0C5C6C';

export interface QuickSearchItem {
  href: string;
  label: string;
  section: string;
  icon: string;
  keywords?: string[];
}

// ── Normalisation + scoring ──────────────────────────────────────────────────

const ACCENTS: Record<string, string> = {
  à: 'a', â: 'a', ä: 'a', á: 'a', ã: 'a', ç: 'c',
  é: 'e', è: 'e', ê: 'e', ë: 'e', î: 'i', ï: 'i', í: 'i',
  ô: 'o', ö: 'o', ó: 'o', õ: 'o', ù: 'u', û: 'u', ü: 'u', ú: 'u',
  ñ: 'n', œ: 'oe', æ: 'ae',
};

function norm(s: string): string {
  return s
    .toLowerCase()
    .split('')
    .map((c) => ACCENTS[c] ?? c)
    .join('')
    .replace(/[^a-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function levenshtein(a: string, b: string): number {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  let cur = new Array<number>(b.length + 1).fill(0);
  for (let i = 0; i < a.length; i++) {
    cur[0] = i + 1;
    for (let j = 0; j < b.length; j++) {
      const cost = a[i] === b[j] ? 0 : 1;
      cur[j + 1] = Math.min(cur[j] + 1, prev[j + 1] + 1, prev[j] + cost);
    }
    [prev, cur] = [cur, prev];
  }
  return prev[b.length];
}

function score(item: QuickSearchItem, q: string, qTokens: string[]): number {
  const label = norm(item.label);
  const kws = (item.keywords ?? []).map(norm);
  let best = 0;

  if (label === q) best = 1000;
  else if (label.startsWith(q)) best = 600;
  else if (label.includes(q)) best = 420;

  for (const k of kws) {
    if (k === q) best = Math.max(best, 380);
    else if (k.startsWith(q)) best = Math.max(best, 300);
    else if (k.includes(q)) best = Math.max(best, 220);
  }

  const hay = `${label} ${kws.join(' ')} ${norm(item.section)}`;
  if (qTokens.length > 1 && qTokens.every((t) => hay.includes(t))) {
    best = Math.max(best, 340);
  }

  if (best === 0 && q.length >= 4) {
    for (const word of hay.split(' ')) {
      if (word.length < 3) continue;
      const d = levenshtein(q, word);
      if (d <= 2) best = Math.max(best, 120 - d * 30);
    }
    for (const tok of qTokens) {
      if (tok.length < 4) continue;
      for (const word of hay.split(' ')) {
        if (word.length < 3) continue;
        if (levenshtein(tok, word) <= 1) best = Math.max(best, 90);
      }
    }
  }

  return best;
}

// ── Modal ────────────────────────────────────────────────────────────────────

export default function QuickSearchModal({
  open,
  onClose,
  items,
}: {
  open: boolean;
  onClose: () => void;
  items: QuickSearchItem[];
}) {
  const router = useRouter();
  const [q, setQ] = useState('');
  const [active, setActive] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open) {
      setQ('');
      setActive(0);
      setTimeout(() => inputRef.current?.focus(), 40);
    }
  }, [open]);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    if (open) document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  const qn = norm(q);
  const results = useMemo(() => {
    if (!qn) {
      // Regroupé par section quand la recherche est vide (= plan du menu)
      return items;
    }
    const qTokens = qn.split(' ').filter(Boolean);
    return items
      .map((it) => ({ it, s: score(it, qn, qTokens) }))
      .filter((e) => e.s > 0)
      .sort((a, b) => b.s - a.s)
      .map((e) => e.it);
  }, [qn, items]);

  useEffect(() => {
    setActive(0);
  }, [qn]);

  if (!open) return null;

  const go = (href: string) => {
    onClose();
    router.push(href);
  };

  const onInputKey = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setActive((a) => Math.min(a + 1, results.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setActive((a) => Math.max(a - 1, 0));
    } else if (e.key === 'Enter' && results[active]) {
      e.preventDefault();
      go(results[active].href);
    }
  };

  const grouped = !qn;

  return (
    <div
      className="fixed inset-0 z-[100] bg-black/40 flex items-start justify-center p-4 sm:pt-24"
      onClick={onClose}
    >
      <div
        className="bg-white rounded-2xl w-full max-w-lg shadow-2xl overflow-hidden flex flex-col max-h-[80vh]"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-2 px-4 py-3 border-b border-gray-100">
          <svg className="w-5 h-5 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-4.35-4.35M17 11a6 6 0 11-12 0 6 6 0 0112 0z" />
          </svg>
          <input
            ref={inputRef}
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={onInputKey}
            placeholder="Rechercher une fonctionnalité…"
            className="flex-1 text-sm outline-none bg-transparent text-[#1F2A2E] placeholder:text-gray-400"
            style={{ fontFamily: 'Galey, sans-serif' }}
          />
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-lg leading-none flex-shrink-0">
            ✕
          </button>
        </div>

        <div className="overflow-y-auto">
          {results.length === 0 ? (
            <p className="text-center text-gray-400 text-sm py-10 px-6" style={{ fontFamily: 'Galey, sans-serif' }}>
              Aucune fonctionnalité pour «&nbsp;{q}&nbsp;»
            </p>
          ) : grouped ? (
            groupSections(results).map(([section, secItems]) => (
              <div key={section}>
                <p className="px-4 pt-3 pb-1 text-[11px] font-bold uppercase tracking-wide text-gray-400">
                  {section}
                </p>
                {secItems.map((it) => (
                  <Row key={it.href + it.label} item={it} onClick={() => go(it.href)} activeRow={false} />
                ))}
              </div>
            ))
          ) : (
            results.map((it, i) => (
              <Row
                key={it.href + it.label}
                item={it}
                onClick={() => go(it.href)}
                activeRow={i === active}
                onHover={() => setActive(i)}
              />
            ))
          )}
        </div>
      </div>
    </div>
  );
}

function groupSections(items: QuickSearchItem[]): [string, QuickSearchItem[]][] {
  const map = new Map<string, QuickSearchItem[]>();
  for (const it of items) {
    const arr = map.get(it.section) ?? [];
    arr.push(it);
    map.set(it.section, arr);
  }
  return Array.from(map.entries());
}

function Row({
  item,
  onClick,
  activeRow,
  onHover,
}: {
  item: QuickSearchItem;
  onClick: () => void;
  activeRow: boolean;
  onHover?: () => void;
}) {
  return (
    <button
      onClick={onClick}
      onMouseEnter={onHover}
      className={`w-full flex items-center gap-3 px-4 py-2.5 text-left transition-colors ${
        activeRow ? 'bg-[#0C5C6C]/8' : 'hover:bg-gray-50'
      }`}
    >
      <span
        className="w-8 h-8 rounded-lg flex items-center justify-center text-base flex-shrink-0"
        style={{ background: `${TEAL}14` }}
      >
        {item.icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-semibold text-[#1F2A2E] truncate">{item.label}</span>
        <span className="block text-[11px] text-gray-400 truncate">{item.section}</span>
      </span>
      <svg className="w-4 h-4 text-gray-300 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
      </svg>
    </button>
  );
}
