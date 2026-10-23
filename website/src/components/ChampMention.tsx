'use client';

import { useEffect, useRef, useState } from 'react';
import { supabase } from '@/lib/supabase';

// @mentions — même format que l'appli (lib/widgets/mention_hashtag.dart) :
// stockées dans le texte sous la forme `@[Nom affiché](profileId)`. La
// notification de la personne citée est créée par la base (forum :
// trg_forum_sujet_notifs / trg_forum_reponse_notifs).

const MENTION = /@\[([^\]]+)\]\(([^)]+)\)/g;

type Profil = { id: string; nom: string; avatar: string | null };

/** Texte lisible : `@[Nom](id)` → `@Nom` (aperçus, listes). */
export function mentionsEnTexte(texte: string): string {
  return texte.replace(MENTION, (_, nom: string) => `@${nom}`);
}

/** Affichage d'un texte avec mentions mises en valeur (« @Nom »). */
export function TexteAvecMentions({ texte }: { texte: string }) {
  const morceaux: React.ReactNode[] = [];
  let dernier = 0;
  for (const m of texte.matchAll(MENTION)) {
    const i = m.index ?? 0;
    if (i > dernier) morceaux.push(texte.slice(dernier, i));
    morceaux.push(
      <span key={i} className="font-semibold text-[#1565C0]">@{m[1]}</span>,
    );
    dernier = i + m[0].length;
  }
  if (dernier < texte.length) morceaux.push(texte.slice(dernier));
  return <>{morceaux}</>;
}

function nomProfil(p: Record<string, unknown>): string {
  const pseudo = String(p.social_pseudo ?? '').trim();
  const prenomNom = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim();
  return pseudo || prenomNom || String(p.nom ?? '').trim() || 'Profil';
}

/** Champ texte avec @mentions : taper « @ » puis un nom propose des profils ;
 *  le texte saisi garde « @Nom », converti en `@[Nom](id)` par `versBalisage`. */
export default function ChampMention({ valeur, onChange, noms, placeholder, multiligne = false, lignes = 4, className, onEntree, uidExclu }: {
  valeur: string;
  /** Noms choisis dans la liste → identifiant de profil (tenu par la page,
   *  passé à versBalisage au moment de l'envoi). */
  noms: Map<string, string>;
  onChange: (v: string) => void;
  placeholder?: string;
  multiligne?: boolean;
  lignes?: number;
  className?: string;
  onEntree?: () => void;
  uidExclu?: string;
}) {
  const [suggestions, setSuggestions] = useState<Profil[]>([]);
  const [requete, setRequete] = useState<string | null>(null);
  const ref = useRef<HTMLInputElement & HTMLTextAreaElement>(null);

  // Mot en cours de frappe juste avant le curseur : « @dup » → recherche « dup ».
  function analyser(texte: string, curseur: number) {
    const avant = texte.slice(0, curseur);
    const m = avant.match(/(?:^|\s)@([\p{L}0-9_-]{2,30})$/u);
    setRequete(m ? m[1] : null);
  }

  useEffect(() => {
    if (!requete) { setSuggestions([]); return; }
    let annule = false;
    const q = requete.replace(/[%,()]/g, '');
    const t = setTimeout(async () => {
      let b = supabase.from('user_profiles_complet')
        .select('id, uid, firstname, lastname, nom, social_pseudo, avatar_url, profile_picture_url_pro')
        .or(`firstname.ilike.%${q}%,lastname.ilike.%${q}%,nom.ilike.%${q}%,social_pseudo.ilike.%${q}%`);
      if (uidExclu) b = b.neq('uid', uidExclu);
      const { data } = await b.limit(6);
      if (annule) return;
      setSuggestions(((data ?? []) as Record<string, unknown>[]).map(p => ({
        id: String(p.id), nom: nomProfil(p),
        avatar: (p.avatar_url as string | null) ?? (p.profile_picture_url_pro as string | null) ?? null,
      })));
    }, 250);
    return () => { annule = true; clearTimeout(t); };
  }, [requete, uidExclu]);

  function choisir(p: Profil) {
    const el = ref.current;
    const curseur = el?.selectionStart ?? valeur.length;
    const avant = valeur.slice(0, curseur).replace(/@([\p{L}0-9_-]{2,30})$/u, `@${p.nom} `);
    const apres = valeur.slice(curseur);
    noms.set(p.nom, p.id);
    onChange(avant + apres);
    setRequete(null);
    setSuggestions([]);
    requestAnimationFrame(() => { el?.focus(); el?.setSelectionRange(avant.length, avant.length); });
  }

  const commun = {
    ref,
    value: valeur,
    placeholder,
    className,
    style: { fontFamily: 'Galey, sans-serif' },
    onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
      onChange(e.target.value);
      analyser(e.target.value, e.target.selectionStart ?? e.target.value.length);
    },
    onKeyDown: (e: React.KeyboardEvent) => {
      if (suggestions.length && (e.key === 'Enter' || e.key === 'Tab')) { e.preventDefault(); choisir(suggestions[0]); return; }
      if (e.key === 'Escape') { setRequete(null); return; }
      if (!multiligne && e.key === 'Enter' && !e.shiftKey && onEntree) { e.preventDefault(); onEntree(); }
    },
  };

  return (
    <div className="relative flex-1 min-w-0">
      {multiligne
        ? <textarea {...commun} rows={lignes} />
        : <input {...commun} />}
      {suggestions.length > 0 && (
        <div className="absolute left-0 right-0 bottom-full mb-1 bg-white border border-gray-200 rounded-xl shadow-lg z-10 overflow-hidden">
          {suggestions.map(p => (
            <button key={p.id} type="button" onMouseDown={e => { e.preventDefault(); choisir(p); }}
              className="w-full flex items-center gap-2 px-3 py-2 text-left text-sm hover:bg-gray-50">
              {p.avatar
                // eslint-disable-next-line @next/next/no-img-element
                ? <img src={p.avatar} alt="" className="w-6 h-6 rounded-full object-cover" />
                : <span className="w-6 h-6 rounded-full bg-[#0C5C6C]/10 text-[#0C5C6C] text-xs font-bold flex items-center justify-center">{p.nom[0]?.toUpperCase()}</span>}
              {p.nom}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** Texte prêt à enregistrer : chaque « @Nom » choisi dans la liste devient
 *  `@[Nom](id)` (format partagé avec l'appli). */
export function versBalisage(texte: string, noms: Map<string, string>): string {
  let t = texte;
  for (const [nom, id] of noms) {
    t = t.split(`@${nom}`).join(`@[${nom}](${id})`);
  }
  return t;
}
