'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { collection, addDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import VerificationBadge, { getBadgeLevel } from '@/components/VerificationBadge';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Bebe {
  nom?: string; sexe?: string; couleur?: string; prix?: number;
  statut?: string; photos?: string[]; description?: string; pedigree?: boolean;
}

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  type?: string;
  type_vente?: string;
  photos?: string[];
  animaux_portee?: Bebe[];
  prix?: number;
  saillie_prix?: number;
  prix_min_portee?: number;
  prix_max_portee?: number;
  ville_eleveur?: string;
  sexe?: string;
  couleur?: string;
  nom_eleveur?: string;
  uid_eleveur?: string;
  description?: string;
  registre_type?: string;
  date_naissance?: string;
  date_naissance_animal?: string;
  saillie_conditions?: string;
  mere_nom?: string; mere_puce?: string; mere_race?: string;
  mere_photo_url?: string; mere_couleur?: string; mere_description?: string; mere_registre?: string;
  pere_nom?: string; pere_puce?: string; pere_race?: string;
  pere_photo_url?: string; pere_couleur?: string; pere_description?: string; pere_registre?: string;
  nb_attendu?: number; nb_nes?: number;
  statut?: string;
  sterilise?: boolean;
  expire_at?: string;
  created_at?: string;
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

function especeLabel(e?: string) {
  const map: Record<string, string> = {
    chien: '🐕 Chien', chat: '🐈 Chat', lapin: '🐇 Lapin',
    oiseau: '🐦 Oiseau', reptile: '🦎 Reptile', cheval: '🐴 Cheval',
    ane: '🫏 Âne', ovin: '🐑 Ovin', caprin: '🐐 Caprin',
    porcin: '🐷 Porcin', nac: '🐾 NAC', poule: '🐓 Poule',
  };
  return e ? (map[e.toLowerCase()] ?? `🐾 ${e}`) : '';
}

function Chip({ icon, label, color = '#0C5C6C' }: { icon: string; label: string; color?: string }) {
  return (
    <span className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold"
      style={{ background: `${color}18`, color }}>
      <span>{icon}</span>{label}
    </span>
  );
}

// ── Bébé card avec carousel ──────────────────────────────────────────────────

