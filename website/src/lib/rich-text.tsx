'use client';

import React from 'react';

/**
 * Mise en forme légère pour les textes du module éducateur (déroulé d'exercice,
 * compte rendu de séance, bilan, note d'objectif). L'éditeur visuel du site
 * produit un fragment HTML simple ; on l'assainit à l'affichage (liste blanche
 * stricte de balises / styles). Un texte brut sans balise reste rendu tel quel.
 */

const ALLOWED_TAGS = new Set(['B', 'STRONG', 'I', 'EM', 'U', 'BR', 'P', 'DIV', 'SPAN', 'UL', 'OL', 'LI', 'FONT']);

export function isRichText(s: string | null | undefined): boolean {
  return !!s && /<(\/?)(b|strong|i|em|u|span|p|div|br|ul|ol|li|font)\b/i.test(s);
}

/** Texte nu d'un fragment (pour les gardes de formulaire / aperçus). */
export function richTextToPlain(html: string | null | undefined): string {
  const s = html ?? '';
  if (!isRichText(s)) return s;
  if (typeof window === 'undefined' || typeof DOMParser === 'undefined') {
    return s.replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ');
  }
  const d = new DOMParser().parseFromString(s, 'text/html');
  return (d.body.textContent ?? '').replace(/ /g, ' ');
}

/** Un fragment contentEditable vide vaut souvent `<br>` ou `<div><br></div>`. */
export function richTextIsEmpty(html: string | null | undefined): boolean {
  return richTextToPlain(html).trim().length === 0;
}

