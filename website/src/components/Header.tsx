'use client';

import { useState, useRef, useEffect } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { usePathname } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { signOut } from 'firebase/auth';
import { auth, db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import { collection, query, where, onSnapshot } from 'firebase/firestore';

interface Notif {
  id: string;
  type: string;
  title: string;
  body: string;
  read: boolean;
  created_at: string | null;
  data?: Record<string, string>;
}

// ── Navigation selon profil ───────────────────────────────────────────────────

const NAV_GUEST = [
  { href: '/annonces',       label: 'Annonces' },
  { href: '/elevages',       label: 'Élevages' },
  { href: '/animaux-perdus', label: 'Animaux perdus' },
];

const NAV_ELEVEUR = [
  { href: '/',               label: 'Accueil' },
  { href: '/mes-animaux',    label: 'Mes Animaux' },
  { href: '/mes-annonces',   label: 'Mes Annonces' },
  { href: '/animaux-perdus', label: 'Animaux perdus' },
  { href: '/services',       label: 'Services' },
  { href: '/messages',       label: 'Messages' },
];

const NAV_PARTICULIER = [
  { href: '/',               label: 'Accueil' },
  { href: '/mes-animaux',    label: 'Mes Animaux' },
  { href: '/annonces',       label: 'Annonces' },
  { href: '/animaux-perdus', label: 'Animaux perdus' },
  { href: '/services',       label: 'Services' },
  { href: '/messages',       label: 'Messages' },
];

// ── Menu drawer items (miroir des drawers de l'app) ──────────────────────────

const MENU_ELEVEUR = [
  {
    section: 'Mon Élevage',
    icon: '🐾',
    items: [
      { href: '/mes-animaux',                    label: 'Mes Animaux',        icon: '🐾' },
      { href: '/mes-annonces',                   label: 'Mes Annonces',       icon: '📋' },
      { href: '/annonces/creer',                 label: 'Nouvelle annonce',   icon: '➕' },
      { href: '/elevage/registre-sanitaire',     label: 'Suivi sanitaire',    icon: '🏥' },
      { href: '/elevage/registre-entree-sortie', label: 'Entrées / Sorties',  icon: '📂' },
      { href: '/elevage/facturation',            label: 'Facturation',        icon: '🧾' },
    ],
  },
  {
    section: 'Annonces',
    icon: '📢',
    items: [
      { href: '/annonces',   label: 'Trouver un compagnon', icon: '❤️' },
      { href: '/elevages',   label: 'Carte des élevages',   icon: '🗺️' },
    ],
  },
  {
    section: 'Animaux perdus',
    icon: '🔍',
    items: [
      { href: '/mes-alertes',    label: 'Gérer mes alertes',       icon: '🔔' },
      { href: '/animaux-perdus', label: 'Voir les animaux perdus', icon: '🔍' },
    ],
  },
  {
    section: 'Services',
    icon: '🏥',
    items: [
      { href: '/services', label: 'Annuaire des services', icon: '🔎' },
    ],
  },
];

const MENU_PENSION = [
  {
    section: 'Ma Pension',
    icon: '🏡',
    items: [
      { href: '/pension/registre',  label: 'Registre pension',     icon: '📋' },
      { href: '/pension/demandes',  label: 'Demandes d\'accès',    icon: '🔑' },
      { href: '/pension/rdv',       label: 'Gestion des RDV',      icon: '🗓️' },
      { href: '/agenda',            label: 'Mon agenda',           icon: '📅' },
    ],
  },
  {
    section: 'Services',
    icon: '🏥',
    items: [
      { href: '/services', label: 'Annuaire des services', icon: '🔎' },
    ],
  },
];

const MENU_PARTICULIER = [
  {
    section: 'Mon Profil',
    icon: '👤',
    items: [
      { href: '/profil',      label: 'Mon Profil',  icon: '👤' },
      { href: '/mes-animaux', label: 'Mes Animaux', icon: '🐾' },
    ],
  },
  {
    section: 'Animaux perdus',
    icon: '🔍',
    items: [
      { href: '/mes-alertes',    label: 'Gérer mes alertes',       icon: '🔔' },
      { href: '/animaux-perdus', label: 'Voir les animaux perdus', icon: '🔍' },
    ],
  },
  {
    section: 'Annonces',
    icon: '📢',
    items: [
      { href: '/annonces', label: 'Trouver un compagnon', icon: '❤️' },
      { href: '/elevages', label: 'Élevages',             icon: '🏡' },
    ],
  },
  {
    section: 'Services',
    icon: '🏥',
    items: [
      { href: '/services', label: 'Annuaire des services', icon: '🔎' },
    ],
  },
];

// ── Composant Header ──────────────────────────────────────────────────────────

export default function Header() {
  const { user, userData, loading } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const [dropdownOpen, setDropdownOpen] = useState(false);
  const [bellOpen, setBellOpen] = useState(false);
  const [expandedSections, setExpandedSections] = useState<Record<string, boolean>>({});
  const [notifs, setNotifs] = useState<Notif[]>([]);
  const [unreadMessages, setUnreadMessages] = useState(0);
  const [pensionDialog, setPensionDialog] = useState<Notif | null>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const bellRef = useRef<HTMLDivElement>(null);
  const router = useRouter();
  const pathname = usePathname();

  const isEleveur = userData?.isElevage === true;
  const isPension = userData?.isPro === true && userData?.catPro === 'pension';
  const displayName = userData?.nameElevage ?? userData?.firstname ?? user?.email ?? '';
  const avatar = userData?.profilePictureUrlElevage ?? userData?.profilePictureUrl ?? null;

  const navLinks = loading || !user ? NAV_GUEST : isEleveur ? NAV_ELEVEUR : NAV_PARTICULIER;
  const menuSections = isEleveur
    ? (isPension ? MENU_PENSION : MENU_ELEVEUR)
    : MENU_PARTICULIER;

  // Écoute des messages non lus (identique éleveur + particulier)
  useEffect(() => {
    if (!user) return;
    const q = query(collection(db, 'conversations'), where('participants', 'array-contains', user.uid));
    return onSnapshot(q, snap => {
      const total = snap.docs.reduce((s, d) => s + ((d.data().unreadCount as Record<string, number>)?.[user.uid] ?? 0), 0);
      setUnreadMessages(total);
    }, () => {});
  }, [user]);

  // Écoute des notifications non lues (Supabase)
  useEffect(() => {
    if (!user) return;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    const fetchNotifs = async () => {
      const { data } = await supabase
        .from('notifications')
        .select('*')
        .eq('uid', user.uid)
        .eq('read', false)
        .order('created_at', { ascending: false })
        .limit(20);
      setNotifs((data ?? []) as Notif[]);
    };

    fetchNotifs();

    channel = supabase
      .channel(`header_notifs_${user.uid}`)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'notifications',
        filter: `uid=eq.${user.uid}`,
      }, () => fetchNotifs())
      .subscribe();

    return () => { channel?.unsubscribe(); };
  }, [user]);

  const totalBell = notifs.length + unreadMessages;

  async function markAllRead() {
    if (!user || notifs.length === 0) return;
    await supabase
      .from('notifications')
      .update({ read: true })
      .eq('uid', user.uid)
      .eq('read', false);
    setNotifs([]);
  }

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setDropdownOpen(false);
      }
      if (bellRef.current && !bellRef.current.contains(e.target as Node)) {
        setBellOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  async function handleSignOut() {
    await signOut(auth);
    setDropdownOpen(false);
    setMenuOpen(false);
    router.push('/');
  }

  function toggleSection(section: string) {
    setExpandedSections(prev => ({ ...prev, [section]: !prev[section] }));
  }

  const isActive = (href: string) =>
    href === '/' ? pathname === '/' : pathname.startsWith(href);

  return (
    <header className="bg-[#0C5C6C] shadow-md sticky top-0 z-50">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between gap-4">

        {/* Logo */}
        <Link href="/" className="flex items-center gap-3 flex-shrink-0">
          <Image src="/Logo_petsmatch_fond_blanc.png" alt="PetsMatch" width={40} height={40} className="object-contain rounded-lg" />
          <span className="text-white font-semibold text-xl tracking-wide hidden sm:block" style={{ fontFamily: 'Galey, sans-serif' }}>
            PetsMatch
          </span>
        </Link>

        {/* Desktop nav */}
        <nav className="hidden md:flex items-center gap-1 flex-1 justify-center">
          {navLinks.map((l) => (
            <Link key={l.href} href={l.href}
              className={`px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${
                isActive(l.href)
                  ? 'bg-white/20 text-white'
                  : 'text-white/75 hover:text-white hover:bg-white/10'
              }`}>
              {l.label}
            </Link>
          ))}
        </nav>

        {/* Auth zone */}
        <div className="hidden md:flex items-center gap-3 flex-shrink-0">
          {loading ? null : user ? (
            <>
            {/* ── Enveloppe messages ── */}
            <Link href="/messages"
              className="relative w-9 h-9 rounded-full bg-white/10 hover:bg-white/20 flex items-center justify-center transition-colors">
              <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/>
              </svg>
              {unreadMessages > 0 && (
                <span className="absolute -top-0.5 -right-0.5 w-4 h-4 bg-red-500 text-white text-[10px] font-bold rounded-full flex items-center justify-center">
                  {unreadMessages > 9 ? '9+' : unreadMessages}
                </span>
              )}
            </Link>

            {/* ── Cloche notifications ── */}
            <div className="relative" ref={bellRef}>
              <button
                onClick={() => { setBellOpen(!bellOpen); if (!bellOpen) markAllRead(); }}
                className="relative w-9 h-9 rounded-full bg-white/10 hover:bg-white/20 flex items-center justify-center transition-colors">
                <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
                </svg>
                {totalBell > 0 && (
                  <span className="absolute -top-0.5 -right-0.5 w-4 h-4 bg-red-500 text-white text-[10px] font-bold rounded-full flex items-center justify-center">
                    {totalBell > 9 ? '9+' : totalBell}
                  </span>
                )}
              </button>

              {bellOpen && (
                <div className="absolute right-0 top-full mt-2 w-80 bg-white rounded-2xl shadow-xl border border-gray-100 overflow-hidden z-50">
                  <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
                    <p className="font-semibold text-sm text-[#1F2A2E]">Notifications</p>
                    {notifs.length > 0 && (
                      <button onClick={markAllRead} className="text-xs text-[#0C5C6C] hover:underline">Tout marquer lu</button>
                    )}
                  </div>
                  <div className="max-h-80 overflow-y-auto">
                    {unreadMessages > 0 && (
                      <Link href="/messages" onClick={() => setBellOpen(false)}
                        className="flex items-center gap-3 px-4 py-3 hover:bg-gray-50 border-b border-gray-50">
                        <div className="w-9 h-9 rounded-full bg-[#0C5C6C]/10 flex items-center justify-center text-lg flex-shrink-0">💬</div>
                        <div>
                          <p className="text-sm font-semibold text-[#1F2A2E]">{unreadMessages} message{unreadMessages > 1 ? 's' : ''} non lu{unreadMessages > 1 ? 's' : ''}</p>
                          <p className="text-xs text-gray-400">Voir vos conversations</p>
                        </div>
                      </Link>
                    )}
                    {notifs.map(n => (
                      <div key={n.id} className="flex items-start gap-3 px-4 py-3 hover:bg-gray-50 border-b border-gray-50">
                        <div className="w-9 h-9 rounded-full bg-amber-50 flex items-center justify-center text-lg flex-shrink-0">
                          {n.type === 'alerte_perdu' ? '🔍'
                            : n.type === 'like' ? '❤️'
                            : n.type === 'chaleur' ? '🌸'
                            : n.type === 'rappel_vaccin' ? '💉'
                            : n.type === 'pension_acces' ? '🏡'
                            : '🔔'}
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-semibold text-[#1F2A2E]">{n.title}</p>
                          <p className="text-xs text-gray-500 truncate">{n.body}</p>
                          {n.type === 'pension_acces' && (
                            <button
                              onClick={() => { setBellOpen(false); setPensionDialog(n); }}
                              className="mt-2 text-xs font-bold text-[#0C5C6C] underline cursor-pointer bg-none border-none p-0"
                            >Répondre →</button>
                          )}
                        </div>
                      </div>
                    ))}
                    {totalBell === 0 && (
                      <div className="text-center py-8 text-gray-400 text-sm">
                        <p className="text-3xl mb-2">🔔</p>
                        <p>Aucune notification</p>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>

            {/* ── Avatar + dropdown ── */}
            <div className="relative" ref={dropdownRef}>
              <button
                onClick={() => setDropdownOpen(!dropdownOpen)}
                className="flex items-center gap-2 bg-white/10 hover:bg-white/20 rounded-full pl-2 pr-3 py-1.5 transition-colors">
                <div className="w-7 h-7 rounded-full overflow-hidden bg-[#6E9E57] flex items-center justify-center flex-shrink-0">
                  {avatar ? (
                    <Image src={avatar} alt="" width={28} height={28} className="object-cover w-full h-full" />
                  ) : (
                    <span className="text-white text-xs font-bold">{(displayName[0] ?? '?').toUpperCase()}</span>
                  )}
                </div>
                <span className="text-white text-sm font-medium truncate max-w-[100px]">{displayName}</span>
                <svg className={`w-4 h-4 text-white/70 transition-transform ${dropdownOpen ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              </button>

              {dropdownOpen && (
                <div className="absolute right-0 top-full mt-2 w-64 bg-white rounded-2xl shadow-xl border border-gray-100 overflow-hidden">
                  {/* Header */}
                  <div className="bg-[#0C5C6C] px-4 py-3 flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full overflow-hidden bg-[#6E9E57] flex items-center justify-center flex-shrink-0">
                      {avatar ? (
                        <Image src={avatar} alt="" width={40} height={40} className="object-cover w-full h-full" />
                      ) : (
                        <span className="text-white text-sm font-bold">{(displayName[0] ?? '?').toUpperCase()}</span>
                      )}
                    </div>
                    <div className="min-w-0">
                      <p className="text-white font-semibold text-sm truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{displayName}</p>
                      <p className="text-white/60 text-xs">{isEleveur ? '✅ Éleveur' : '👤 Particulier'}</p>
                    </div>
                  </div>

                  {/* Sections */}
                  <div className="py-1 max-h-96 overflow-y-auto">
                    {menuSections.map((sec) => (
                      <div key={sec.section}>
                        <button
                          onClick={() => toggleSection(sec.section)}
                          className="w-full flex items-center gap-2 px-4 py-2.5 text-sm font-semibold text-gray-700 hover:bg-gray-50 transition-colors">
                          <span>{sec.icon}</span>
                          <span className="flex-1 text-left">{sec.section}</span>
                          <svg className={`w-4 h-4 text-gray-400 transition-transform ${expandedSections[sec.section] ? 'rotate-180' : ''}`}
                            fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                          </svg>
                        </button>
                        {expandedSections[sec.section] && (
                          <div className="bg-gray-50">
                            {sec.items.map((item) => (
                              <Link key={item.href} href={item.href}
                                onClick={() => setDropdownOpen(false)}
                                className="flex items-center gap-3 pl-10 pr-4 py-2 text-sm text-gray-600 hover:bg-gray-100 transition-colors">
                                <span className="text-base">{item.icon}</span>
                                {item.label}
                              </Link>
                            ))}
                          </div>
                        )}
                      </div>
                    ))}

                    <div className="border-t border-gray-100 mt-1">
                      <Link href="/profil" onClick={() => setDropdownOpen(false)}
                        className="flex items-center gap-3 px-4 py-2.5 text-sm text-gray-700 hover:bg-gray-50 transition-colors">
                        <span>⚙️</span> Mon Profil
                      </Link>
                      {!isEleveur && (
                        <Link href="/mes-alertes" onClick={() => setDropdownOpen(false)}
                          className="flex items-center gap-3 px-4 py-2.5 text-sm text-gray-700 hover:bg-gray-50 transition-colors">
                          <span>🔔</span> Mes Alertes perdus
                        </Link>
                      )}
                      <Link href="/favoris" onClick={() => setDropdownOpen(false)}
                        className="flex items-center gap-3 px-4 py-2.5 text-sm text-gray-700 hover:bg-gray-50 transition-colors">
                        <span>❤️</span> Mes interactions
                      </Link>
                    </div>

                    <div className="border-t border-gray-100">
                      <button onClick={handleSignOut}
                        className="flex items-center gap-3 w-full px-4 py-2.5 text-sm text-red-500 hover:bg-red-50 transition-colors">
                        <span>🚪</span> Déconnexion
                      </button>
                    </div>
                  </div>
                </div>
              )}
            </div>
            </>
          ) : (
            <>
              <Link href="/connexion" className="text-sm text-white/80 hover:text-white font-medium transition-colors">
                Se connecter
              </Link>
              <Link href="/inscription"
                className="text-sm bg-[#6E9E57] hover:bg-[#5A8A45] text-white font-semibold px-4 py-2 rounded-full transition-colors">
                S'inscrire
              </Link>
            </>
          )}
        </div>

        {/* Mobile : cloche + hamburger */}
        <div className="md:hidden flex items-center gap-2">
          {user && (
            <Link href="/messages" className="relative w-9 h-9 rounded-full bg-white/10 flex items-center justify-center">
              <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
              </svg>
              {totalBell > 0 && (
                <span className="absolute -top-0.5 -right-0.5 w-4 h-4 bg-red-500 text-white text-[10px] font-bold rounded-full flex items-center justify-center">
                  {totalBell > 9 ? '9+' : totalBell}
                </span>
              )}
            </Link>
          )}
          <button className="text-white p-1" onClick={() => setMenuOpen(!menuOpen)}>
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              {menuOpen
                ? <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                : <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />}
            </svg>
          </button>
        </div>
      </div>

      {/* Mobile menu */}
      {menuOpen && (
        <div className="md:hidden bg-[#094F5D] px-4 pb-4 max-h-[80vh] overflow-y-auto">
          {/* Nav links */}
          <div className="space-y-0.5 pt-2">
            {navLinks.map((l) => (
              <Link key={l.href} href={l.href} onClick={() => setMenuOpen(false)}
                className={`block py-2.5 text-sm font-medium border-b border-white/10 ${
                  isActive(l.href) ? 'text-white' : 'text-white/75 hover:text-white'
                }`}>
                {l.label}
              </Link>
            ))}
          </div>

          {!loading && user ? (
            <div className="mt-3">
              {/* Profile summary */}
              <div className="flex items-center gap-3 py-3 border-b border-white/10 mb-2">
                <div className="w-9 h-9 rounded-full overflow-hidden bg-[#6E9E57] flex items-center justify-center flex-shrink-0">
                  {avatar ? (
                    <Image src={avatar} alt="" width={36} height={36} className="object-cover w-full h-full" />
                  ) : (
                    <span className="text-white text-xs font-bold">{(displayName[0] ?? '?').toUpperCase()}</span>
                  )}
                </div>
                <div>
                  <p className="text-white text-sm font-semibold">{displayName}</p>
                  <p className="text-white/50 text-xs">{isEleveur ? 'Éleveur' : 'Particulier'}</p>
                </div>
              </div>

              {/* Sections */}
              {menuSections.map((sec) => (
                <div key={sec.section}>
                  <button
                    onClick={() => toggleSection(sec.section)}
                    className="w-full flex items-center gap-2 py-2 text-white/80 text-sm font-semibold">
                    <span>{sec.icon}</span>
                    <span className="flex-1 text-left">{sec.section}</span>
                    <svg className={`w-4 h-4 text-white/40 transition-transform ${expandedSections[sec.section] ? 'rotate-180' : ''}`}
                      fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                    </svg>
                  </button>
                  {expandedSections[sec.section] && (
                    <div className="pl-6 space-y-0.5 mb-1">
                      {sec.items.map((item) => (
                        <Link key={item.href} href={item.href} onClick={() => setMenuOpen(false)}
                          className="flex items-center gap-2 py-2 text-white/70 hover:text-white text-sm">
                          <span>{item.icon}</span> {item.label}
                        </Link>
                      ))}
                    </div>
                  )}
                </div>
              ))}

              <div className="border-t border-white/10 mt-2 pt-2 space-y-0.5">
                <Link href="/profil" onClick={() => setMenuOpen(false)}
                  className="flex items-center gap-2 py-2 text-white/70 hover:text-white text-sm">
                  ⚙️ Mon Profil
                </Link>
                <Link href="/favoris" onClick={() => setMenuOpen(false)}
                  className="flex items-center gap-2 py-2 text-white/70 hover:text-white text-sm">
                  ❤️ Mes interactions
                </Link>
                <button onClick={handleSignOut}
                  className="flex items-center gap-2 py-2 text-red-300 hover:text-red-200 text-sm">
                  🚪 Déconnexion
                </button>
              </div>
            </div>
          ) : !loading && (
            <div className="pt-3 flex gap-3">
              <Link href="/connexion" onClick={() => setMenuOpen(false)}
                className="flex-1 text-center text-sm text-white border border-white/30 rounded-full py-2 hover:bg-white/10">
                Se connecter
              </Link>
              <Link href="/inscription" onClick={() => setMenuOpen(false)}
                className="flex-1 text-center text-sm bg-[#6E9E57] text-white font-semibold rounded-full py-2 hover:bg-[#5A8A45]">
                S'inscrire
              </Link>
            </div>
          )}
        </div>
      )}

      {/* Dialog pension_acces — accepter / refuser */}
      {pensionDialog && user && (
        <PensionAccesDialog
          notif={pensionDialog}
          ownerUid={user.uid}
          onClose={() => setPensionDialog(null)}
          onDone={async (approved: boolean) => {
            const d = pensionDialog.data ?? {};
            const pensionUid = d.pensionUid;
            const animalId   = d.animalId;
            const animalNom  = d.animalNom ?? 'cet animal';
            const pensionNom = d.pensionNom ?? 'La pension';
            if (!pensionUid || !animalId) { setPensionDialog(null); return; }

            const newStatut = approved ? 'approved' : 'refused';
            await supabase.from('pension_acces').update({ statut: newStatut })
              .eq('pro_uid', pensionUid).eq('animal_id', animalId);

            await supabase.from('notifications').insert({
              uid:   pensionUid,
              type:  'pension_acces_reponse',
              title: approved ? `Accès accordé pour ${animalNom}` : `Demande refusée pour ${animalNom}`,
              body:  approved
                ? `Le propriétaire vous a autorisé à consulter la fiche de ${animalNom}.`
                : `Le propriétaire a refusé votre demande pour ${animalNom}.`,
              data:  { animalId, animalNom, approved: String(approved) },
              read:  false,
            });

            await supabase.from('notifications').delete().eq('id', pensionDialog.id);
            setNotifs(prev => prev.filter(n => n.id !== pensionDialog.id));
            setPensionDialog(null);
          }}
        />
      )}
    </header>
  );
}

// ── Dialog Autoriser / Refuser accès pension ──────────────────────────────────

function PensionAccesDialog({ notif, ownerUid: _ownerUid, onClose, onDone }: {
  notif: Notif;
  ownerUid: string;
  onClose: () => void;
  onDone: (approved: boolean) => Promise<void>;
}) {
  const [loading, setLoading] = useState(false);

  async function handle(approved: boolean) {
    setLoading(true);
    await onDone(approved);
    setLoading(false);
  }

  return (
    <div style={{
      position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      zIndex: 2000, padding: 16,
    }}>
      <div style={{
        background: 'white', borderRadius: 20, padding: 28,
        maxWidth: 440, width: '100%', boxShadow: '0 20px 60px rgba(0,0,0,0.2)',
      }}>
        <div style={{ textAlign: 'center', marginBottom: 20 }}>
          <div style={{ fontSize: 40, marginBottom: 12 }}>🏡</div>
          <h2 style={{ margin: '0 0 8px', fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 18, color: '#1F2A2E' }}>
            {notif.title}
          </h2>
          <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontSize: 14, color: '#6F767B', lineHeight: 1.5 }}>
            {notif.body}
          </p>
        </div>

        <div style={{ display: 'flex', gap: 12 }}>
          <button disabled={loading} onClick={() => handle(false)} style={{
            flex: 1, padding: '12px 0', borderRadius: 10,
            border: '1px solid #d32f2f', background: 'transparent',
            color: '#d32f2f', fontFamily: 'Galey, sans-serif',
            fontWeight: 700, fontSize: 14, cursor: loading ? 'not-allowed' : 'pointer',
          }}>Refuser</button>

          <button disabled={loading} onClick={() => handle(true)} style={{
            flex: 1, padding: '12px 0', borderRadius: 10,
            border: 'none', background: '#0C5C6C', color: 'white',
            fontFamily: 'Galey, sans-serif', fontWeight: 700,
            fontSize: 14, cursor: loading ? 'not-allowed' : 'pointer',
            opacity: loading ? 0.7 : 1,
          }}>{loading ? '…' : 'Autoriser'}</button>
        </div>

        <button onClick={onClose} style={{
          display: 'block', margin: '16px auto 0', background: 'none', border: 'none',
          color: '#9ca3af', fontFamily: 'Galey, sans-serif', fontSize: 13, cursor: 'pointer',
        }}>Annuler</button>
      </div>
    </div>
  );
}
