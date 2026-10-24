'use client';

import { Suspense, useEffect, useRef, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { collection, addDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import VerificationBadge, { getBadgeLevel } from '@/components/VerificationBadge';
import { resultatChipClass, testChipLabel, type TestGenetique } from '@/lib/genetics';
import { Icone, Puce, BORDURE } from '@/components/dashboard/kit';
import { TEINTES_STATUT } from '@/components/annonces/GestionAnnonces';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Bebe {
  nom?: string; sexe?: string; couleur?: string; couleur_yeux?: string; prix?: number;
  statut?: string; photos?: string[]; description?: string; pedigree?: boolean;
}

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  espece_autre?: string;
  race?: string;
  type?: string;
  type_vente?: string;
  photos?: string[];
  animaux_portee?: Bebe[];
  prix?: number;
  prix_unite?: string;
  saillie_prix?: number;
  prix_min_portee?: number;
  prix_max_portee?: number;
  niveau_recommande?: string;
  palmares?: string;
  indice_iso?: number;
  indice_idr?: number;
  indice_icc?: number;
  video_monte_url?: string;
  video_libre_url?: string;
  ville_eleveur?: string;
  sexe?: string;
  couleur?: string;
  couleur_yeux?: string;
  nom_eleveur?: string;
  uid_eleveur?: string;
  description?: string;
  registre_type?: string;
  date_naissance?: string;
  date_naissance_animal?: string;
  age_estime?: boolean;
  saillie_conditions?: string;
  saillie_genetique?: string;
  etalon_animal_id?: string;
  pere_animal_id?: string;
  mere_animal_id?: string;
  mere_nom?: string; mere_puce?: string; mere_race?: string;
  mere_photo_url?: string; mere_couleur?: string; mere_couleur_yeux?: string; mere_description?: string; mere_registre?: string;
  pere_nom?: string; pere_puce?: string; pere_race?: string;
  pere_photo_url?: string; pere_couleur?: string; pere_couleur_yeux?: string; pere_description?: string; pere_registre?: string;
  nb_attendu?: number; nb_nes?: number;
  statut?: string;
  sterilise?: boolean;
  expire_at?: string;
  created_at?: string;
  profil_source?: string;
  profile_id?: string;
  boost_until?: string;
  vaccines?: boolean; vermifuge?: boolean; identification?: boolean; bilan_sante?: boolean; semaines?: number;
  numero_registre?: string; club_pedigree?: string; studbook?: string; prix_negociable?: boolean;
}

interface AssoData {
  nom: string;
  avatar: string;
  ville: string;
}

interface ProData {
  profile_picture_url_elevage?: string;
  name_elevage?: string;
  ville_elevage?: string;
  pays_elevage?: string;
  statut_pro?: string;
  siret?: string;
  is_premium?: boolean;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmtDate(iso?: string) {
  if (!iso) return null;
  const d = new Date(iso);
  if (isNaN(d.getTime())) return null;
  return d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

function ageLabel(dateStr?: string): string | null {
  if (!dateStr) return null;
  const days = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (days < 0) return 'À naître';
  if (days < 91) { const w = Math.floor(days / 7); return w <= 1 ? '1 semaine' : `${w} semaines`; }
  const m = Math.floor(days / 30.44);
  if (m >= 12) { const y = Math.floor(days / 365.25); return y <= 1 ? '1 an' : `${y} ans`; }
  return m <= 1 ? '1 mois' : `${m} mois`;
}

function especeLabel(e?: string, especeAutre?: string) {
  const map: Record<string, string> = {
    chien: 'Chien', chat: 'Chat', lapin: 'Lapin',
    oiseau: 'Oiseau', reptile: 'Reptile', cheval: 'Cheval',
    ane: 'Âne', ovin: 'Ovin', caprin: 'Caprin',
    porcin: 'Porcin', nac: 'NAC', poule: 'Poule',
  };
  if (e?.toLowerCase() === 'autre' && especeAutre) return especeAutre;
  return e ? (map[e.toLowerCase()] ?? e) : '';
}

const STATUT_ANNONCE: Record<string, { label: string; teinte: string }> = {
  disponible: { label: 'Disponible', teinte: 'vert' },
  reserve:    { label: 'Réservé', teinte: 'ambre' },
  vendu:      { label: 'Vendu', teinte: 'bleu' },
  cede:       { label: 'Cédé', teinte: 'teal' },
  pause:      { label: 'En pause', teinte: 'gris' },
  archivee:   { label: 'Archivée', teinte: 'gris' },
  archive:    { label: 'Archivée', teinte: 'gris' },
  expiree:    { label: 'Expirée', teinte: 'rouge' },
  suspendu:   { label: 'Suspendue', teinte: 'rouge' },
  brouillon:  { label: 'Brouillon', teinte: 'gris' },
};

/** Ligne « libellé : valeur » de la carte Informations. */
function Ligne({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-[minmax(0,9rem)_1fr] gap-3 py-1.5 text-[15px]">
      <dt className="text-gray-500">{label}</dt>
      <dd className="text-[#1E2025] min-w-0 break-words">{children}</dd>
    </div>
  );
}

/** Section blanche de la fiche (titre + contenu). */
function Bloc({ titre, aside, children }: { titre: string; aside?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="bg-white rounded-2xl p-5 sm:p-6" style={{ border: `1px solid ${BORDURE}` }}>
      <div className="flex items-baseline justify-between gap-3 mb-3">
        <h2 className="font-bold text-lg sm:text-xl text-[#1E2025]">{titre}</h2>
        {aside}
      </div>
      {children}
    </section>
  );
}

const Fermer = () => <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M6 6l12 12M18 6L6 18" /></svg>;
const Chevron = ({ gauche = false }: { gauche?: boolean }) => <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d={gauche ? 'M15 6l-6 6 6 6' : 'M9 6l6 6-6 6'} /></svg>;

// ── Lightbox ──────────────────────────────────────────────────────────────────

function Lightbox({ photos, initialIdx, onClose }: {
  photos: string[];
  initialIdx: number;
  onClose: () => void;
}) {
  const [idx, setIdx] = useState(initialIdx);
  const closeRef = typeof onClose === 'function' ? onClose : () => {};

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') closeRef();
      if (e.key === 'ArrowLeft')  setIdx(i => (i - 1 + photos.length) % photos.length);
      if (e.key === 'ArrowRight') setIdx(i => (i + 1) % photos.length);
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [photos.length]);

  return (
    <div className="fixed inset-0 z-50 bg-black/92 flex items-center justify-center"
      onClick={closeRef}>
      <div className="relative w-full h-full flex items-center justify-center p-4"
        onClick={e => e.stopPropagation()}>
        {/* Image */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={photos[idx]} alt="" className="max-w-full max-h-full object-contain select-none" draggable={false} />

        {/* Fermer */}
        <button onClick={closeRef}
          aria-label="Fermer"
          className="absolute top-4 right-4 w-10 h-10 rounded-full bg-white/15 text-white flex items-center justify-center hover:bg-white/30 transition-colors">
          <Fermer />
        </button>

        {/* Navigation */}
        {photos.length > 1 && (
          <>
            <button onClick={() => setIdx(i => (i - 1 + photos.length) % photos.length)}
              aria-label="Photo précédente"
              className="absolute left-3 top-1/2 -translate-y-1/2 w-10 h-10 rounded-full bg-white/15 text-white flex items-center justify-center hover:bg-white/30 transition-colors">
              <Chevron gauche />
            </button>
            <button onClick={() => setIdx(i => (i + 1) % photos.length)}
              aria-label="Photo suivante"
              className="absolute right-3 top-1/2 -translate-y-1/2 w-10 h-10 rounded-full bg-white/15 text-white flex items-center justify-center hover:bg-white/30 transition-colors">
              <Chevron />
            </button>
            <div className="absolute bottom-5 left-1/2 -translate-x-1/2 text-white/70 text-sm bg-black/30 px-3 py-1 rounded-full">
              {idx + 1} / {photos.length}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

// ── Modal likers / favoris ────────────────────────────────────────────────────

function LikersModal({ annonceId, bebeIndex, mode, onClose }: {
  annonceId: string;
  bebeIndex?: number;
  mode: 'likes' | 'favoris';
  onClose: () => void;
}) {
  const router = useRouter();
  const [users, setUsers] = useState<{ uid: string; firstname?: string; lastname?: string; profile_picture_url?: string }[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const table = mode === 'likes' ? 'likes' : 'favoris';
    const base = supabase.from(table).select('user_uid').eq('annonce_id', annonceId);
    const filtered = bebeIndex != null
      ? base.eq('bebe_index', bebeIndex)
      : base.is('bebe_index', null);
    filtered.order('created_at', { ascending: false }).then(async ({ data: rows }) => {
      if (!rows?.length) { setLoading(false); return; }
      // Dédupliquer par user_uid (un même compte peut avoir liké depuis plusieurs profils)
      const uids = [...new Set((rows as { user_uid: string }[]).map(r => r.user_uid))];
      const { data: u } = await supabase.from('user_profiles_complet')
        .select('uid, firstname, lastname, profile_picture_url:avatar_url').in('uid', uids).eq('is_main', true);
      setUsers((u ?? []) as typeof users);
      setLoading(false);
    });
  }, [annonceId, bebeIndex, mode]);

  const label = mode === 'likes' ? `j'aime${users.length > 1 ? 's' : ''}` : `favori${users.length > 1 ? 's' : ''}`;

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-end justify-center sm:items-center"
      onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-sm max-h-[70vh] flex flex-col"
        onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <div className="flex items-center gap-2">
            <span className="text-[#E0457B]"><Icone nom="coeur" taille={18} /></span>
            <span className="font-['Galey'] font-bold text-[#1F2A2E]">
              {loading ? '…' : `${users.length} ${label}`}
              {bebeIndex != null && <span className="font-normal text-gray-400 text-xs ml-2">— bébé {bebeIndex + 1}</span>}
            </span>
          </div>
          <button onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors w-7 h-7 flex items-center justify-center">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
              <path d="M18 6L6 18M6 6l12 12"/>
            </svg>
          </button>
        </div>
        <div className="overflow-y-auto flex-1">
          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : users.length === 0 ? (
            <p className="text-center text-gray-400 py-10 text-sm font-['Galey']">
              {mode === 'likes' ? "Aucun j'aime pour le moment" : 'Aucun favori pour le moment'}
            </p>
          ) : (
            users.map(u => (
              <button key={u.uid}
                onClick={() => { onClose(); router.push(`/profil/${u.uid}`); }}
                className="w-full flex items-center gap-3 px-5 py-3 hover:bg-gray-50 transition-colors text-left">
                <div className="w-10 h-10 rounded-full bg-[#0C5C6C] flex items-center justify-center overflow-hidden flex-shrink-0">
                  {u.profile_picture_url ? (
                    <Image src={u.profile_picture_url} alt="" width={40} height={40} className="object-cover" unoptimized />
                  ) : (
                    <span className="text-white text-xs font-bold">{(u.firstname?.[0] ?? '?').toUpperCase()}</span>
                  )}
                </div>
                <span className="font-['Galey'] font-semibold text-sm text-[#1F2A2E] flex-1">
                  {[u.firstname, u.lastname].filter(Boolean).join(' ') || 'Utilisateur'}
                </span>
                <svg className="w-4 h-4 text-gray-300 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7"/>
                </svg>
              </button>
            ))
          )}
        </div>
      </div>
    </div>
  );
}

// ── Bébé card avec carousel ──────────────────────────────────────────────────

function BebeCard({ bebe: b, index, annonceId, uidEleveur, currentUser, onOpenLightbox, onShowLikers }: {
  bebe: Bebe;
  index: number;
  annonceId: string;
  uidEleveur?: string;
  currentUser: { uid: string } | null;
  onOpenLightbox: (photos: string[], idx: number) => void;
  onShowLikers?: () => void;
}) {
  const cardRef = useRef<HTMLDivElement>(null);
  const { activeProfileId } = useAuth();
  const [idx, setIdx] = useState(0);
  const [isLiked, setIsLiked] = useState(false);
  const [likeCount, setLikeCount] = useState(0);
  const [likeLoading, setLikeLoading] = useState(false);
  const photos = (b.photos ?? []).filter(p => p?.startsWith('http'));
  const statut = b.statut ?? 'disponible';
  const statutColor = statut === 'disponible' ? '#6E9E57' : statut === 'reserve' ? '#F59E0B' : '#94A3B8';
  const statutLabel = statut === 'disponible' ? 'Dispo' : statut === 'reserve' ? 'Réservé' : 'Vendu';

  // Tracking vue chiot (une fois quand la carte devient visible)
  useEffect(() => {
    const el = cardRef.current;
    if (!el) return;
    const key = `vue_bebe_${annonceId}_${index}`;
    if (sessionStorage.getItem(key)) return;
    const obs = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) {
        sessionStorage.setItem(key, '1');
        fetch('/api/annonces/stats', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ annonceId, bebeIndex: index }),
        }).catch(() => {});
        obs.disconnect();
      }
    }, { threshold: 0.5 });
    obs.observe(el);
    return () => obs.disconnect();
  }, [annonceId, index]);

  useEffect(() => {
    supabase.from('likes').select('user_uid').eq('annonce_id', annonceId).eq('bebe_index', index)
      .then(({ data: rows }) => {
        if (!rows) return;
        const uniqueUids = [...new Set((rows as { user_uid: string }[]).map(r => r.user_uid))];
        setLikeCount(uniqueUids.length);
        if (currentUser) setIsLiked(uniqueUids.includes(currentUser.uid));
      });
  }, [annonceId, index, currentUser]);

  const toggleLike = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!currentUser) return;
    if (likeLoading) return;
    setLikeLoading(true);
    const wasLiked = isLiked;
    setIsLiked(!wasLiked);
    setLikeCount(c => c + (wasLiked ? -1 : 1));
    try {
      // « J'aime » par profil : on remplace seulement celui du profil actif.
      const base = supabase.from('likes').delete()
        .eq('user_uid', currentUser.uid).eq('annonce_id', annonceId);
      await (activeProfileId ? base.or(`profile_id.eq.${activeProfileId},profile_id.is.null`) : base.is('profile_id', null)).eq('bebe_index', index);
      if (!wasLiked) {
        await supabase.from('likes')
          .insert({ user_uid: currentUser.uid, annonce_id: annonceId, bebe_index: index,
            uid_eleveur: uidEleveur ?? null,
            ...(activeProfileId ? { profile_id: activeProfileId } : {}) });
      }
    } catch {
      setIsLiked(wasLiked);
      setLikeCount(c => c + (wasLiked ? 1 : -1));
    } finally {
      setLikeLoading(false);
    }
  };

  return (
    <div ref={cardRef} className="rounded-xl overflow-hidden bg-white" style={{ border: `1px solid ${BORDURE}` }}>
      <div className="aspect-square relative bg-[#F3F6F5] group"
        onClick={() => photos.length > 0 && onOpenLightbox(photos, idx)}
        style={{ cursor: photos.length > 0 ? 'zoom-in' : 'default' }}>
        {photos.length > 0 ? (
          <Image src={photos[idx]} alt={b.nom || `Bébé ${index + 1}`} fill className="object-cover"
            sizes="(max-width: 672px) 50vw, 336px" />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-[#0C5C6C]"><Icone nom="patte" taille={30} /></div>
        )}
        {/* Flèches navigation */}
        {photos.length > 1 && (
          <>
            <button onClick={e => { e.stopPropagation(); setIdx(i => (i - 1 + photos.length) % photos.length); }}
              aria-label="Photo précédente"
              className="absolute left-1 top-1/2 -translate-y-1/2 w-7 h-7 rounded-full bg-black/40 text-white flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
              <Chevron gauche />
            </button>
            <button onClick={e => { e.stopPropagation(); setIdx(i => (i + 1) % photos.length); }}
              aria-label="Photo suivante"
              className="absolute right-1 top-1/2 -translate-y-1/2 w-7 h-7 rounded-full bg-black/40 text-white flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
              <Chevron />
            </button>
            <div className="absolute bottom-1.5 left-1/2 -translate-x-1/2 flex gap-1">
              {photos.map((_, j) => (
                <button key={j} onClick={e => { e.stopPropagation(); setIdx(j); }}
                  className={`rounded-full transition-all ${j === idx ? 'w-3 h-1.5 bg-white' : 'w-1.5 h-1.5 bg-white/50'}`} />
              ))}
            </div>
          </>
        )}
        <span className="absolute top-2 left-2 text-xs font-bold px-2 py-0.5 rounded-full text-white"
          style={{ background: statutColor }}>
          {statutLabel}
        </span>
        {/* Bouton like */}
        <button
          onClick={toggleLike}
          disabled={likeLoading || !currentUser}
          className="absolute top-2 right-2 flex items-center gap-1 px-2 py-1 rounded-full text-xs font-bold transition-all disabled:opacity-50"
          style={{
            background: isLiked ? 'rgba(239,68,68,0.85)' : 'rgba(0,0,0,0.35)',
            color: 'white',
            backdropFilter: 'blur(4px)',
          }}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill={isLiked ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2" strokeLinejoin="round"><path d="M12 20s-7-4.4-9-9a5 5 0 019-3 5 5 0 019 3c-2 4.6-9 9-9 9z" /></svg>{likeCount > 0 && <span>{likeCount}</span>}
        </button>
      </div>
      <div className="p-2 space-y-0.5">
        <p className="font-['Galey'] font-bold text-sm text-[#1E2025] truncate">{b.nom || `Bébé ${index + 1}`}</p>
        {b.sexe && <p className="text-xs text-gray-600">{b.sexe === 'male' ? 'Mâle' : 'Femelle'}</p>}
        {b.couleur && <p className="text-xs text-gray-500 truncate">Robe : {b.couleur}</p>}
        {b.couleur_yeux && <p className="text-xs text-gray-500 truncate">Yeux : {b.couleur_yeux}</p>}
        {b.prix != null && <p className="font-['Galey'] font-bold text-sm text-[#1E2025]">{b.prix} €</p>}
        {b.description && <p className="text-xs text-gray-500 mt-1 leading-relaxed line-clamp-3">{b.description}</p>}
        {photos.length > 1 && (
          <p className="text-[11px] text-gray-400 mt-0.5">{photos.length} photos</p>
        )}
        {likeCount > 0 && (
          <button onClick={e => { e.stopPropagation(); onShowLikers?.(); }}
            className="text-[11px] text-gray-500 hover:text-[#E0457B] transition-colors mt-0.5">
            {likeCount} j&apos;aime{likeCount > 1 ? 's' : ''}
          </button>
        )}
      </div>
    </div>
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

function AnnonceDetailPageInner() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const searchParams = useSearchParams();
  const selectedBebe = searchParams.get('bebe');
  const { user, activeProfileId } = useAuth();
  const [annonce, setAnnonce] = useState<Annonce | null>(null);
  const [pro, setPro] = useState<ProData | null>(null);
  const [assoData, setAssoData] = useState<AssoData | null>(null);
  const [assoProfileId, setAssoProfileId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [imgIdx, setImgIdx] = useState(0);
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);
  const [etalonTests, setEtalonTests] = useState<TestGenetique[]>([]);
  const [etalonInfo, setEtalonInfo] = useState<{ nb_petits_produits?: number | null; historique_fertilite?: string | null; profil_adn_etabli?: boolean | null } | null>(null);

  // Likes / favoris
  const [likeCount, setLikeCount] = useState(0);
  const [isLiked, setIsLiked] = useState(false);
  const [likeLoading, setLikeLoading] = useState(false);
  const [activeModal, setActiveModal] = useState<{ mode: 'likes' | 'favoris'; bebeIndex?: number } | null>(null);
  const bebeRefs = useRef<(HTMLDivElement | null)[]>([]);

  // Lightbox
  const [lightbox, setLightbox] = useState<{ photos: string[]; idx: number } | null>(null);

  // Signalement
  const [showSigModal, setShowSigModal] = useState(false);
  const [sigRaison, setSigRaison] = useState('contenu_inapproprie');
  const [sigDesc, setSigDesc] = useState('');

  // Le boost se gère uniquement depuis le menu « … » de « Mes annonces »
  // (components/annonces/BoostAnnonceModal.tsx) : rien ici.
  const isOwner = !!user && !!annonce && user.uid === annonce.uid_eleveur
    && (!annonce.profile_id || !activeProfileId || annonce.profile_id === activeProfileId);

  // Fiches publiques des parents (reproducteurs rendus publics par l'élevage,
  // mêmes règles que /elevages/[id]/reproducteurs/[animalId]).
  const [fichesParents, setFichesParents] = useState<{ pere?: string; mere?: string }>({});
  const [copie, setCopie] = useState(false);
  useEffect(() => {
    const uid = annonce?.uid_eleveur;
    const ids = [annonce?.pere_animal_id, annonce?.mere_animal_id].filter((x): x is string => !!x);
    if (!uid || ids.length === 0 || annonce?.profil_source === 'association') { setFichesParents({}); return; }
    (async () => {
      const { data: prof } = await supabase.from('user_profiles_complet')
        .select('id, montre_reproducteurs, statut_pro')
        .eq('uid', uid).eq('profile_type', 'eleveur').maybeSingle();
      if (!prof?.id || prof.montre_reproducteurs !== true) return;
      if (!['actif', 'validated'].includes(prof.statut_pro ?? '') && user?.uid !== uid) return;
      const { data: rows } = await supabase.from('animaux').select('id')
        .in('id', ids).eq('profile_id', prof.id).eq('uid_eleveur', uid).eq('reproducteur_public', true);
      const visibles = new Set((rows ?? []).map(r => String(r.id)));
      const href = (aid?: string) => aid && visibles.has(aid) ? `/elevages/${uid}/reproducteurs/${aid}` : undefined;
      setFichesParents({ pere: href(annonce?.pere_animal_id), mere: href(annonce?.mere_animal_id) });
    })();
  }, [annonce?.uid_eleveur, annonce?.pere_animal_id, annonce?.mere_animal_id, annonce?.profil_source, user?.uid]);

  async function partager() {
    const url = window.location.href;
    const titreP = annonce?.titre || annonce?.race || 'Annonce PetsMatch';
    try {
      if (navigator.share) { await navigator.share({ title: titreP, url }); return; }
      await navigator.clipboard.writeText(url);
      setCopie(true); setTimeout(() => setCopie(false), 2000);
    } catch { /* partage annulé */ }
  }
  const [sigLoading, setSigLoading] = useState(false);
  const [sigSent, setSigSent] = useState(false);

  // Tracking vue (fire-and-forget, une seule fois par session)
  useEffect(() => {
    if (!id) return;
    const key = `vue_tracked_${id}`;
    const isUnique = !sessionStorage.getItem(key);
    if (isUnique) sessionStorage.setItem(key, '1');

    const doTrack = (extra: Record<string, unknown> = {}) => {
      fetch('/api/annonces/stats', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ annonceId: id, unique: isUnique, ...extra }),
      }).catch(() => {});
    };

    if (activeProfileId) {
      // Utilisateur connecté — l'API résoudra le département depuis son profil
      doTrack({ profileId: activeProfileId });
    } else if (typeof navigator !== 'undefined' && 'geolocation' in navigator) {
      // Anonyme — géolocalisation navigateur → département
      navigator.geolocation.getCurrentPosition(
        async (pos) => {
          try {
            const { latitude, longitude } = pos.coords;
            const r = await fetch(
              `https://api-adresse.data.gouv.fr/reverse/?lon=${longitude}&lat=${latitude}`,
              { cache: 'no-store' }
            );
            const d = await r.json();
            // context = "75, Paris, Île-de-France" — on prend le code département
            const context: string = d.features?.[0]?.properties?.context ?? '';
            const dept = context.split(',')[0]?.trim() ?? 'inconnu';
            doTrack({ departement: dept });
          } catch {
            doTrack();
          }
        },
        () => doTrack(), // géoloc refusée ou timeout
        { timeout: 5000, maximumAge: 600000 }
      );
    } else {
      doTrack();
    }
  }, [id, activeProfileId]);

  useEffect(() => {
    if (!id) return;
    supabase.from('annonces').select('*').eq('id', id).maybeSingle()
      .then(({ data }) => {
        if (!data) { setLoading(false); return; }
        setAnnonce(data as Annonce);
        // Compteur de vues — via RPC (SECURITY DEFINER) car les annonces
        // sont publiques : un visiteur non connecté doit pouvoir incrémenter
        // le compteur sans passer les policies RLS d'écriture (réservées au
        // propriétaire/cogérant). Jamais pour le propriétaire lui-même.
        if (!user || user.uid !== data.uid_eleveur) {
          supabase.rpc('increment_annonce_vues', { p_annonce_id: id }).then(() => {});
        }
        if (data.uid_eleveur) {
          if (data.profil_source === 'association') {
            // Charge le profil association — query sans profile_type (RLS bloque) + filter client-side
            Promise.all([
              supabase.from('user_profiles_complet')
                .select('id, profile_type, nom, profile_label, avatar_url, ville')
                .eq('uid', data.uid_eleveur),
              supabase.from('user_profiles_complet')
                .select('nom, profile_picture_url_pro, ville_pro')
                .eq('uid', data.uid_eleveur).eq('is_main', true).maybeSingle(),
            ]).then(([{ data: allProfiles }, { data: u }]) => {
              type SP = { id?: string; profile_type?: string; nom?: string; profile_label?: string; avatar_url?: string; ville?: string };
              type U  = { nom?: string; profile_picture_url_pro?: string; ville_pro?: string };
              const profiles = (allProfiles ?? []) as SP[];
              const s = profiles.find(p => p.profile_type === 'association') ?? null;
              const r = u as U | null;
              if (s?.id) setAssoProfileId(s.id);
              setAssoData({
                nom:    s?.nom?.trim() || s?.profile_label?.trim() || r?.nom || data.nom_eleveur || 'Association',
                avatar: s?.avatar_url || r?.profile_picture_url_pro || '',
                ville:  s?.ville || r?.ville_pro || data.ville_eleveur || '',
              });
            });
          } else {
            Promise.all([
              supabase.from('user_profiles_complet')
                .select('profile_picture_url_pro, nom, ville_pro, pays_pro, statut_pro, siret')
                .eq('uid', data.uid_eleveur).eq('is_main', true).maybeSingle(),
              supabase.from('users_complet').select('is_premium').eq('uid', data.uid_eleveur).maybeSingle(),
            ]).then(([{ data: cp }, { data: premiumRow }]) => {
              if (!cp) return;
              setPro({
                profile_picture_url_elevage: cp.profile_picture_url_pro,
                name_elevage: cp.nom,
                ville_elevage: cp.ville_pro,
                pays_elevage: cp.pays_pro,
                statut_pro: cp.statut_pro,
                siret: cp.siret,
                is_premium: premiumRow?.is_premium ?? false,
              } as ProData);
            });
          }
        }
        setLoading(false);
      }, () => setLoading(false));

    // Charge les likes (dédupliquer par user_uid pour éviter les doublons multi-profil)
    supabase.from('likes').select('user_uid').eq('annonce_id', id).is('bebe_index', null)
      .then(({ data: rows }: { data: { user_uid: string }[] | null }) => {
        if (!rows) return;
        const uniqueUids = [...new Set(rows.map(r => r.user_uid))];
        setLikeCount(uniqueUids.length);
        if (!user) return;
        setIsLiked(uniqueUids.includes(user.uid));
      });
  }, [id, user]);

  // Étalon lié : tests génétiques + fertilité (saillie)
  useEffect(() => {
    const etalonId = annonce?.etalon_animal_id ?? annonce?.pere_animal_id;
    if (!annonce || annonce.type_vente !== 'saillie' || !etalonId) return;
    (async () => {
      const [{ data: a }, { data: tg }] = await Promise.all([
        supabase.from('animaux')
          .select('nb_petits_produits, historique_fertilite, profil_adn_etabli')
          .eq('id', etalonId).maybeSingle(),
        supabase.from('tests_genetiques')
          .select('categorie, code, nom, resultat, genotype, lien_resultat').eq('animal_id', etalonId),
      ]);
      setEtalonInfo(a ?? null);
      setEtalonTests((tg ?? []) as TestGenetique[]);
    })();
  }, [annonce]);

  // Scroll vers le bébé ciblé (navigation depuis une notification like)
  useEffect(() => {
    if (!annonce || !selectedBebe) return;
    const idx = parseInt(selectedBebe, 10);
    if (isNaN(idx)) return;
    const timer = setTimeout(() => {
      bebeRefs.current[idx]?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }, 600);
    return () => clearTimeout(timer);
  }, [annonce, selectedBebe]);

  const handleContact = async () => {
    if (!user || !annonce?.uid_eleveur) { router.push('/connexion'); return; }
    setSending(true);
    try {
      // Récupère le profil Supabase de l'éleveur pour taguer la conversation
      const { data: proProfile } = await supabase
        .from('user_profiles_complet').select('id').eq('uid', annonce.uid_eleveur)
        .order('is_main', { ascending: false }).limit(1).maybeSingle();

      const participants = [user.uid, annonce.uid_eleveur].sort();
      const convId = participants.join('_') + '_annonce_' + id;
      const titre = annonce.titre || annonce.race || annonce.espece || 'Annonce';
      await addDoc(collection(db, 'conversations'), {
        id: convId, participants,
        lastMessage: `Bonjour, je suis intéressé(e) par votre annonce : ${titre}`,
        timestamp: serverTimestamp(),
        unreadCount: { [annonce.uid_eleveur]: 1 },
        categorie: 'annonces',
        ...(proProfile?.id ? { pro_profile_id: proProfile.id } : {}),
        ...(activeProfileId ? { consumer_profile_id: activeProfileId } : {}),
      });
      await addDoc(collection(db, 'conversations', convId, 'messages'), {
        text: `Bonjour, je suis intéressé(e) par votre annonce : ${titre}`,
        senderId: user.uid,
        timestamp: serverTimestamp(),
        isRead: false,
      });
      setSent(true);
      router.push('/messages');
    } catch { setSending(false); }
  };

  const SIG_RAISONS = [
    { key: 'contenu_inapproprie', label: 'Contenu inapproprié' },
    { key: 'spam',               label: 'Spam ou arnaque' },
    { key: 'faux_profil',        label: 'Faux profil' },
    { key: 'maltraitance',       label: 'Maltraitance animale' },
    { key: 'autre',              label: 'Autre' },
  ];

  const handleSignalement = async () => {
    if (!user || !annonce) return;
    setSigLoading(true);
    try {
      const { error } = await supabase.from('signalements').insert({
        reporter_uid: user.uid,
        target_type: 'annonce',
        target_id: annonce.id,
        raison: sigRaison,
        description: sigDesc.trim() || null,
      });
      if (error?.code === '23505') {
        alert('Vous avez déjà signalé cette annonce.');
      } else {
        setSigSent(true);
        // ANTI03 : suspension automatique à 3 signalements
        const { count: nbSig } = await supabase
          .from('signalements')
          .select('id', { count: 'exact', head: true })
          .eq('target_type', 'annonce')
          .eq('target_id', annonce.id);
        if ((nbSig ?? 0) >= 3) {
          await supabase.from('annonces').update({ statut: 'suspendu' }).eq('id', annonce.id);
        }
        setTimeout(() => { setShowSigModal(false); setSigSent(false); setSigDesc(''); }, 1500);
      }
    } finally {
      setSigLoading(false);
    }
  };

  const toggleLike = async () => {
    if (!user) { router.push('/connexion'); return; }
    setLikeLoading(true);
    const wasLiked = isLiked;
    setIsLiked(!wasLiked);
    setLikeCount(c => c + (wasLiked ? -1 : 1));
    try {
      // « J'aime » par profil : on remplace seulement celui du profil actif.
      const base = supabase.from('likes').delete().eq('user_uid', user.uid).eq('annonce_id', id!);
      await (activeProfileId ? base.or(`profile_id.eq.${activeProfileId},profile_id.is.null`) : base.is('profile_id', null)).is('bebe_index', null);
      if (!wasLiked) {
        await supabase.from('likes').insert({
          user_uid: user.uid, annonce_id: id!, bebe_index: null,
          profile_type: activeProfileId ? 'eleveur' : 'particulier',
          ...(activeProfileId ? { profile_id: activeProfileId } : {}),
        });
      }
      const { data: rows } = await supabase.from('likes').select('user_uid').eq('annonce_id', id!).is('bebe_index', null);
      if (rows) {
        setLikeCount(rows.length);
        setIsLiked(rows.some((r: { user_uid: string }) => r.user_uid === user.uid));
      }
    } catch {
      setIsLiked(wasLiked);
      setLikeCount(c => c + (wasLiked ? 1 : -1));
    } finally {
      setLikeLoading(false);
    }
  };

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center bg-[#F8F8F6]">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (!annonce) return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4 bg-[#F8F8F6]">
      <p className="text-gray-500 font-['Galey']">Annonce introuvable.</p>
      <Link href="/annonces" className="text-[#0C5C6C] underline text-sm">Retour aux annonces</Link>
    </div>
  );

  // Vendeur (non association) pas encore validé → invisible aux autres, sauf
  // au propriétaire qui peut prévisualiser son annonce.
  if (annonce.profil_source !== 'association' && pro
      && !['actif', 'validated'].includes(pro.statut_pro || '') && !isOwner) {
    return (
      <div className="min-h-screen bg-[#F8F8F6] flex flex-col items-center justify-center gap-3 px-4 text-center">
        <span className="text-[#0C5C6C]"><Icone nom="horloge" taille={44} /></span>
        <p className="text-gray-700 font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
          Cette annonce est en cours de validation
        </p>
        <p className="text-gray-500 text-sm max-w-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
          Elle sera visible dès que notre équipe aura approuvé le vendeur.
        </p>
        <Link href="/annonces" className="text-[#0C5C6C] text-sm underline">Retour aux annonces</Link>
      </div>
    );
  }

  // Annonce bloquée (abonnement éleveur expiré, hors quota gratuit) — sauf
  // au propriétaire, qui garde accès pour republier après paiement.
  if (annonce.statut === 'quota_depasse' && !isOwner) {
    return (
      <div className="min-h-screen bg-[#F8F8F6] flex flex-col items-center justify-center gap-3 px-4 text-center">
        <span className="text-[#0C5C6C]"><Icone nom="cle" taille={44} /></span>
        <p className="text-gray-700 font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
          Cette annonce n&apos;est plus disponible
        </p>
        <p className="text-gray-500 text-sm max-w-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
          Elle sera de nouveau visible dès que le vendeur aura repris un abonnement payant.
        </p>
        <Link href="/annonces" className="text-[#0C5C6C] text-sm underline">Retour aux annonces</Link>
      </div>
    );
  }

  const photos = (annonce.photos ?? []) as string[];
  const bebes = (annonce.animaux_portee ?? []) as Bebe[];
  const isPortee = annonce.type === 'portee';
  const isSaillie = annonce.type_vente === 'saillie';
  const isAsso = annonce.profil_source === 'association';
  const EQUIDE_FORMULES: Record<string, string> = {
    location: 'Location', demi_pension: 'Demi-pension',
    pension_complete: 'Pension complète', valorisation: 'Valorisation',
  };
  const equideFormule = EQUIDE_FORMULES[annonce.type_vente ?? ''];
  const prixCadence = annonce.prix_unite === 'mois' ? ' / mois'
    : annonce.prix_unite === 'semaine' ? ' / semaine' : '';
  const hasEquideSport = !!(annonce.niveau_recommande || annonce.palmares
    || annonce.indice_iso || annonce.indice_idr || annonce.indice_icc
    || annonce.video_monte_url || annonce.video_libre_url);
  const titre = annonce.titre || annonce.race || especeLabel(annonce.espece, annonce.espece_autre) || 'Annonce';
  const dateNaissStr = isPortee ? annonce.date_naissance : annonce.date_naissance_animal;
  const statutInfo = STATUT_ANNONCE[annonce.statut ?? 'disponible'];
  const teinteStatut = TEINTES_STATUT[statutInfo?.teinte ?? 'gris'];

  // Prix principal (mêmes règles qu'auparavant, selon le type d'annonce).
  const prixPrincipal: { libelle?: string; valeur: string } | null = equideFormule
    ? { libelle: equideFormule, valeur: annonce.type_vente === 'valorisation'
        ? (annonce.prix != null && annonce.prix > 0 ? `${annonce.prix} €${prixCadence}` : 'Rémunération à convenir')
        : (annonce.prix != null && annonce.prix > 0 ? `${annonce.prix} €${prixCadence}` : 'Prix à convenir') }
    : annonce.type_vente === 'don' ? { valeur: 'Don' }
    : isSaillie ? (annonce.saillie_prix != null ? { libelle: 'Saillie', valeur: `${Number(annonce.saillie_prix)} €` } : null)
    : isPortee ? ((annonce.prix_min_portee != null || annonce.prix_max_portee != null) ? { valeur:
        annonce.prix_min_portee != null && annonce.prix_max_portee != null
          ? `${annonce.prix_min_portee} – ${annonce.prix_max_portee} €`
          : annonce.prix_min_portee != null ? `À partir de ${annonce.prix_min_portee} €`
          : `Jusqu'à ${annonce.prix_max_portee} €` } : null)
    : annonce.prix != null ? { libelle: annonce.type_vente === 'adoption' ? 'Frais d’adoption' : undefined, valeur: `${annonce.prix} €` }
    : null;

  const destination = isSaillie ? 'Saillie' : equideFormule ? equideFormule
    : isPortee ? 'Portée' : annonce.type_vente === 'adoption' ? 'Adoption'
    : annonce.type_vente === 'don' ? 'Don' : 'Compagnie';

  // Annonceur : association ou éleveur (même carte, mêmes actions qu'avant).
  const vendeur = isAsso
    ? (assoData ? {
        libelle: 'Association', nom: assoData.nom, avatar: assoData.avatar, ville: assoData.ville,
        href: annonce.uid_eleveur ? `/associations/${assoProfileId ?? annonce.uid_eleveur}` : null, badge: null as React.ReactNode,
      } : null)
    : (pro || annonce.nom_eleveur) ? {
        libelle: annonce.profil_source === 'particulier' ? 'Annonceur' : 'Éleveur',
        nom: pro?.name_elevage || annonce.nom_eleveur || 'Éleveur',
        avatar: pro?.profile_picture_url_elevage ?? '',
        ville: [pro?.ville_elevage || annonce.ville_eleveur, pro?.pays_elevage && pro.pays_elevage !== 'France' ? pro.pays_elevage : null].filter(Boolean).join(', '),
        href: annonce.uid_eleveur ? `/elevages/${annonce.uid_eleveur}` : null,
        badge: pro ? <VerificationBadge level={getBadgeLevel({ statutPro: pro.statut_pro, siret: pro.siret, isPremium: pro.is_premium })} size="sm" /> : null,
      } : null;
  // Contact : jamais pour le propriétaire de l'annonce.
  const peutContacter = !!user && !isOwner && user.uid !== annonce.uid_eleveur
    && (isAsso || annonce.statut === 'disponible');
  const libelleContact = isAsso ? 'Contacter l’association' : annonce.profil_source === 'particulier' ? 'Contacter l’annonceur' : 'Contacter l’éleveur';

  const parents = !isSaillie ? ([
    { cle: 'pere' as const, libelle: 'Père', nom: annonce.pere_nom, race: annonce.pere_race, photo: annonce.pere_photo_url,
      couleur: annonce.pere_couleur, yeux: annonce.pere_couleur_yeux, puce: annonce.pere_puce, registre: annonce.pere_registre,
      description: annonce.pere_description, href: fichesParents.pere },
    { cle: 'mere' as const, libelle: 'Mère', nom: annonce.mere_nom, race: annonce.mere_race, photo: annonce.mere_photo_url,
      couleur: annonce.mere_couleur, yeux: annonce.mere_couleur_yeux, puce: annonce.mere_puce, registre: annonce.mere_registre,
      description: annonce.mere_description, href: fichesParents.mere },
  ].filter(p => p.nom || p.race || p.photo)) : [];

  const bouton = 'inline-flex items-center justify-center gap-2 rounded-xl text-sm font-semibold transition-colors min-h-11 px-4';

  return (
    <>
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 sm:px-6 py-5 sm:py-8">
        <button onClick={() => router.back()} className="inline-flex items-center gap-1.5 text-sm font-semibold text-[#0C5C6C] hover:underline mb-4">
          <Chevron gauche /> Retour
        </button>

        <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)] gap-5 lg:gap-8 items-start">
          {/* ── Galerie ─────────────────────────────────────────────────── */}
          <div className="min-w-0">
            {photos.length > 0 ? (
              <>
                <div className="rounded-2xl overflow-hidden bg-[#EEF1EF] relative aspect-[4/3] group cursor-zoom-in"
                  onClick={() => setLightbox({ photos, idx: imgIdx })}>
                  <Image src={photos[imgIdx]} alt={titre} fill className="object-contain" sizes="(max-width: 1024px) 100vw, 600px" priority />
                  {photos.length > 1 && (
                    <>
                      <button aria-label="Photo précédente" onClick={e => { e.stopPropagation(); setImgIdx(i => (i - 1 + photos.length) % photos.length); }}
                        className="absolute left-3 top-1/2 -translate-y-1/2 bg-white/90 text-[#1E2025] rounded-full w-10 h-10 flex items-center justify-center shadow"><Chevron gauche /></button>
                      <button aria-label="Photo suivante" onClick={e => { e.stopPropagation(); setImgIdx(i => (i + 1) % photos.length); }}
                        className="absolute right-3 top-1/2 -translate-y-1/2 bg-white/90 text-[#1E2025] rounded-full w-10 h-10 flex items-center justify-center shadow"><Chevron /></button>
                      <span className="absolute bottom-3 right-3 text-xs font-semibold bg-black/50 text-white px-2 py-0.5 rounded-full tabular-nums">{imgIdx + 1} / {photos.length}</span>
                    </>
                  )}
                </div>
                {photos.length > 1 && (
                  <div className="grid grid-cols-4 sm:grid-cols-5 gap-2 mt-3">
                    {photos.map((p, i) => (
                      <button key={i} onClick={() => setImgIdx(i)} aria-label={`Photo ${i + 1}`}
                        className={`relative aspect-[4/3] rounded-xl overflow-hidden bg-[#EEF1EF] ${i === imgIdx ? 'ring-2 ring-[#0C5C6C] ring-offset-2' : 'opacity-80 hover:opacity-100'}`}>
                        <Image src={p} alt="" fill className="object-cover" sizes="120px" />
                      </button>
                    ))}
                  </div>
                )}
              </>
            ) : (
              <div className="rounded-2xl aspect-[4/3] bg-[#EEF1EF] flex items-center justify-center text-[#0C5C6C]"><Icone nom="patte" taille={56} /></div>
            )}
          </div>

          {/* ── Résumé, annonceur, informations ─────────────────────────── */}
          <div className="min-w-0 space-y-4">
            <div>
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <h1 className="text-[28px] sm:text-4xl font-bold text-[#1E2025] leading-tight break-words">{titre}</h1>
                  <p className="text-base text-gray-600 mt-1 capitalize">
                    {[annonce.race && annonce.race !== titre ? annonce.race : especeLabel(annonce.espece, annonce.espece_autre), annonce.ville_eleveur].filter(Boolean).join(' · ')}
                  </p>
                </div>
                {prixPrincipal && (
                  <div className="text-right flex-shrink-0">
                    {prixPrincipal.libelle && <p className="text-xs font-semibold text-gray-500">{prixPrincipal.libelle}</p>}
                    <p className="text-2xl sm:text-3xl font-bold text-[#0C5C6C] tabular-nums whitespace-nowrap">{prixPrincipal.valeur}</p>
                    {annonce.prix_negociable && <p className="text-xs font-semibold text-[#2F7D3A]">Négociable</p>}
                  </div>
                )}
              </div>
              <div className="flex flex-wrap items-center gap-2 mt-3">
                {statutInfo && <Puce texte={statutInfo.label} fg={teinteStatut.fg} bg={teinteStatut.bg} point />}
                <Puce texte={destination} fg="#41525A" bg="#FFFFFF" />
              </div>
              {/* Actions publiques de consultation */}
              <div className="flex flex-wrap items-center gap-2 mt-4">
                <button onClick={toggleLike} disabled={likeLoading} aria-pressed={isLiked}
                  className={`${bouton} bg-white disabled:opacity-60 ${isLiked ? 'text-[#E0457B]' : 'text-[#1E2025] hover:border-[#0C5C6C]/50'}`}
                  style={{ border: `1px solid ${isLiked ? '#F4B5C9' : BORDURE}` }}>
                  <svg width="18" height="18" viewBox="0 0 24 24" fill={isLiked ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2" strokeLinejoin="round"><path d="M12 20s-7-4.4-9-9a5 5 0 019-3 5 5 0 019 3c-2 4.6-9 9-9 9z" /></svg>
                  J&apos;aime{likeCount > 0 && <span className="tabular-nums text-gray-500">· {likeCount}</span>}
                </button>
                <button onClick={partager} className={`${bouton} bg-white text-[#1E2025] hover:border-[#0C5C6C]/50`} style={{ border: `1px solid ${BORDURE}` }}>
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="18" cy="5" r="3" /><circle cx="6" cy="12" r="3" /><circle cx="18" cy="19" r="3" /><path d="M8.6 13.5l6.8 4M15.4 6.5l-6.8 4" /></svg>
                  {copie ? 'Lien copié' : 'Partager'}
                </button>
                {user && likeCount > 0 && (
                  <button onClick={() => setActiveModal({ mode: 'likes' })} className="text-sm text-gray-500 hover:text-[#0C5C6C] underline-offset-2 hover:underline">
                    Voir les j&apos;aime
                  </button>
                )}
              </div>
            </div>

            {/* Annonceur */}
            {vendeur && (
              <section className="bg-white rounded-2xl p-5" style={{ border: `1px solid ${BORDURE}` }}>
                <p className="text-sm font-semibold text-gray-500 mb-3">{vendeur.libelle}</p>
                <div className="flex items-center gap-3">
                  {vendeur.href ? (
                    <Link href={vendeur.href} className="w-14 h-14 rounded-full bg-[#E8F4F6] overflow-hidden flex-shrink-0 relative block text-[#0C5C6C]">
                      {vendeur.avatar
                        ? <Image src={vendeur.avatar} alt={vendeur.nom} fill className="object-cover" sizes="56px" unoptimized />
                        : <span className="w-full h-full flex items-center justify-center"><Icone nom="maison" taille={24} /></span>}
                    </Link>
                  ) : (
                    <span className="w-14 h-14 rounded-full bg-[#E8F4F6] flex-shrink-0 flex items-center justify-center text-[#0C5C6C]"><Icone nom="maison" taille={24} /></span>
                  )}
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      {vendeur.href
                        ? <Link href={vendeur.href} className="font-bold text-lg text-[#1E2025] hover:text-[#0C5C6C] truncate">{vendeur.nom}</Link>
                        : <p className="font-bold text-lg text-[#1E2025] truncate">{vendeur.nom}</p>}
                      {vendeur.badge}
                    </div>
                    {vendeur.ville && <p className="text-sm text-gray-500 inline-flex items-center gap-1"><Icone nom="pin" taille={14} />{vendeur.ville}</p>}
                  </div>
                </div>
                {(peutContacter || vendeur.href || !user) && (
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-4">
                    {peutContacter && (
                      <button onClick={handleContact} disabled={sending || sent}
                        className={`${bouton} bg-[#0C5C6C] hover:bg-[#094F5D] text-white disabled:opacity-60`}>
                        <Icone nom="enveloppe" taille={17} />
                        {sent ? 'Message envoyé' : sending ? 'Envoi…' : libelleContact}
                      </button>
                    )}
                    {!user && (
                      <Link href="/connexion" className={`${bouton} bg-[#0C5C6C] hover:bg-[#094F5D] text-white`}>
                        <Icone nom="enveloppe" taille={17} /> Se connecter pour contacter
                      </Link>
                    )}
                    {vendeur.href && (
                      <Link href={vendeur.href} className={`${bouton} bg-white text-[#0C5C6C] hover:bg-[#E8F4F6]`} style={{ border: '1px solid rgba(12,92,108,0.45)' }}>
                        Voir le profil
                      </Link>
                    )}
                  </div>
                )}
              </section>
            )}

            {/* Annonceur introuvable : le contact reste possible. */}
            {!vendeur && (peutContacter || !user) && (
              peutContacter ? (
                <button onClick={handleContact} disabled={sending || sent} className={`${bouton} w-full bg-[#0C5C6C] hover:bg-[#094F5D] text-white disabled:opacity-60`}>
                  <Icone nom="enveloppe" taille={17} />{sent ? 'Message envoyé' : sending ? 'Envoi…' : libelleContact}
                </button>
              ) : (
                <Link href="/connexion" className={`${bouton} w-full bg-[#0C5C6C] hover:bg-[#094F5D] text-white`}>
                  <Icone nom="enveloppe" taille={17} /> Se connecter pour contacter
                </Link>
              )
            )}

            {/* Informations */}
            <section className="bg-white rounded-2xl p-5" style={{ border: `1px solid ${BORDURE}` }}>
              <h2 className="font-bold text-lg text-[#1E2025] mb-1">{isPortee ? 'La portée' : 'Informations'}</h2>
              <dl>
                {annonce.espece && <Ligne label="Espèce">{especeLabel(annonce.espece, annonce.espece_autre)}</Ligne>}
                {annonce.race && annonce.race !== annonce.espece && <Ligne label="Race">{annonce.race}</Ligne>}
                <Ligne label="Destination">{destination}</Ligne>
                {annonce.sexe && <Ligne label="Sexe">{annonce.sexe === 'male' ? 'Mâle' : 'Femelle'}</Ligne>}
                {ageLabel(dateNaissStr) && <Ligne label="Âge">{annonce.age_estime ? `Environ ${ageLabel(dateNaissStr)!}` : ageLabel(dateNaissStr)!}</Ligne>}
                {fmtDate(dateNaissStr) && (
                  <Ligne label="Naissance">{annonce.age_estime ? `Vers ${new Date(dateNaissStr!).getFullYear()}` : fmtDate(dateNaissStr)}</Ligne>
                )}
                {annonce.couleur && <Ligne label="Couleur / robe">{annonce.couleur}</Ligne>}
                {annonce.couleur_yeux && <Ligne label="Couleur des yeux">{annonce.couleur_yeux}</Ligne>}
                {annonce.sterilise && <Ligne label="Stérilisation">Stérilisé(e)</Ligne>}
                {isPortee && annonce.nb_nes != null && <Ligne label="Nés">{annonce.nb_nes} bébé{annonce.nb_nes > 1 ? 's' : ''}</Ligne>}
                {isPortee && annonce.nb_attendu != null && <Ligne label="Attendus">{annonce.nb_attendu}</Ligne>}
                {annonce.ville_eleveur && <Ligne label="Lieu">{annonce.ville_eleveur}</Ligne>}
                {fmtDate(annonce.created_at) && <Ligne label="Publiée le">{fmtDate(annonce.created_at)}</Ligne>}
              </dl>
              {annonce.age_estime && (
                <p className="text-sm text-[#92400E] bg-[#FFFBEB] rounded-xl px-3 py-2 mt-3">
                  Âge estimé par l&apos;association : la date de naissance exacte de cet animal n&apos;est pas connue.
                </p>
              )}
            </section>
          </div>
        </div>

        {/* ── Sections de lecture ───────────────────────────────────────── */}
        <div className="space-y-5 mt-6 sm:mt-8">
          {annonce.description && (
            <Bloc titre="Description">
              <p className="text-[15px] text-[#41525A] leading-relaxed whitespace-pre-wrap">{annonce.description}</p>
            </Bloc>
          )}

          {/* Santé et conformité (mêmes rubriques que l'appli) */}
          <Bloc titre="Santé et conformité">
            <ul className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2">
              {([
                ['Vacciné(e)', annonce.vaccines],
                ['Vermifugé(e)', annonce.vermifuge],
                ['Pucé(e) / tatoué(e)', annonce.identification],
                ['Bilan de santé vétérinaire', annonce.bilan_sante],
              ] as [string, boolean | undefined][]).map(([l, ok]) => (
                <li key={l} className={`flex items-center gap-2.5 text-[15px] ${ok ? 'text-[#1E2025]' : 'text-gray-400'}`}>
                  <span className={`w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0 ${ok ? 'bg-[#EAF5EC] text-[#2F7D3A]' : 'bg-gray-100 text-gray-400'}`}>
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">{ok ? <path d="M5 12l5 5L20 7" /> : <path d="M6 6l12 12M18 6L6 18" />}</svg>
                  </span>
                  {l}
                </li>
              ))}
            </ul>
            {annonce.semaines != null && !isSaillie && (
              <p className="text-[15px] text-[#1E2025] mt-3">
                Cession à partir de {annonce.semaines} semaines
                {annonce.semaines < 8 && <span className="ml-2 text-sm font-semibold text-[#B45309]">minimum légal : 8 semaines</span>}
              </p>
            )}
          </Bloc>

          {/* Pedigree */}
          {annonce.registre_type && (
            <Bloc titre={`Pedigree et ${annonce.espece === 'chien' ? 'LOF' : annonce.espece === 'chat' ? 'LOOF' : annonce.espece === 'cheval' ? 'SIRE' : 'registre'}`}>
              <dl>
                <Ligne label="Registre">{annonce.registre_type}</Ligne>
                {annonce.numero_registre && <Ligne label="N° d’inscription">{annonce.numero_registre}</Ligne>}
                {annonce.studbook && <Ligne label="Studbook">{annonce.studbook}</Ligne>}
                {annonce.club_pedigree && <Ligne label="Club de race">{annonce.club_pedigree}</Ligne>}
              </dl>
            </Bloc>
          )}

          {/* Cheval — sport & vidéos */}
          {annonce.espece === 'cheval' && hasEquideSport && (
            <Bloc titre="Sport et vidéos">
              <dl>
                {annonce.niveau_recommande && <Ligne label="Niveau">{annonce.niveau_recommande}</Ligne>}
                {(annonce.indice_iso || annonce.indice_idr || annonce.indice_icc) && (
                  <Ligne label="Indices">{[
                    annonce.indice_iso ? `ISO ${annonce.indice_iso}` : null,
                    annonce.indice_idr ? `IDR ${annonce.indice_idr}` : null,
                    annonce.indice_icc ? `ICC ${annonce.indice_icc}` : null,
                  ].filter(Boolean).join(' · ')}</Ligne>
                )}
              </dl>
              {annonce.palmares && <p className="text-[15px] text-[#41525A] leading-relaxed whitespace-pre-wrap mt-2">{annonce.palmares}</p>}
              {(annonce.video_monte_url || annonce.video_libre_url) && (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
                  {annonce.video_monte_url && (
                    <div>
                      <p className="text-sm font-semibold text-gray-500 mb-1">Sous selle</p>
                      <video src={annonce.video_monte_url} controls className="w-full rounded-xl" style={{ border: `1px solid ${BORDURE}` }} />
                    </div>
                  )}
                  {annonce.video_libre_url && (
                    <div>
                      <p className="text-sm font-semibold text-gray-500 mb-1">En liberté</p>
                      <video src={annonce.video_libre_url} controls className="w-full rounded-xl" style={{ border: `1px solid ${BORDURE}` }} />
                    </div>
                  )}
                </div>
              )}
            </Bloc>
          )}

          {/* Conditions saillie */}
          {isSaillie && annonce.saillie_conditions && (
            <Bloc titre="Conditions de saillie">
              <p className="text-[15px] text-[#41525A] leading-relaxed whitespace-pre-wrap">{annonce.saillie_conditions}</p>
            </Bloc>
          )}

          {/* Saillie — statut génétique de l'étalon + fertilité */}
          {isSaillie && (() => {
            const maladies = etalonTests.filter(t => t.categorie === 'maladie');
            const adnEtabli = etalonInfo?.profil_adn_etabli === true
              || etalonTests.some(t => t.categorie === 'adn' && t.resultat === 'etabli');
            const genLibre = (annonce.saillie_genetique ?? '').trim();
            const hasGen = maladies.length > 0 || adnEtabli || genLibre.length > 0;
            const nb = etalonInfo?.nb_petits_produits;
            const hist = (etalonInfo?.historique_fertilite ?? '').trim();
            const hasFert = nb != null || hist.length > 0;
            if (!hasGen && !hasFert) return null;
            return (
              <Bloc titre="Génétique et fertilité de l’étalon">
                {hasGen && (
                  (maladies.length > 0 || adnEtabli) ? (
                    <div className="flex flex-wrap gap-2">
                      {adnEtabli && <span className="inline-flex items-center gap-1 bg-[#EAF5EC] text-[#2F7D3A] text-xs font-semibold px-2.5 py-1 rounded-full">Profil ADN établi</span>}
                      {maladies.map((t, i) => (
                        <span key={i} className={`inline-flex items-center text-xs font-semibold px-2.5 py-1 rounded-full ${resultatChipClass(t.resultat)}`}>
                          {testChipLabel(t)}
                          {t.lien_resultat && (
                            <a href={t.lien_resultat} target="_blank" rel="noopener noreferrer" className="ml-1.5 underline">résultat</a>
                          )}
                        </span>
                      ))}
                    </div>
                  ) : (
                    <p className="text-[15px] text-[#41525A] leading-relaxed whitespace-pre-line">{genLibre}</p>
                  )
                )}
                {hasFert && (
                  <div className={hasGen ? 'mt-4' : ''}>
                    <p className="text-sm font-semibold text-gray-500 mb-1">Fertilité</p>
                    {nb != null && <p className="text-[15px] font-semibold text-[#1E2025]">{nb} poulains produits</p>}
                    {hist && <p className="text-[15px] text-[#41525A] leading-relaxed whitespace-pre-line mt-1">{hist}</p>}
                  </div>
                )}
              </Bloc>
            );
          })()}

          {/* Bébés portée */}
          {isPortee && bebes.length > 0 && (
            <Bloc titre={`Bébés · ${bebes.filter(b => b.statut === 'disponible').length} disponible${bebes.filter(b => b.statut === 'disponible').length > 1 ? 's' : ''}`}>
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
                {bebes.map((b, i) => (
                  <div key={i} ref={el => { bebeRefs.current[i] = el; }}
                    className={selectedBebe != null && parseInt(selectedBebe, 10) === i
                      ? 'ring-2 ring-[#0C5C6C] rounded-xl' : ''}>
                    <BebeCard bebe={b} index={i}
                      annonceId={annonce.id}
                      uidEleveur={annonce.uid_eleveur}
                      currentUser={user}
                      onOpenLightbox={(p, pi) => setLightbox({ photos: p, idx: pi })}
                      onShowLikers={() => setActiveModal({ mode: 'likes', bebeIndex: i })} />
                  </div>
                ))}
              </div>
            </Bloc>
          )}

          {/* Parents : deux cartes de même structure */}
          {parents.length > 0 && (
            <Bloc titre={isPortee ? 'Les parents' : 'Ses parents'}>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {parents.map(p => {
                  const photo = p.photo ? (
                    <span className="relative block w-full sm:w-40 aspect-[4/3] sm:aspect-square rounded-xl overflow-hidden bg-[#EEF1EF] flex-shrink-0">
                      <Image src={p.photo} alt={`${p.libelle}${p.nom ? ` ${p.nom}` : ''}`} fill className="object-cover" sizes="(max-width: 640px) 100vw, 160px" unoptimized />
                    </span>
                  ) : (
                    <span className="flex w-full sm:w-40 aspect-[4/3] sm:aspect-square rounded-xl bg-[#EEF1EF] text-[#0C5C6C] items-center justify-center flex-shrink-0"><Icone nom="patte" taille={32} /></span>
                  );
                  return (
                    <div key={p.cle} className="rounded-2xl p-3 sm:p-4 flex flex-col sm:flex-row gap-4 bg-white" style={{ border: `1px solid ${BORDURE}` }}>
                      {p.href
                        ? <Link href={p.href} aria-label={`Voir la fiche du ${p.libelle.toLowerCase()}`}>{photo}</Link>
                        : p.photo
                          ? <button type="button" className="cursor-zoom-in text-left" onClick={() => setLightbox({ photos: [p.photo!], idx: 0 })} aria-label="Agrandir la photo">{photo}</button>
                          : photo}
                      <div className="min-w-0 flex-1 flex flex-col">
                        <p className="text-sm font-bold text-[#0C5C6C]">{p.libelle}</p>
                        {p.nom && (p.href
                          ? <Link href={p.href} className="text-lg font-bold text-[#1E2025] hover:text-[#0C5C6C] break-words">{p.nom}</Link>
                          : <p className="text-lg font-bold text-[#1E2025] break-words">{p.nom}</p>)}
                        <dl className="text-sm text-gray-600 mt-1 space-y-0.5">
                          {p.race && <div>{p.race}</div>}
                          {p.couleur && <div>Robe : {p.couleur}</div>}
                          {p.yeux && <div>Yeux : {p.yeux}</div>}
                          {p.registre && <div>Registre : {p.registre}</div>}
                          {p.puce && <div className="break-all">Identification : <span className="tabular-nums">{p.puce}</span></div>}
                        </dl>
                        {p.description && <p className="text-sm text-gray-500 leading-relaxed mt-2">{p.description}</p>}
                        {p.href && (
                          <Link href={p.href}
                            className={`${bouton} mt-3 self-start bg-white text-[#0C5C6C] hover:bg-[#E8F4F6]`} style={{ border: '1px solid rgba(12,92,108,0.45)' }}>
                            Voir la fiche du parent <Icone nom="fleche" taille={16} />
                          </Link>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            </Bloc>
          )}

          {user && !isOwner && user.uid !== annonce.uid_eleveur && (
            <div className="text-center">
              <button type="button"
                onClick={() => { setShowSigModal(true); setSigDesc(''); setSigRaison('contenu_inapproprie'); }}
                className="text-sm text-gray-500 hover:text-gray-700 underline-offset-2 hover:underline py-1">
                Signaler cette annonce
              </button>
            </div>
          )}
        </div>
      </div>
    </div>

    {/* Modal likers / favoris */}
    {activeModal && (
      <LikersModal
        annonceId={annonce!.id}
        bebeIndex={activeModal.bebeIndex}
        mode={activeModal.mode}
        onClose={() => setActiveModal(null)}
      />
    )}

    {/* Modal signalement */}
    {showSigModal && (
      <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4">
        <div className="bg-white rounded-2xl w-full max-w-sm p-6 shadow-2xl">
          <h3 className="font-['Galey'] font-bold text-[#1F2A2E] mb-3">Signaler cette annonce</h3>
          <div className="space-y-2 mb-4">
            {SIG_RAISONS.map(r => (
              <label key={r.key} className="flex items-center gap-3 cursor-pointer">
                <input
                  type="radio"
                  name="sig_raison"
                  value={r.key}
                  checked={sigRaison === r.key}
                  onChange={() => setSigRaison(r.key)}
                  className="accent-[#0C5C6C]"
                />
                <span className="text-sm text-[#1F2A2E]">{r.label}</span>
              </label>
            ))}
          </div>
          <textarea
            value={sigDesc}
            onChange={e => setSigDesc(e.target.value)}
            placeholder="Détails (facultatif)"
            rows={3}
            className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm mb-4 focus:outline-none focus:border-[#6E9E57] resize-none"
          />
          {sigSent && <p className="text-[#2F7D3A] text-sm text-center mb-3">Signalement envoyé. Merci.</p>}
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setShowSigModal(false)}
              className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 transition-colors"
            >
              Annuler
            </button>
            <button
              type="button"
              onClick={handleSignalement}
              disabled={sigLoading || sigSent}
              className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white text-sm font-semibold py-2.5 rounded-xl transition-colors"
            >
              {sigLoading ? 'Envoi…' : 'Envoyer'}
            </button>
          </div>
        </div>
      </div>
    )}

    {/* Lightbox */}
    {lightbox && (
      <Lightbox photos={lightbox.photos} initialIdx={lightbox.idx}
        onClose={() => setLightbox(null)} />
    )}
    </>
  );
}

export default function AnnonceDetailPage() {
  return (
    <Suspense fallback={null}>
      <AnnonceDetailPageInner />
    </Suspense>
  );
}
