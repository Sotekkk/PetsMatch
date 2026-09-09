'use client';

import { useEffect, useState, use } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Post {
  id: string;
  uid: string;
  author_profile_id?: string | null;
  texte?: string | null;
  media_url?: string | null;
  created_at?: string | null;
  is_repost?: boolean | null;
  original_post_id?: string | null;
}

interface Author {
  id: string;
  firstname?: string | null;
  lastname?: string | null;
  nom?: string | null;
  profile_type?: string | null;
  avatar_url?: string | null;
  profile_picture_url_pro?: string | null;
}

type State =
  | { status: 'loading' }
  | { status: 'invalid' }
  | { status: 'ok'; post: Post; author: Author | null; medias: string[] };

const TYPE_LABEL: Record<string, string> = {
  eleveur: 'Éleveur',
  association: 'Association',
  veterinaire: 'Vétérinaire / Ostéo',
  sante: 'Vétérinaire / Ostéo',
  education: 'Éducateur',
  garde: 'Pet Sitter',
  toilettage: 'Toiletteur',
  photographe: 'Photographe',
  pension: 'Pension',
};

function mediaUrls(raw?: string | null): string[] {
  if (!raw) return [];
  if (raw.startsWith('[')) {
    try {
      const arr = JSON.parse(raw);
      return Array.isArray(arr) ? arr.filter((u) => typeof u === 'string') : [];
    } catch {
      return [];
    }
  }
  return [raw];
}

function authorName(a: Author | null): string {
  if (!a) return 'Membre';
  const struct = (a.nom ?? '').trim();
  const person = `${a.firstname ?? ''} ${a.lastname ?? ''}`.trim();
  const isPro = !!a.profile_type && a.profile_type !== 'particulier';
  if (isPro && struct) return struct;
  if (person) return person;
  return struct || 'Membre';
}

function authorPhoto(a: Author | null): string | null {
  if (!a) return null;
  const isPro = !!a.profile_type && a.profile_type !== 'particulier';
  if (isPro) return a.profile_picture_url_pro || a.avatar_url || null;
  return a.avatar_url || null;
}