function BebeCard({ bebe: b, index }: { bebe: Bebe; index: number }) {
  const [idx, setIdx] = useState(0);
  const photos = (b.photos ?? []).filter(p => p?.startsWith('http'));
  const statut = b.statut ?? 'disponible';
  const statutColor = statut === 'disponible' ? '#6E9E57' : statut === 'reserve' ? '#F59E0B' : '#94A3B8';
  const statutLabel = statut === 'disponible' ? 'Dispo' : statut === 'reserve' ? 'Réservé' : 'Vendu';

  return (
    <div className="rounded-xl overflow-hidden border border-[#E8EDE6] bg-[#F8F8F6]">
      <div className="aspect-square relative bg-[#EEF5EA] group">
        {photos.length > 0 ? (
          <Image src={photos[idx]} alt={b.nom || `Bébé ${index + 1}`} fill className="object-cover"
            sizes="(max-width: 672px) 50vw, 336px" />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-3xl">🐾</div>
        )}
        {/* Flèches navigation */}
        {photos.length > 1 && (
          <>
            <button onClick={() => setIdx(i => (i - 1 + photos.length) % photos.length)}
              className="absolute left-1 top-1/2 -translate-y-1/2 w-6 h-6 rounded-full bg-black/40 text-white flex items-center justify-center text-sm opacity-0 group-hover:opacity-100 transition-opacity">
              ‹
            </button>
            <button onClick={() => setIdx(i => (i + 1) % photos.length)}
              className="absolute right-1 top-1/2 -translate-y-1/2 w-6 h-6 rounded-full bg-black/40 text-white flex items-center justify-center text-sm opacity-0 group-hover:opacity-100 transition-opacity">
              ›
            </button>
            <div className="absolute bottom-1.5 left-1/2 -translate-x-1/2 flex gap-1">
              {photos.map((_, j) => (
                <button key={j} onClick={() => setIdx(j)}
                  className={`rounded-full transition-all ${j === idx ? 'w-3 h-1.5 bg-white' : 'w-1.5 h-1.5 bg-white/50'}`} />
              ))}
            </div>
          </>
        )}
        <span className="absolute top-2 right-2 text-xs font-bold px-2 py-0.5 rounded-full text-white"
          style={{ background: statutColor }}>
          {statutLabel}
        </span>
      </div>
      <div className="p-2 space-y-0.5">
        <p className="font-['Galey'] font-bold text-sm text-[#1E2025] truncate">{b.nom || `Bébé ${index + 1}`}</p>
        {b.sexe && <p className="text-xs text-gray-500">{b.sexe === 'male' ? '♂ Mâle' : '♀ Femelle'}</p>}
        {b.couleur && <p className="text-xs text-gray-400 truncate">🎨 {b.couleur}</p>}
        {b.prix != null && <p className="font-['Galey'] font-bold text-sm text-[#0C5C6C]">{b.prix} €</p>}
        {b.description && <p className="text-xs text-gray-400 mt-1 leading-relaxed line-clamp-3">{b.description}</p>}
        {photos.length > 1 && (
          <p className="text-[10px] text-gray-400 mt-0.5">📷 {photos.length} photos</p>
        )}
      </div>
    </div>
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function AnnonceDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { user } = useAuth();
  const [annonce, setAnnonce] = useState<Annonce | null>(null);
  const [pro, setPro] = useState<ProData | null>(null);
  const [loading, setLoading] = useState(true);
  const [imgIdx, setImgIdx] = useState(0);
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);

  // Likes
  const [likeCount, setLikeCount] = useState(0);
  const [isLiked, setIsLiked] = useState(false);
  const [likers, setLikers] = useState<{ uid: string; firstname?: string; profile_picture_url?: string }[]>([]);
  const [likeLoading, setLikeLoading] = useState(false);
  const [showLikersModal, setShowLikersModal] = useState(false);

  // Signalement
  const [showSigModal, setShowSigModal] = useState(false);
  const [sigRaison, setSigRaison] = useState('contenu_inapproprie');
  const [sigDesc, setSigDesc] = useState('');
  const [sigLoading, setSigLoading] = useState(false);
  const [sigSent, setSigSent] = useState(false);

  useEffect(() => {
    if (!id) return;
    supabase.from('annonces').select('*').eq('id', id).maybeSingle()
      .then(({ data }) => {
        if (!data) { setLoading(false); return; }
        setAnnonce(data as Annonce);
        if (data.uid_eleveur) {
          supabase.from('users')
            .select('profile_picture_url_elevage, name_elevage, ville_elevage, pays_elevage, statut_pro, siret, is_premium')
            .eq('uid', data.uid_eleveur).maybeSingle()
            .then(({ data: u }) => { if (u) setPro(u as ProData); });
        }
        setLoading(false);
      }, () => setLoading(false));

    // Charge les likes
    supabase.from('likes').select('user_uid').eq('annonce_id', id).is('bebe_index', null)
      .then(({ data: rows }: { data: { user_uid: string }[] | null }) => {
        if (!rows) return;
        setLikeCount(rows.length);
        if (!user) return;
        setIsLiked(rows.some(r => r.user_uid === user.uid));
        if (rows.length === 0) return;
        const uids = rows.slice(0, 20).map(r => r.user_uid);
        supabase.from('users').select('uid, firstname, profile_picture_url').in('uid', uids)
          .then(({ data: u }) => { if (u) setLikers(u as typeof likers); });
      });
  }, [id, user]);

  const handleContact = async () => {
    if (!user || !annonce?.uid_eleveur) { router.push('/connexion'); return; }
    setSending(true);
    try {
      const participants = [user.uid, annonce.uid_eleveur].sort();
      const convId = participants.join('_') + '_annonce_' + id;
      const titre = annonce.titre || annonce.race || annonce.espece || 'Annonce';
      await addDoc(collection(db, 'conversations'), {
        id: convId, participants,
        lastMessage: `Bonjour, je suis intéressé(e) par votre annonce : ${titre}`,
        timestamp: serverTimestamp(),
        unreadCount: { [annonce.uid_eleveur]: 1 },
        categorie: 'annonces',
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
      if (wasLiked) {
        await supabase.from('likes').delete()
          .eq('user_uid', user.uid).eq('annonce_id', id!).is('bebe_index', null);
      } else {
        await supabase.from('likes').upsert({ user_uid: user.uid, annonce_id: id!, bebe_index: null, profile_type: 'particulier' });
      }
      const { data: rows } = await supabase.from('likes').select('user_uid').eq('annonce_id', id!).is('bebe_index', null);
      if (rows) {
        setLikeCount(rows.length);
        setIsLiked(rows.some((r: { user_uid: string }) => r.user_uid === user.uid));
        const uids = rows.slice(0, 20).map((r: { user_uid: string }) => r.user_uid);
        if (uids.length > 0) {
          const { data: u } = await supabase.from('users').select('uid, firstname, profile_picture_url').in('uid', uids);
          if (u) setLikers(u as typeof likers);
        } else {
          setLikers([]);
        }
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
      <Link href="/annonces" className="text-[#0C5C6C] underline text-sm">← Retour aux annonces</Link>
    </div>
  );

  const photos = (annonce.photos ?? []) as string[];
  const bebes = (annonce.animaux_portee ?? []) as Bebe[];
  const isPortee = annonce.type === 'portee';
  const isSaillie = annonce.type_vente === 'saillie';
  const titre = annonce.titre || annonce.race || especeLabel(annonce.espece) || 'Annonce';
  const dateNaissStr = isPortee ? annonce.date_naissance : annonce.date_naissance_animal;

  return (
    <>
    <div className="min-h-screen bg-[#F8F8F6]">
      {/* Header */}
      <div className="bg-white border-b border-[#E8EDE6] sticky top-0 z-10">
        <div className="max-w-2xl mx-auto px-4 py-3 flex items-center gap-3">
          <button onClick={() => router.back()} className="text-[#0C5C6C] hover:opacity-70 transition-opacity">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
              <path d="M19 12H5M12 5l-7 7 7 7"/>
            </svg>
          </button>
          <span className="font-['Galey'] font-bold text-[#1E2025] truncate flex-1">{titre}</span>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">

        {/* Carrousel photos */}
        {photos.length > 0 && (
          <div className="rounded-2xl overflow-hidden bg-black relative aspect-square">
            <Image src={photos[imgIdx]} alt={titre} fill className="object-contain" sizes="(max-width: 672px) 100vw, 672px" />
            {photos.length > 1 && (
              <>
                <button onClick={() => setImgIdx(i => (i - 1 + photos.length) % photos.length)}
                  className="absolute left-3 top-1/2 -translate-y-1/2 bg-black/40 text-white rounded-full w-8 h-8 flex items-center justify-center">‹</button>
                <button onClick={() => setImgIdx(i => (i + 1) % photos.length)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 bg-black/40 text-white rounded-full w-8 h-8 flex items-center justify-center">›</button>
                <div className="absolute bottom-3 left-1/2 -translate-x-1/2 flex gap-1.5">
                  {photos.map((_, i) => (
                    <button key={i} onClick={() => setImgIdx(i)}
                      className={`w-2 h-2 rounded-full transition-all ${i === imgIdx ? 'bg-white w-4' : 'bg-white/50'}`} />
                  ))}
                </div>
              </>
            )}
          </div>
        )}

        {/* Titre + chips espèce/race */}
        <div className="bg-white rounded-2xl p-5 shadow-sm">
          <h1 className="font-['Galey'] font-bold text-xl text-[#1E2025] mb-3">{titre}</h1>
          <div className="flex flex-wrap gap-2">
            {annonce.espece && <Chip icon="🐾" label={especeLabel(annonce.espece)} />}
            {annonce.race && annonce.race !== annonce.espece && <Chip icon="🏷️" label={annonce.race} />}
            {annonce.registre_type && !annonce.registre_type.startsWith('Non ') &&
              <Chip icon="📜" label={annonce.registre_type} color="#6E9E57" />}
            {isSaillie && <Chip icon="💑" label="Saillie" color="#8B5CF6" />}
            {annonce.ville_eleveur && <Chip icon="📍" label={annonce.ville_eleveur} color="#64748B" />}
          </div>
        </div>

        {/* Infos animal / portée */}
        <div className="bg-white rounded-2xl p-5 shadow-sm space-y-3">
          <h2 className="font-['Galey'] font-bold text-sm text-[#0C5C6C] uppercase tracking-wide">
            {isPortee ? 'La portée' : 'L\'animal'}
          </h2>
          <div className="flex flex-wrap gap-2">
            {annonce.sexe && (
              <Chip
                icon={annonce.sexe === 'male' ? '♂️' : '♀️'}
                label={annonce.sexe === 'male' ? 'Mâle' : 'Femelle'}
                color={annonce.sexe === 'male' ? '#0C5C6C' : '#EC4899'}
              />
            )}
            {annonce.couleur && <Chip icon="🎨" label={annonce.couleur} color="#64748B" />}
            {annonce.sterilise && <Chip icon="✂️" label="Stérilisé(e)" color="#F59E0B" />}

            {/* ── DATE DE NAISSANCE ── */}
            {ageLabel(dateNaissStr) && (
              <Chip icon="🎂" label={ageLabel(dateNaissStr)!} />
            )}
            {fmtDate(dateNaissStr) && (
              <Chip icon="📅" label={`Né(e) le ${fmtDate(dateNaissStr)}`} color="#4B5563" />
            )}

            {isPortee && annonce.nb_nes != null && (
              <Chip icon="🐾" label={`${annonce.nb_nes} bébé${annonce.nb_nes > 1 ? 's' : ''}`} />
            )}
            {isPortee && annonce.nb_attendu != null && (
              <Chip icon="⏳" label={`${annonce.nb_attendu} attendu${annonce.nb_attendu > 1 ? 's' : ''}`} color="#64748B" />
            )}
          </div>

          {/* Prix */}
          {!isPortee && !isSaillie && annonce.prix != null && (
            <p className="font-['Galey'] font-bold text-2xl text-[#0C5C6C]">{annonce.prix} €</p>
          )}
          {isSaillie && annonce.saillie_prix != null && (
            <p className="font-['Galey'] font-bold text-2xl text-[#0C5C6C]">{Number(annonce.saillie_prix)} €</p>
          )}
          {isPortee && (annonce.prix_min_portee != null || annonce.prix_max_portee != null) && (
            <p className="font-['Galey'] font-bold text-2xl text-[#0C5C6C]">
              {annonce.prix_min_portee != null && annonce.prix_max_portee != null
                ? `${annonce.prix_min_portee} – ${annonce.prix_max_portee} €`
                : annonce.prix_min_portee != null ? `À partir de ${annonce.prix_min_portee} €`
                : `Jusqu'à ${annonce.prix_max_portee} €`}
            </p>
          )}
        </div>

        {/* Description */}
        {annonce.description && (
          <div className="bg-white rounded-2xl p-5 shadow-sm">
            <h2 className="font-['Galey'] font-bold text-sm text-[#0C5C6C] uppercase tracking-wide mb-3">Description</h2>
            <p className="font-['Galey'] text-[#444] text-sm leading-relaxed whitespace-pre-wrap">{annonce.description}</p>
          </div>
        )}

        {/* Conditions saillie */}
        {isSaillie && annonce.saillie_conditions && (
          <div className="bg-white rounded-2xl p-5 shadow-sm">
            <h2 className="font-['Galey'] font-bold text-sm text-[#0C5C6C] uppercase tracking-wide mb-3">Conditions de saillie</h2>
            <p className="font-['Galey'] text-[#444] text-sm leading-relaxed">{annonce.saillie_conditions}</p>
          </div>
        )}

        {/* Bébés portée */}
        {isPortee && bebes.length > 0 && (
          <div className="bg-white rounded-2xl p-5 shadow-sm">
            <h2 className="font-['Galey'] font-bold text-sm text-[#0C5C6C] uppercase tracking-wide mb-3">
              Bébés ({bebes.filter(b => b.statut === 'disponible').length} disponible{bebes.filter(b => b.statut === 'disponible').length > 1 ? 's' : ''})
            </h2>
            <div className="grid grid-cols-2 gap-3">
              {bebes.map((b, i) => <BebeCard key={i} bebe={b} index={i} />)}
            </div>
          </div>
        )}

        {/* Parents */}
        {!isSaillie && (annonce.pere_nom || annonce.mere_nom || annonce.pere_race || annonce.mere_race ||
          annonce.pere_photo_url || annonce.mere_photo_url) && (
          <div className="bg-white rounded-2xl p-5 shadow-sm">
            <h2 className="font-['Galey'] font-bold text-sm text-[#0C5C6C] uppercase tracking-wide mb-3">Parents</h2>
            <div className="grid grid-cols-2 gap-3">
              {/* Père */}
              {(annonce.pere_nom || annonce.pere_race || annonce.pere_photo_url) && (
                <div className="bg-[#F0F7FF] rounded-xl overflow-hidden">
                  {annonce.pere_photo_url && (
                    <div className="aspect-square relative bg-[#E8F0FF]">
                      <Image src={annonce.pere_photo_url} alt="Père" fill className="object-cover"
                        sizes="(max-width: 672px) 50vw, 300px" unoptimized />
                    </div>
                  )}
                  <div className="p-3 space-y-0.5">
                    <p className="text-xs font-bold text-[#0C5C6C] uppercase mb-1">♂ Père</p>
                    {annonce.pere_nom && <p className="font-['Galey'] font-semibold text-sm text-[#1E2025]">{annonce.pere_nom}</p>}
                    {annonce.pere_race && <p className="text-xs text-gray-500">{annonce.pere_race}</p>}
                    {annonce.pere_couleur && <p className="text-xs text-gray-500">🎨 {annonce.pere_couleur}</p>}
                    {annonce.pere_puce && (
                      <p className="text-xs text-gray-400 font-mono break-all">🔖 {annonce.pere_puce}</p>
                    )}
                    {annonce.pere_registre && (
                      <p className="text-xs text-[#6E9E57] font-semibold">📜 {annonce.pere_registre}</p>
                    )}
                    {annonce.pere_description && (
                      <p className="text-xs text-gray-500 mt-1.5 leading-relaxed">{annonce.pere_description}</p>
                    )}
                  </div>
                </div>
              )}
              {/* Mère */}
              {(annonce.mere_nom || annonce.mere_race || annonce.mere_photo_url) && (
                <div className="bg-[#FFF0F6] rounded-xl overflow-hidden">
                  {annonce.mere_photo_url && (
                    <div className="aspect-square relative bg-[#FFE8F2]">
                      <Image src={annonce.mere_photo_url} alt="Mère" fill className="object-cover"
                        sizes="(max-width: 672px) 50vw, 300px" unoptimized />
                    </div>
                  )}
                  <div className="p-3 space-y-0.5">
                    <p className="text-xs font-bold text-[#EC4899] uppercase mb-1">♀ Mère</p>
                    {annonce.mere_nom && <p className="font-['Galey'] font-semibold text-sm text-[#1E2025]">{annonce.mere_nom}</p>}
                    {annonce.mere_race && <p className="text-xs text-gray-500">{annonce.mere_race}</p>}
                    {annonce.mere_couleur && <p className="text-xs text-gray-500">🎨 {annonce.mere_couleur}</p>}
                    {annonce.mere_puce && (
                      <p className="text-xs text-gray-400 font-mono break-all">🔖 {annonce.mere_puce}</p>
                    )}
                    {annonce.mere_registre && (
                      <p className="text-xs text-[#6E9E57] font-semibold">📜 {annonce.mere_registre}</p>
                    )}
                    {annonce.mere_description && (
                      <p className="text-xs text-gray-500 mt-1.5 leading-relaxed">{annonce.mere_description}</p>
                    )}
                  </div>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Likes */}
        <div className="bg-white rounded-2xl p-4 shadow-sm flex items-center gap-3 flex-wrap">
          <button
            onClick={toggleLike}
            disabled={likeLoading}
            className="flex items-center gap-2 px-4 py-2 rounded-full border transition-all disabled:opacity-50 cursor-pointer"
            style={{
              background: isLiked ? '#FDECEA' : '#F9F9F9',
              borderColor: isLiked ? '#F87171' : '#E5E7EB',
              color: isLiked ? '#EF4444' : '#6B7280',
            }}
          >
            <span className="text-base">{isLiked ? '❤️' : '🤍'}</span>
            <span className="font-['Galey'] font-semibold text-sm">
              {likeCount > 0 ? likeCount : "J’aime"}
            </span>
          </button>
          {user && likers.length > 0 && (
            <button
              onClick={() => setShowLikersModal(true)}
              className="flex items-center gap-2 hover:opacity-70 transition-opacity"
            >
              <div className="flex">
                {likers.slice(0, 3).map((l, i) => (
                  <div key={l.uid} className="w-7 h-7 rounded-full border-2 border-white overflow-hidden bg-[#0C5C6C] flex items-center justify-center flex-shrink-0"
                    style={{ marginLeft: i > 0 ? '-8px' : '0', zIndex: 3 - i }}>
                    {l.profile_picture_url ? (
                      <Image src={l.profile_picture_url} alt="" width={28} height={28} className="object-cover w-7 h-7" unoptimized />
                    ) : (
                      <span className="text-white text-xs">👤</span>
                    )}
                  </div>
                ))}
              </div>
              <span className="font-['Galey'] text-xs text-gray-500">
                {likeCount === 1
                  ? `${likers[0]?.firstname ?? ''} a aimé`
                  : likeCount <= likers.length
                    ? `${likers[0]?.firstname ?? ''} et ${likeCount - 1} autre${likeCount > 2 ? 's' : ''}`
                    : `Voir les ${likeCount} j’aimes`
                }
              </span>
            </button>
          )}
          {!user && likeCount > 0 && (
            <span className="font-['Galey'] text-xs text-gray-400">
              {likeCount} j&apos;aime{likeCount > 1 ? 's' : ''}
            </span>
          )}
        </div>

        {/* Éleveur */}
        {(pro || annonce.nom_eleveur) && (
          <div className="bg-white rounded-2xl p-5 shadow-sm">
            <h2 className="font-['Galey'] font-bold text-sm text-[#0C5C6C] uppercase tracking-wide mb-3">L'éleveur</h2>
            <div className="flex items-center gap-3">
              {annonce.uid_eleveur ? (
                <Link href={`/elevages/${annonce.uid_eleveur}`} className="w-12 h-12 rounded-full bg-[#EEF5EA] overflow-hidden flex-shrink-0 relative block hover:opacity-90 transition-opacity">
                  {pro?.profile_picture_url_elevage ? (
                    <Image src={pro.profile_picture_url_elevage} alt="éleveur" fill className="object-cover" sizes="64px" />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-xl">🏡</div>
                  )}
                </Link>
              ) : (
                <div className="w-12 h-12 rounded-full bg-[#EEF5EA] overflow-hidden flex-shrink-0 relative">
                  {pro?.profile_picture_url_elevage ? (
                    <Image src={pro.profile_picture_url_elevage} alt="éleveur" fill className="object-cover" sizes="64px" />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-xl">🏡</div>
                  )}
                </div>
              )}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  {annonce.uid_eleveur ? (
                    <Link href={`/elevages/${annonce.uid_eleveur}`} className="font-['Galey'] font-bold text-[#1E2025] hover:text-[#0C5C6C] transition-colors">
                      {pro?.name_elevage || annonce.nom_eleveur || 'Éleveur'}
                    </Link>
                  ) : (
                    <p className="font-['Galey'] font-bold text-[#1E2025]">
                      {pro?.name_elevage || annonce.nom_eleveur || 'Éleveur'}
                    </p>
                  )}
                  {pro && <VerificationBadge level={getBadgeLevel({ statutPro: pro.statut_pro, siret: pro.siret, isPremium: pro.is_premium })} size="sm" />}
                </div>
                {(pro?.ville_elevage || annonce.ville_eleveur) && (
                  <p className="text-xs text-gray-500">
                    📍 {pro?.ville_elevage || annonce.ville_eleveur}
                    {pro?.pays_elevage && pro.pays_elevage !== 'France' ? `, ${pro.pays_elevage}` : ''}
                  </p>
                )}
              </div>
              {annonce.uid_eleveur && (
                <Link href={`/elevages/${annonce.uid_eleveur}`}
                  className="flex-shrink-0 text-xs font-semibold text-[#0C5C6C] border border-[#0C5C6C] px-3 py-1.5 rounded-xl hover:bg-[#0C5C6C] hover:text-white transition-colors">
                  Voir le profil
                </Link>
              )}
            </div>
          </div>
        )}

        {/* Bouton contact */}
        {annonce.statut === 'disponible' && user?.uid !== annonce.uid_eleveur && (
          <button
            onClick={handleContact}
            disabled={sending || sent}
            className="w-full py-4 rounded-2xl font-['Galey'] font-bold text-white text-base transition-opacity disabled:opacity-60"
            style={{ background: '#0C5C6C' }}>
            {sent ? '✓ Message envoyé' : sending ? 'Envoi...' : '💬 Contacter l\'éleveur'}
          </button>
        )}

        {!user && (
          <Link href="/connexion"
            className="block w-full py-4 rounded-2xl font-['Galey'] font-bold text-white text-base text-center"
            style={{ background: '#0C5C6C' }}>
            Se connecter pour contacter
          </Link>
        )}

        {user && annonce && user.uid !== annonce.uid_eleveur && (
          <button
            type="button"
            onClick={() => { setShowSigModal(true); setSigDesc(''); setSigRaison('contenu_inapproprie'); }}
            className="w-full text-center text-xs text-gray-400 hover:text-gray-600 py-1 transition-colors"
          >
            ⚑ Signaler cette annonce
          </button>
        )}

      </div>
    </div>

    {/* Modal likers */}
    {showLikersModal && user && likers.length > 0 && (
      <div className="fixed inset-0 bg-black/60 z-50 flex items-end justify-center sm:items-center" onClick={() => setShowLikersModal(false)}>
        <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-sm max-h-[60vh] flex flex-col" onClick={e => e.stopPropagation()}>
          <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
            <div className="flex items-center gap-2">
              <span className="text-red-400">❤️</span>
              <span className="font-['Galey'] font-bold text-[#1F2A2E]">
                {likeCount} j&apos;aime{likeCount > 1 ? 's' : ''}
              </span>
            </div>
            <button onClick={() => setShowLikersModal(false)} className="text-gray-400 hover:text-gray-600 transition-colors">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M18 6L6 18M6 6l12 12"/>
              </svg>
            </button>
          </div>
          <div className="overflow-y-auto flex-1">
            {likers.map(l => (
              <div key={l.uid} className="flex items-center gap-3 px-5 py-3 hover:bg-gray-50 transition-colors">
                <div className="w-10 h-10 rounded-full bg-[#0C5C6C] flex items-center justify-center overflow-hidden flex-shrink-0">
                  {l.profile_picture_url ? (
                    <Image src={l.profile_picture_url} alt="" width={40} height={40} className="object-cover" unoptimized />
                  ) : (
                    <span className="text-white text-lg">👤</span>
                  )}
                </div>
                <span className="font-['Galey'] font-semibold text-sm text-[#1F2A2E] flex-1">
                  {l.firstname ?? 'Utilisateur'}
                </span>
                <span className="text-red-300 text-sm">❤️</span>
              </div>
            ))}
            {likeCount > likers.length && (
              <p className="text-center text-xs text-gray-400 py-3 font-['Galey']">
                ... et {likeCount - likers.length} autre{likeCount - likers.length > 1 ? 's' : ''}
              </p>
            )}
          </div>
        </div>
      </div>
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
          {sigSent && <p className="text-[#6E9E57] text-sm text-center mb-3">✓ Signalement envoyé. Merci.</p>}
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
    </>
  );
}