/** Ne conserve qu'une couleur / alignement sûrs dans un attribut style. */
function safeStyle(raw: string | null): string {
  if (!raw) return '';
  const out: string[] = [];
  const color = /color\s*:\s*(#[0-9a-fA-F]{3,8}|rgba?\([\d.,\s]*\))/i.exec(raw);
  if (color) out.push(`color:${color[1]}`);
  const align = /text-align\s*:\s*(left|right|center|justify)/i.exec(raw);
  if (align) out.push(`text-align:${align[1]}`);
  const weight = /font-weight\s*:\s*(bold|[5-9]00)/i.exec(raw);
  if (weight) out.push('font-weight:bold');
  if (/font-style\s*:\s*italic/i.test(raw)) out.push('font-style:italic');
  if (/text-decoration[^;]*underline/i.test(raw)) out.push('text-decoration:underline');
  return out.join(';');
}

function sanitizeNode(node: Node, out: Document): Node | null {
  if (node.nodeType === Node.TEXT_NODE) {
    return out.createTextNode(node.textContent ?? '');
  }
  if (node.nodeType !== Node.ELEMENT_NODE) return null;
  const el = node as Element;
  if (!ALLOWED_TAGS.has(el.tagName)) {
    // balise interdite : on garde son contenu (aplati)
    const frag = out.createDocumentFragment();
    el.childNodes.forEach(child => {
      const c = sanitizeNode(child, out);
      if (c) frag.appendChild(c);
    });
    return frag;
  }
  // <font color="…"> (execCommand hérité) → <span style="color:…">
  const tagName = el.tagName === 'FONT' ? 'span' : el.tagName.toLowerCase();
  const clean = out.createElement(tagName);
  let style = safeStyle(el.getAttribute('style'));
  const fontColor = el.tagName === 'FONT' ? el.getAttribute('color') : null;
  if (fontColor && /^#[0-9a-fA-F]{3,8}$|^rgb/.test(fontColor)) {
    style = style ? `${style};color:${fontColor}` : `color:${fontColor}`;
  }
  if (style) clean.setAttribute('style', style);
  el.childNodes.forEach(child => {
    const c = sanitizeNode(child, out);
    if (c) clean.appendChild(c);
  });
  return clean;
}

export function sanitizeRichText(html: string): string {
  if (typeof window === 'undefined' || typeof DOMParser === 'undefined') {
    // SSR / fallback : on retire toutes les balises
    return html.replace(/<[^>]*>/g, '');
  }
  const doc = new DOMParser().parseFromString(`<body>${html}</body>`, 'text/html');
  const result = document.implementation.createHTMLDocument('');
  const container = result.createElement('div');
  doc.body.childNodes.forEach(child => {
    const c = sanitizeNode(child, result);
    if (c) container.appendChild(c);
  });
  return container.innerHTML;
}

/** Affiche un texte éventuellement mis en forme. */
export function RichText({ value, className = '' }: { value: string | null | undefined; className?: string }) {
  const text = value ?? '';
  if (!isRichText(text)) {
    return <p className={`whitespace-pre-wrap ${className}`}>{text}</p>;
  }
  return (
    <div
      className={`rich-text ${className}`}
      dangerouslySetInnerHTML={{ __html: sanitizeRichText(text) }}
    />
  );
}

const COLORS = [
  '#1F2A2E', '#6B7280', '#EF6C00', '#F5A623', '#C62828', '#E11D48',
  '#2E7D32', '#0C5C6C', '#1D4ED8', '#6A1B9A', '#9D174D', '#7C4A21',
];

/**
 * Éditeur visuel minimaliste (contentEditable + execCommand). Produit un
 * fragment HTML simple transmis via `onChange`. Volontairement sans dépendance.
 */
export function RichTextEditor({
  value,
  onChange,
  placeholder,
  minHeight = 160,
}: {
  value: string;
  onChange: (html: string) => void;
  placeholder?: string;
  minHeight?: number;
}) {
  const ref = React.useRef<HTMLDivElement>(null);
  const [showColors, setShowColors] = React.useState(false);
  const [customColor, setCustomColor] = React.useState('#EF6C00');

  // Initialise le contenu une seule fois (évite de casser le curseur en frappe).
  React.useEffect(() => {
    if (ref.current && ref.current.innerHTML !== value) {
      ref.current.innerHTML = value || '';
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function exec(cmd: string, arg?: string) {
    ref.current?.focus();
    // Couleur → <span style="color:…"> (styleWithCSS). Gras/italique/souligné →
    // vraies balises <b>/<i>/<u> (plus simples à rendre et à assainir).
    try { document.execCommand('styleWithCSS', false, cmd === 'foreColor' ? 'true' : 'false'); } catch { /* Safari */ }
    document.execCommand(cmd, false, arg);
    if (ref.current) onChange(ref.current.innerHTML);
  }

  const btn = 'px-2 py-1 rounded text-sm hover:bg-gray-100 text-gray-600';
  return (
    <div className="border border-gray-200 rounded-xl overflow-hidden">
      <div className="flex flex-wrap items-center gap-0.5 border-b border-gray-100 bg-gray-50 px-1.5 py-1">
        <button type="button" onClick={() => exec('bold')} className={`${btn} font-bold`} title="Gras">B</button>
        <button type="button" onClick={() => exec('italic')} className={`${btn} italic`} title="Italique">I</button>
        <button type="button" onClick={() => exec('underline')} className={`${btn} underline`} title="Souligné">U</button>
        <span className="w-px h-4 bg-gray-200 mx-1" />
        <button type="button" onClick={() => exec('insertUnorderedList')} className={btn} title="Liste à puces">• —</button>
        <span className="w-px h-4 bg-gray-200 mx-1" />
        <div className="relative">
          <button type="button" onClick={() => setShowColors(v => !v)} className={btn} title="Couleur">
            <span className="inline-block w-3.5 h-3.5 rounded-sm align-middle" style={{ background: 'linear-gradient(135deg,#EF6C00,#0C5C6C)' }} />
          </button>
          {showColors && (
            <div className="absolute z-10 mt-1 w-40 bg-white border border-gray-200 rounded-lg p-2 shadow-sm">
              <div className="grid grid-cols-6 gap-1.5">
                {COLORS.map(c => (
                  <button key={c} type="button" title={c}
                    onClick={() => { exec('foreColor', c); setShowColors(false); }}
                    className="w-5 h-5 rounded-full border border-gray-200" style={{ background: c }} />
                ))}
              </div>
              <label className="mt-2 flex items-center gap-1.5 text-[11px] text-gray-500 cursor-pointer">
                <input type="color" value={customColor}
                  onChange={e => setCustomColor(e.target.value)}
                  className="w-5 h-5 rounded border border-gray-200 bg-transparent p-0 cursor-pointer" />
                Couleur personnalisée
              </label>
              <button type="button"
                onClick={() => { exec('foreColor', customColor); setShowColors(false); }}
                className="mt-1.5 w-full text-[11px] text-white rounded py-1" style={{ background: customColor }}>
                Appliquer
              </button>
              <button type="button"
                onClick={() => { exec('foreColor', '#1F2A2E'); setShowColors(false); }}
                className="mt-1 w-full text-[11px] text-gray-500 rounded py-1 border border-gray-200">
                Couleur par défaut
              </button>
            </div>
          )}
        </div>
      </div>
      <div
        ref={ref}
        contentEditable
        suppressContentEditableWarning
        onInput={() => ref.current && onChange(ref.current.innerHTML)}
        data-placeholder={placeholder}
        className="rich-text px-3 py-2 text-sm outline-none overflow-y-auto empty:before:content-[attr(data-placeholder)] empty:before:text-gray-400"
        style={{ minHeight }}
      />
    </div>
  );
}