export default function SharedPostPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [state, setState] = useState<State>({ status: 'loading' });

  useEffect(() => {
    if (!id) {
      setState({ status: 'invalid' });
      return;
    }
    load(id);
  }, [id]);

  async function load(postId: string) {
    try {
      const { data: row, error } = await supabase
        .from('posts_socialmedia')
        .select('id, uid, author_profile_id, texte, media_url, created_at, is_repost, original_post_id')
        .eq('id', postId)
        .maybeSingle();

      if (error || !row) {
        setState({ status: 'invalid' });
        return;
      }

      let post = row as Post;

      // Repost → on affiche le contenu et l'auteur du post original.
      if (post.is_repost && post.original_post_id) {
        const { data: orig } = await supabase
          .from('posts_socialmedia')
          .select('id, uid, author_profile_id, texte, media_url, created_at')
          .eq('id', post.original_post_id)
          .maybeSingle();
        if (orig) post = { ...(orig as Post), is_repost: false, original_post_id: null };
      }

      let author: Author | null = null;
      if (post.author_profile_id) {
        const { data } = await supabase
          .from('user_profiles')
          .select('id, firstname, lastname, nom, profile_type, avatar_url, profile_picture_url_pro')
          .eq('id', post.author_profile_id)
          .maybeSingle();
        author = data as Author | null;
      }
      if (!author) {
        const { data } = await supabase
          .from('user_profiles')
          .select('id, firstname, lastname, nom, profile_type, avatar_url, profile_picture_url_pro')
          .eq('uid', post.uid)
          .eq('profile_type', 'particulier')
          .maybeSingle();
        author = data as Author | null;
      }

      setState({ status: 'ok', post, author, medias: mediaUrls(post.media_url) });
    } catch {
      setState({ status: 'invalid' });
    }
  }

  if (state.status === 'loading') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-center">
          <div className="w-10 h-10 border-4 border-green-500 border-t-transparent rounded-full animate-spin mx-auto mb-3" />
          <p className="text-gray-500 font-medium">Chargement de la publication…</p>
        </div>
      </div>
    );
  }

  if (state.status === 'invalid') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
        <div className="text-center max-w-sm">
          <div className="text-6xl mb-4">🔒</div>
          <h1 className="text-xl font-bold text-gray-800 mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
            Publication introuvable
          </h1>
          <p className="text-gray-500 text-sm leading-relaxed">
            Ce lien ne mène à aucune publication, ou elle a été supprimée.
          </p>
          <a
            href="/"
            className="mt-6 inline-block bg-green-600 text-white px-6 py-2.5 rounded-full text-sm font-medium hover:bg-green-700 transition-colors"
          >
            Découvrir PetsMatch
          </a>
        </div>
      </div>
    );
  }

  const { post, author, medias } = state;
  const name = authorName(author);
  const photo = authorPhoto(author);
  const typeLabel = author?.profile_type ? TYPE_LABEL[author.profile_type] : null;
  const date = post.created_at
    ? new Date(post.created_at).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })
    : null;

  return (
    <div className="min-h-screen bg-gradient-to-b from-green-50 to-white">
      <div className="bg-white border-b border-gray-100 px-4 py-3 flex items-center gap-2">
        <span className="text-xl font-bold text-green-700" style={{ fontFamily: 'Galey, sans-serif' }}>
          Pets Social
        </span>
        <span className="text-xs text-gray-400 bg-gray-100 px-2 py-0.5 rounded-full ml-auto">
          Publication partagée
        </span>
      </div>

      <div className="max-w-md mx-auto px-4 py-8">
        <OpenInApp postId={post.id} />

        <div className="bg-white rounded-3xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="flex items-center gap-3 p-4">
            {photo ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={photo} alt={name} className="w-11 h-11 rounded-full object-cover" />
            ) : (
              <div className="w-11 h-11 rounded-full bg-green-100 flex items-center justify-center text-lg">🐾</div>
            )}
            <div className="min-w-0">
              <p className="font-bold text-gray-900 truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                {name}
              </p>
              <p className="text-xs text-gray-400">
                {typeLabel ? `${typeLabel}${date ? ' · ' : ''}` : ''}
                {date}
              </p>
            </div>
          </div>

          {post.texte && (
            <p className="px-4 pb-3 text-[15px] text-gray-800 leading-relaxed whitespace-pre-wrap">{post.texte}</p>
          )}

          {medias.length > 0 && (
            <div className={medias.length > 1 ? 'grid grid-cols-2 gap-0.5' : ''}>
              {medias.map((url) => (
                // eslint-disable-next-line @next/next/no-img-element
                <img key={url} src={url} alt="" className="w-full object-cover max-h-[70vh]" />
              ))}
            </div>
          )}
        </div>

        <p className="text-center text-xs text-gray-400 mt-6">
          Publié sur Pets Social, le réseau de la communauté PetsMatch.
        </p>
        <div className="text-center mt-3">
          <Link href="/" className="text-sm text-green-700 font-medium hover:underline">
            En savoir plus sur PetsMatch
          </Link>
        </div>
      </div>
    </div>
  );
}

/**
 * Bandeau « Ouvrir dans l'application ». Sur un téléphone où l'app est installée
 * et les liens vérifiés (Android App Links / iOS Universal Links), ce lien
 * s'ouvre directement dans PetsMatch sans passer par cette page ; le bouton
 * sert de repli quand l'OS n'a pas intercepté le lien (lien collé dans un
 * navigateur intégré, etc.).
 */
function OpenInApp({ postId }: { postId: string }) {
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    setIsMobile(/android|iphone|ipad|ipod/i.test(navigator.userAgent));
  }, []);

  if (!isMobile) return null;

  function open() {
    const ua = navigator.userAgent;
    if (/android/i.test(ua)) {
      window.location.href = `intent://p/${postId}#Intent;scheme=https;host=petsmatchapp.com;package=com.application.petsmatch;end`;
    } else {
      // iOS : le Universal Link, s'il est configuré, ouvre l'app.
      window.location.href = `https://petsmatchapp.com/p/${postId}`;
    }
  }

  return (
    <button
      onClick={open}
      className="w-full mb-4 bg-green-600 text-white rounded-2xl px-4 py-3 text-sm font-semibold flex items-center justify-center gap-2 hover:bg-green-700 transition-colors"
      style={{ fontFamily: 'Galey, sans-serif' }}
    >
      Ouvrir dans l&apos;application PetsMatch
    </button>
  );
}
