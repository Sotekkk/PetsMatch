'use client';

import { useState, useRef, useEffect } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { usePathname } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { signOut } from 'firebase/auth';
import { auth, db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { usePlan, usePensionPlan } from '@/lib/use-plan';
import { useRouter } from 'next/navigation';
import { ACTIVE_PROFILE_KEY, ACTIVE_PROFILE_TYPE_KEY, PROFILE_CHANGE_EVENT } from '@/hooks/useActiveProfile';

interface Notif {
  id: string;
  type: string;
  title: string;
  body: string;
  read: boolean;
  created_at: string | null;
  data?: Record<string, string>;
}

interface UserProfile {
  id: string;
  profile_type: string;
  is_main: boolean;
  profile_label: string | null;
  nom: string | null;
  avatar_url: string | null;
  name_elevage: string | null;
  cat_pro: string | null;
}

// ── Navigation selon profil ───────────────────────────────────────────────────

const NAV_GUEST = [
  { href: '/annonces',       label: 'Annonces' },
  { href: '/adoptions',      label: '💚 Adoptions' },
  { href: '/elevages',       label: 'Élevages' },
  { href: '/associations',   label: 'Associations' },
  { href: '/animaux-perdus', label: 'Animaux perdus' },
  { href: '/services',       label: 'Annuaire' },
  { href: '/communaute',     label: 'Communauté' },
  { href: '/marketplace',    label: 'Marketplace' },
];

const NAV_ELEVEUR = [
  { href: '/mes-animaux',             label: 'Mes Animaux' },
  { href: '/mes-annonces',            label: 'Mes Annonces' },
  { href: '/abonnement',              label: 'Abonnement' },
  { href: '/services',                label: 'Annuaire' },
  { href: '/communaute',              label: 'Communauté' },
  { href: '/marketplace',             label: 'Marketplace' },
];

// NAV spécifique profils pro secondaires (pas d'élevage)
const NAV_PRO = [
  { href: '/',                     label: 'Accueil' },
  { href: '/adoptions', label: '💚 Adoptions' },
  { href: '/agenda',               label: 'Agenda' },
  { href: '/services',             label: 'Annuaire' },
  { href: '/communaute',           label: 'Communauté' },
  { href: '/messages',             label: 'Messages' },
];

const NAV_VET = [
  { href: '/',                     label: 'Accueil' },
  { href: '/adoptions', label: '💚 Adoptions' },
  { href: '/agenda',               label: 'Agenda' },
  { href: '/mes-patients',         label: 'Patients' },
  { href: '/messages',             label: 'Messages' },
];

const NAV_PARTICULIER = [
  { href: '/',                     label: 'Accueil' },
  { href: '/mes-animaux',          label: 'Mes Animaux' },
  { href: '/agenda',               label: 'Agenda' },
  { href: '/annonces',             label: 'Annonces' },
  { href: '/adoptions', label: '💚 Adoptions' },
  { href: '/animaux-perdus',       label: 'Animaux perdus' },
  { href: '/services',             label: 'Annuaire' },
  { href: '/communaute',           label: 'Communauté' },
  { href: '/marketplace',          label: 'Marketplace' },
  { href: '/messages',             label: 'Messages' },
];

const NAV_ASSOCIATION = [
  { href: '/association',              label: 'Mon Association' },
  { href: '/association/animaux',      label: 'Mes Animaux' },
  { href: '/association/annonces',     label: 'Mes Annonces' },
  { href: '/association/planning',     label: 'Planning' },
  { href: '/animaux-perdus',           label: 'Animaux perdus' },
  { href: '/messages',                 label: 'Messages' },
];

// ── Menu drawer items (miroir des drawers de l'app) ──────────────────────────

const MENU_ELEVEUR = [
  {
    section: 'Mon Élevage',
    icon: '🐾',
    items: [
      { href: '/mes-animaux',                    label: 'Mes Animaux',        icon: '🐾' },
      { href: '/elevage/agenda',                 label: 'Agenda',     icon: '🗓️' },
      { href: '/elevage/planning',               label: 'Protocoles',         icon: '📅' },
      { href: '/elevage/registre-sanitaire',     label: 'Suivi sanitaire',    icon: '🏥', pro: true },
      { href: '/elevage/inventaire',              label: 'Inventaire',         icon: '📦' },
      { href: '/employes',                        label: 'Mes employés',       icon: '👥' },
      { href: '/elevage/registre-entree-sortie', label: 'Entrée - Sortie',  icon: '📂', pro: true },
    ],
  },
  {
    section: 'Administratif',
    icon: '📁',
    items: [
      { href: '/elevage/contrat',               label: 'Mes Contrats',      icon: '📄', premium: true },
      { href: '/mes-contrats',                  label: 'Mes Contrats reçus', icon: '📄' },
      { href: '/elevage/facturation',            label: 'Facturation',        icon: '🧾', premium: true },
    ],
  },
  {
    section: 'Annonces',
    icon: '📢',
    items: [
      { href: '/mes-annonces',   label: 'Mes Annonces',         icon: '📋' },
      { href: '/annonces/creer', label: 'Nouvelle annonce',     icon: '➕' },
      { href: '/annonces',       label: 'Trouver un compagnon', icon: '❤️' },
      { href: '/elevages',       label: 'Carte des élevages',   icon: '🗺️' },
    ],
  },
  {
    section: 'Animaux perdus / trouvés',
    icon: '🔍',
    items: [
      { href: '/mes-alertes',    label: 'Gérer mes alertes',       icon: '🔔' },
      { href: '/animaux-perdus', label: 'Voir les animaux perdus', icon: '🔍' },
    ],
  },
  {
    section: 'Annuaire & Communauté',
    icon: '🔎',
    items: [
      { href: '/services',    label: 'Annuaire des professionnels', icon: '🔎' },
      { href: '/communaute',  label: 'Communauté',                  icon: '👥' },
    ],
  },
];

// Menu vétérinaire / santé animale
const MENU_VET = [
  {
    section: 'Mon Activité',
    icon: '🩺',
    items: [
      { href: '/agenda',        label: 'Mon agenda',      icon: '📅' },
      { href: '/mes-rdv',       label: 'Gérer mes RDV',   icon: '🗓️' },
      { href: '/pro/creneaux',  label: 'Mes créneaux',    icon: '⏰' },
      { href: '/mes-patients',  label: 'Mes patients',    icon: '🐾' },
    ],
  },
  {
    section: 'Mon Profil',
    icon: '👤',
    items: [
      { href: '/profil',     label: 'Modifier mon profil', icon: '✏️' },
      { href: '/mes-taches', label: 'Mes tâches',          icon: '✅' },
    ],
  },
  {
    section: 'Annuaire & Communauté',
    icon: '🔎',
    items: [
      { href: '/services',    label: 'Annuaire des professionnels', icon: '🔎' },
      { href: '/communaute',  label: 'Communauté',                  icon: '👥' },
      { href: '/marketplace', label: 'Marketplace',                 icon: '🛍️' },
    ],
  },
];

// Menu générique pour tous les pros sauf pension/vet
const MENU_PRO = [
  {
    section: 'Mon Activité',
    icon: '📅',
    items: [
      { href: '/agenda',       label: 'Mon agenda',      icon: '📅' },
      { href: '/mes-rdv',      label: 'Gérer mes RDV',   icon: '🗓️' },
      { href: '/pro/creneaux', label: 'Mes créneaux',    icon: '⏰' },
    ],
  },
  {
    section: 'Mon Profil',
    icon: '👤',
    items: [
      { href: '/profil',     label: 'Modifier mon profil', icon: '✏️' },
      { href: '/employes',   label: 'Mes employés',        icon: '👥' },
      { href: '/mes-taches', label: 'Mes tâches',          icon: '✅' },
    ],
  },
  {
    section: 'Annuaire & Communauté',
    icon: '🔎',
    items: [
      { href: '/services',    label: 'Annuaire des professionnels', icon: '🔎' },
      { href: '/communaute',  label: 'Communauté',                  icon: '👥' },
      { href: '/marketplace', label: 'Marketplace',                 icon: '🛍️' },
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
      { href: '/pension/chenil',    label: 'Logements / Chenil',   icon: '🏘️' },
      { href: '/pension/planning',  label: 'Planning occupation',  icon: '📆', pro: true },
      { href: '/pension/contrat',   label: 'Contrats',             icon: '✍️', pro: true },
      { href: '/mes-rdv',           label: 'Gestion des RDV',      icon: '🗓️' },
      { href: '/pro/creneaux',      label: 'Mes créneaux',         icon: '⏰' },
      { href: '/agenda',            label: 'Mon agenda',           icon: '📅' },
      { href: '/elevage/inventaire',label: 'Inventaire',           icon: '📦', pro: true },
      { href: '/mes-taches',        label: 'Mes tâches',           icon: '✅', pro: true },
      { href: '/employes',          label: 'Mes employés',         icon: '👥', pro: true },
      { href: '/elevage/facturation',label: 'Facturation',          icon: '🧾' },
      { href: '/pension/abonnement', label: 'Mon abonnement',       icon: '💳' },
    ],
  },
  {
    section: 'Annuaire & Communauté',
    icon: '🔎',
    items: [
      { href: '/services',   label: 'Annuaire des professionnels', icon: '🔎' },
      { href: '/communaute', label: 'Communauté',                  icon: '👥' },
    ],
  },
];

const MENU_ASSOCIATION = [
  {
    section: 'Mon Association',
    icon: '🐾',
    items: [
      { href: '/association',                            label: 'Tableau de bord',       icon: '🏠' },
      { href: '/association/animaux',                    label: 'Mes Animaux',           icon: '🐾' },
      { href: '/association/familles-accueil',           label: 'Familles d\'accueil',   icon: '🏡' },
      { href: '/association/chenil',                     label: 'Chenil / Planning',     icon: '🗓️' },
      { href: '/association/planning',                   label: 'Protocoles',            icon: '📅' },
      { href: '/association/registre-sanitaire',         label: 'Suivi sanitaire',       icon: '🏥' },
      { href: '/association/inventaire',                 label: 'Inventaire',            icon: '📦' },
      { href: '/association/benevoles',                  label: 'Bénévoles',             icon: '🤝' },
      { href: '/employes',                               label: 'Mes employés',          icon: '👥' },
      { href: '/association/registre-entree-sortie',     label: 'Entrée - Sortie',       icon: '📂' },
      { href: '/mes-taches',                             label: 'Mes tâches',            icon: '✅' },
    ],
  },
  {
    section: 'Agenda & RDV',
    icon: '🗓️',
    items: [
      { href: '/association/agenda', label: 'Agenda',    icon: '🗓️' },
      { href: '/mes-rdv',            label: 'Mes RDV',   icon: '📅' },
      { href: '/mes-taches',         label: 'Mes tâches', icon: '✅' },
    ],
  },
  {
    section: 'Administratif',
    icon: '📁',
    items: [
      { href: '/association/contrat',               label: 'Contrats d\'adoption', icon: '📋' },
      { href: '/association/certificat-engagement', label: 'Certificats',           icon: '✍️' },
      { href: '/association/facturation',           label: 'Facturation',           icon: '🧾' },
    ],
  },
  {
    section: 'Annonces',
    icon: '📢',
    items: [
      { href: '/association/annonces',       label: 'Mes Annonces',         icon: '📣' },
      { href: '/association/annonces/creer', label: 'Nouvelle annonce',     icon: '➕' },
      { href: '/annonces',                   label: 'Trouver un compagnon', icon: '❤️' },
    ],
  },
  {
    section: 'Animaux perdus / trouvés',
    icon: '🔍',
    items: [
      { href: '/mes-alertes',    label: 'Gérer mes alertes',       icon: '🔔' },
      { href: '/animaux-perdus', label: 'Voir les animaux perdus', icon: '🔍' },
    ],
  },
  {
    section: 'Annuaire & Communauté',
    icon: '🔎',
    items: [
      { href: '/services',    label: 'Annuaire des professionnels', icon: '🔎' },
      { href: '/communaute',  label: 'Communauté',                  icon: '👥' },
      { href: '/marketplace', label: 'Marketplace',                 icon: '🛍️' },
    ],
  },
];

const MENU_PARTICULIER = [
  {
    section: 'Mon Profil',
    icon: '👤',
    items: [
      { href: '/profil',              label: 'Mon Profil',         icon: '👤' },
      { href: '/mes-animaux',         label: 'Mes Animaux',        icon: '🐾' },
      { href: '/mes-animaux-acquis',  label: 'Mes Animaux Acquis', icon: '🤝' },
      { href: '/agenda',              label: 'Mon Agenda',         icon: '🗓️' },
      { href: '/mes-taches',          label: 'Mes tâches',         icon: '✅' },
    ],
  },
  {
    section: 'Administratif',
    icon: '📄',
    items: [
      { href: '/mes-contrats', label: 'Mes Contrats', icon: '📄' },
    ],
  },
  {
    section: 'Animaux perdus / trouvés',
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
      { href: '/annonces',      label: 'Trouver un compagnon', icon: '❤️' },
      { href: '/adoptions',     label: 'Adoptions',            icon: '💚' },
      { href: '/elevages',      label: 'Élevages',             icon: '🏡' },
      { href: '/associations',  label: 'Associations',         icon: '🏠' },
    ],
  },
  {
    section: 'Annuaire & Communauté',
    icon: '🔎',
    items: [
      { href: '/services',   label: 'Annuaire des professionnels', icon: '🔎' },
      { href: '/communaute', label: 'Communauté',                  icon: '👥' },
    ],
  },
];

// ── Helpers types profil ──────────────────────────────────────────────────────

const PRO_TYPES = new Set(['veterinaire', 'sante', 'education', 'garde', 'pension', 'toilettage', 'photographe', 'marechal_ferrant']);

function typeLabel(type: string): string {
  return ({
    particulier:      'Particulier',
    association:      'Association',
    eleveur:          'Éleveur',
    veterinaire:      'Vétérinaire',
    para_medical:     'Para-médical',
    education:        'Éducation',
    petsitter:        'Pet-sitter',
    pension:          'Pension',
    promeneur:        'Promeneur',
    photographe:      'Photographe',
    marechal_ferrant: 'Maréchal-ferrant',
    petfriendly:      'Lieu Pet-Friendly',
    partenaire:       'Partenaire',
  } as Record<string, string>)[type] ?? 'Profil';
}

function typeEmoji(type: string): string {
  return ({
    particulier:      '👤',
    association:      '🐾',
    eleveur:          '🐾',
    veterinaire:      '🏥',
    para_medical:     '💆',
    education:        '🧠',
    petsitter:        '🏠',
    pension:          '🏨',
    promeneur:        '🚶',
    photographe:      '📷',
    marechal_ferrant: '🔨',
    petfriendly:      '📍',
    partenaire:       '🤝',
  } as Record<string, string>)[type] ?? '👤';
}

// ACTIVE_PROFILE_KEY et PROFILE_CHANGE_EVENT importés depuis useActiveProfile

// ── Navigation par type de notification ──────────────────────────────────────
function getNotifUrl(n: Notif): string | null {
  const d = n.data ?? {};
  switch (n.type) {
    case 'like':
      return d.annonceId
        ? `/annonces/${d.annonceId}${d.bebeIndex != null && d.bebeIndex !== '' ? `?bebe=${d.bebeIndex}` : ''}`
        : '/mes-annonces';
    case 'alerte_perdu':
      return '/animaux-perdus';
    case 'chaleur':
      return '/mes-animaux';
    case 'rappel_vaccin':
      return d.animalId ? `/mes-animaux/${d.animalId}` : '/mes-animaux';
    case 'annonce_expiration':
      return '/mes-annonces';
    case 'cession_signature_demandee':
      return d.signingUrl ?? (d.token ? `/signer-cession/${d.token}` : null);
    case 'cession_confirmee':
    case 'cession_animal':
      return d.animalId ? `/mes-animaux/${d.animalId}?readOnly=1` : '/mes-animaux-acquis';
    case 'cession_signee_acquereur':
    case 'cession_signe_acquereur':
      return d.animalId ? `/mes-animaux/${d.animalId}` : '/mes-animaux';
    case 'cession_revoquee':
      return null;
    case 'contrat_saillie_invite':
    case 'contrat_signe_eleveur':
    case 'contrat_signe_complet':
      return d.url ?? '/elevage/contrat';
    case 'contrat_signe_acquereur':
    case 'contrat_refuse':
    case 'contrat_expire':
      return '/elevage/contrat';
    case 'pension_acces':
      return null; // géré par dialog
    case 'pension_acces_reponse':
      return d.approved === 'true' && d.animalId ? `/mes-animaux/${d.animalId}` : null;
    case 'rdv_demande':
    case 'rdv_contre_proposition':
    case 'rdv_annule_client':
      return '/mes-rdv';
    case 'rdv_confirme':
    case 'rdv_refuse':
    case 'rdv_annule':
      return '/agenda';
    case 'promenade_join':
    case 'promenade_accepte':
    case 'promenade_refuse':
    case 'promenade_annulee':
    case 'promenade_modifiee':
      return d.promenadeId ? `/promenades/${d.promenadeId}` : '/promenades';
    case 'petfriend_request':
    case 'petfriend_accepted':
      return d.fromUid ? `/profil/${d.fromUid}` : '/petfriends';
    case 'employee_invite':
    case 'tache':
      return '/mes-employeurs';
    case 'sante_vet':
      return d.animalId ? `/mes-animaux/${d.animalId}` : null;
    case 'vet_access_reponse':
      return '/mes-patients';
    case 'profil_en_attente':
    case 'profil_valide':
      return '/profil';
    default:
      return null;
  }
}

// ── Composant Header ──────────────────────────────────────────────────────────

export default function Header() {
  const { user, userData, loading, availableProfiles: authProfiles, activeProfileId: authActiveId, setActiveProfileId: authSetActiveId } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const [dropdownOpen, setDropdownOpen] = useState(false);
  const [bellOpen, setBellOpen] = useState(false);
  const [expandedSections, setExpandedSections] = useState<Record<string, boolean>>({});
  const [notifs, setNotifs] = useState<Notif[]>([]);
  const [unreadMessages, setUnreadMessages] = useState(0);
  const [pensionDialog, setPensionDialog] = useState<Notif | null>(null);
  // Profile switching — utilise directement les profils chargés par AuthContext
  const profiles: UserProfile[] = authProfiles as unknown as UserProfile[];
  const [isFa, setIsFa] = useState(false);
  const [isEmploye, setIsEmploye] = useState(false);
  const [isBenevole, setIsBenevole] = useState(false);
  const activeProfileId = authActiveId;
  const cachedProfileType: string | null =
    typeof window !== 'undefined' ? (localStorage.getItem(ACTIVE_PROFILE_TYPE_KEY) ?? null) : null;
  const [profileSwitcherOpen, setProfileSwitcherOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const bellRef = useRef<HTMLDivElement>(null);
  const router = useRouter();
  const pathname = usePathname();
  const { plan: eleveurPlan } = usePlan();
  const { plan: pensionPlan } = usePensionPlan();

  // ── Effective profile data (primary or secondary) ─────────────────────────
  const activeProfile = profiles.find(p => p.id === activeProfileId) ?? null;

  // Si un profil secondaire est sélectionné (activeProfileId non vide) mais que les
  // profils ne sont pas encore chargés depuis Supabase, on utilise le type mis en cache
  // dans localStorage pour éviter de tomber sur les données du profil primaire.
  const resolvedProfileType: string | null =
    activeProfile?.profile_type ??
    (activeProfileId && !activeProfile ? cachedProfileType : null);

  const effectiveIsAssociation =
    (resolvedProfileType === 'association') ||
    (!resolvedProfileType && userData?.isAssociation === true);

  const effectiveType = resolvedProfileType ?? (
    userData?.isPro ? (userData?.catPro ?? 'sante')
    : userData?.isAssociation ? 'association'
    : (userData?.isElevage ? 'eleveur' : 'particulier')
  );
  const effectiveIsEleveur = resolvedProfileType
    ? (resolvedProfileType === 'eleveur' || PRO_TYPES.has(resolvedProfileType))
    : userData?.isElevage === true;
  const effectiveIsPension = resolvedProfileType
    ? resolvedProfileType === 'pension'
    : (userData?.isPro === true && userData?.catPro === 'pension');
  // Détection pro primaire (userData.isPro = true, aucun profil secondaire actif)
  const isPrimaryPro = !resolvedProfileType && userData?.isPro === true;
  const primaryCatPro = userData?.catPro ?? '';

  const effectiveIsVet = !!(resolvedProfileType === 'veterinaire' || resolvedProfileType === 'sante' ||
    activeProfile?.cat_pro === 'veterinaire' || activeProfile?.cat_pro === 'sante'
  ) || (isPrimaryPro && (primaryCatPro === 'veterinaire' || primaryCatPro === 'sante'));

  const primaryDisplayName = userData?.nameElevage ?? userData?.firstname ?? user?.email ?? '';
  const primaryAvatar = userData?.profilePictureUrlElevage ?? userData?.profilePictureUrl ?? null;

  const effectiveDisplayName = activeProfile
    ? (activeProfile.nom ?? activeProfile.profile_label ?? activeProfile.name_elevage ?? primaryDisplayName)
    : primaryDisplayName;
  const effectiveAvatar = activeProfile?.avatar_url ?? primaryAvatar;

  const effectiveIsPro = activeProfile
    ? PRO_TYPES.has(activeProfile.profile_type)
    : userData?.isPro === true;

  // Tout profil pro actif (secondaire ou primaire)
  const isSecondaryPro = !!(activeProfile && PRO_TYPES.has(activeProfile.profile_type));
  const isEffectivelyPro = isSecondaryPro || isPrimaryPro;
  const navLinks = loading || !user ? NAV_GUEST
    : isEffectivelyPro ? (effectiveIsVet ? NAV_VET : NAV_PRO)
    : effectiveIsAssociation ? NAV_ASSOCIATION
    : effectiveIsEleveur ? NAV_ELEVEUR
    : NAV_PARTICULIER;
  const baseMenuParticulier = isFa
    ? MENU_PARTICULIER.map(sec => sec.section === 'Mon Profil'
        ? { ...sec, items: [...sec.items, { href: '/mes-animaux-accueil', label: 'Animaux en accueil', icon: '🏡' }] }
        : sec)
    : MENU_PARTICULIER;
  const baseMenuSections = isEffectivelyPro
    ? (effectiveIsPension ? MENU_PENSION : effectiveIsVet ? MENU_VET : MENU_PRO)
    : effectiveIsAssociation ? MENU_ASSOCIATION
    : effectiveIsEleveur ? MENU_ELEVEUR
    : baseMenuParticulier;
  const menuSections = (isEmploye || isBenevole)
    ? baseMenuSections.map((sec, i) => i === 0
        ? {
            ...sec,
            items: [
              ...sec.items,
              ...(isEmploye ? [{ href: '/mes-employeurs', label: 'Mes employeurs', icon: '🏡' }] : []),
              ...(isBenevole ? [{ href: '/mes-associations', label: 'Mes associations', icon: '🏠' }] : []),
            ],
          }
        : sec)
    : baseMenuSections;

  // ── Détection famille d'accueil & employé/bénévole ───────────────────────
  useEffect(() => {
    if (!user) { setIsFa(false); setIsEmploye(false); return; }
    supabase.from('familles_accueil').select('id').eq('fa_uid', user.uid).eq('actif', true).limit(1)
      .then(({ data }) => setIsFa((data ?? []).length > 0));
    supabase.from('employes').select('id, type').eq('uid_employe', user.uid).eq('actif', true)
      .then(({ data }) => {
        const rows = data ?? [];
        setIsEmploye(rows.some((r: { type: string | null }) => r.type !== 'benevole'));
        setIsBenevole(rows.some((r: { type: string | null }) => r.type === 'benevole'));
      });
  }, [user]);


  function switchProfile(id: string | null) {
    const newId = id ?? '';
    const targetProfile = profiles.find(p => p.id === newId) ?? profiles.find(p => p.is_main);
    const targetType = targetProfile?.profile_type ?? null;
    const finalId = newId || (targetProfile?.id ?? '');

    // Écriture localStorage en premier — garantit le changement même si AuthContext
    // n'a pas encore chargé availableProfiles (race condition sur pages hors accueil)
    if (finalId) {
      localStorage.setItem(ACTIVE_PROFILE_KEY, finalId);
      if (targetProfile?.profile_type) {
        localStorage.setItem(ACTIVE_PROFILE_TYPE_KEY, targetProfile.profile_type);
      }
      window.dispatchEvent(new Event(PROFILE_CHANGE_EVENT));
    } else {
      localStorage.removeItem(ACTIVE_PROFILE_KEY);
      localStorage.removeItem(ACTIVE_PROFILE_TYPE_KEY);
    }

    authSetActiveId(finalId || null);
    setProfileSwitcherOpen(false);
    setDropdownOpen(false);
    setMenuOpen(false);

    // Hard reload vers la bonne section — garantit un état propre
    const dest = targetType === 'association' ? '/association' : '/';
    window.location.href = dest;
  }

  // ── Messages non lus (Supabase) ───────────────────────────────────────────
  useEffect(() => {
    if (!user) return;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    async function fetchUnread() {
      const { data } = await supabase
        .from('conversations')
        .select('unread_count')
        .filter('participants', 'cs', `["${user!.uid}"]`);
      if (!data) return;
      const total = (data as { unread_count: Record<string, number> | null }[])
        .reduce((s, c) => s + (c.unread_count?.[user!.uid] ?? 0), 0);
      setUnreadMessages(total);
    }

    fetchUnread();

    channel = supabase
      .channel(`header_convs_${user.uid}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'conversations' }, () => fetchUnread())
      .subscribe();

    return () => { channel?.unsubscribe(); };
  }, [user]);

  // ── Notifications ─────────────────────────────────────────────────────────
  useEffect(() => {
    if (!user) return;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    // Via API route (service role) pour contourner les RLS avec Firebase Auth
    const fetchNotifs = async () => {
      const res = await fetch(`/api/notifications?uid=${encodeURIComponent(user.uid)}`);
      if (res.ok) setNotifs(await res.json() as Notif[]);
    };

    fetchNotifs();

    // Realtime Supabase : déclenche un re-fetch via l'API à chaque changement
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
    setNotifs([]); // optimistic
    await fetch('/api/notifications', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ uid: user.uid }),
    });
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
    localStorage.removeItem(ACTIVE_PROFILE_KEY);
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

  // ── Profile switcher panel (shared desktop + mobile) ─────────────────────
  function ProfileSwitcherPanel({ onClose }: { onClose: () => void }) {
    return (
      <div className="bg-[#F8F8F8] rounded-xl mx-2 mb-2 overflow-hidden">
        <div className="px-4 py-2.5 flex items-center justify-between border-b border-gray-200">
          <span className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide">Mes profils</span>
          <button onClick={() => setProfileSwitcherOpen(false)} className="text-gray-400 hover:text-gray-600 text-sm">
            ✕
          </button>
        </div>

        {/* Liste plate de tous les profils */}
        {profiles.map(p => {
          const isActive = activeProfileId === p.id || (!activeProfileId && p.is_main);
          const displayName = p.nom ?? p.profile_label ?? typeLabel(p.profile_type);
          return (
            <button
              key={p.id}
              onClick={() => { switchProfile(p.id); onClose(); }}
              className={`w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white transition-colors text-left ${isActive ? 'bg-white' : ''}`}>
              <div className="w-8 h-8 rounded-full overflow-hidden bg-[#DCE8D5] flex items-center justify-center flex-shrink-0 relative">
                {p.avatar_url ? (
                  <Image src={p.avatar_url} alt="" width={32} height={32} className="object-cover w-full h-full" />
                ) : (
                  <span className="text-[#6E9E57] text-sm">{typeEmoji(p.profile_type)}</span>
                )}
                {isActive && (
                  <span className="absolute -bottom-0.5 -right-0.5 w-3.5 h-3.5 bg-[#6E9E57] rounded-full border-2 border-white flex items-center justify-center">
                    <span className="text-white text-[8px]">✓</span>
                  </span>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-1.5">
                  <p className={`text-sm truncate ${isActive ? 'font-bold text-[#1F2A2E]' : 'font-medium text-gray-700'}`}>
                    {displayName}
                  </p>
                  {p.is_main && (
                    <span className="text-[10px] bg-[#EEF5EA] text-[#6E9E57] px-1.5 py-0.5 rounded-full font-semibold flex-shrink-0">
                      Principal
                    </span>
                  )}
                </div>
                <p className="text-xs text-gray-400">{typeEmoji(p.profile_type)} {typeLabel(p.profile_type)}</p>
              </div>
            </button>
          );
        })}

        {/* Ajouter un profil */}
        <Link href="/profil/ajouter"
          onClick={() => { setDropdownOpen(false); setMenuOpen(false); }}
          className="flex items-center gap-3 px-4 py-2.5 border-t border-gray-200 text-[#6E9E57] hover:bg-[#EEF5EA] transition-colors">
          <span className="w-8 h-8 rounded-full bg-[#EEF5EA] flex items-center justify-center text-sm flex-shrink-0">＋</span>
          <span className="text-sm font-semibold">Ajouter un profil</span>
        </Link>
      </div>
    );
  }

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
                onClick={() => setBellOpen(!bellOpen)}
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
                    {notifs.map(n => {
                      const notifProfileType = (n as Notif & { profile_type?: string }).profile_type;
                      const isDifferentProfile = notifProfileType && notifProfileType !== effectiveType;
                      const dest = getNotifUrl(n);
                      const isExternal = dest?.startsWith('http') ?? false;
                      const isActionable = isDifferentProfile || n.type === 'pension_acces' || !!dest;

                      const handleClick = async () => {
                        if (isDifferentProfile) {
                          setBellOpen(false);
                          const matchedProfile = profiles.find(p => p.profile_type === notifProfileType);
                          switchProfile(matchedProfile?.id ?? null);
                          return;
                        }
                        // Marquer comme lu + retirer de la liste
                        setNotifs(prev => prev.filter(x => x.id !== n.id));
                        supabase.from('notifications').update({ read: true }).eq('id', n.id).then(() => {});
                        setBellOpen(false);
                        if (n.type === 'pension_acces') { setPensionDialog(n); return; }
                        if (!dest) return;
                        if (isExternal) window.open(dest, '_blank', 'noopener noreferrer');
                        else router.push(dest);
                      };

                      return (
                        <div key={n.id}
                          className={`flex items-start gap-3 px-4 py-3 hover:bg-gray-50 border-b border-gray-50 ${isActionable ? 'cursor-pointer' : ''}`}
                          onClick={handleClick}>
                          <div className="w-9 h-9 rounded-full bg-amber-50 flex items-center justify-center text-lg flex-shrink-0">
                            {n.type === 'alerte_perdu' ? '🔍'
                              : n.type === 'like' ? '❤️'
                              : n.type === 'chaleur' ? '🌸'
                              : n.type === 'rappel_vaccin' ? '💉'
                              : n.type === 'pension_acces' || n.type === 'pension_acces_reponse' ? '🏡'
                              : n.type === 'contrat_saillie_invite' ? '💞'
                              : n.type === 'contrat_signe_complet' ? '✅'
                              : n.type === 'contrat_signe_acquereur' || n.type === 'contrat_signe_eleveur' ? '✍️'
                              : n.type === 'contrat_refuse' ? '❌'
                              : n.type === 'contrat_expire' ? '⏰'
                              : n.type?.startsWith('contrat') || n.type?.startsWith('certificat') ? '📄'
                              : n.type === 'cession_signature_demandee' ? '✍️'
                              : n.type === 'cession_confirmee' || n.type === 'cession_animal' ? '🐾'
                              : n.type === 'cession_signee_acquereur' || n.type === 'cession_signe_acquereur' ? '🔔'
                              : n.type?.startsWith('cession') ? '🤝'
                              : n.type === 'rdv_confirme' ? '✅'
                              : n.type === 'rdv_refuse' || n.type?.includes('annule') ? '❌'
                              : n.type?.startsWith('rdv') ? '📅'
                              : n.type === 'employee_invite' ? '🤝'
                              : n.type === 'tache' ? '✅'
                              : n.type === 'profil_valide' ? '✅'
                              : n.type === 'profil_en_attente' ? '⏳'
                              : n.type === 'sante_vet' ? '🏥'
                              : n.type === 'annonce_expiration' ? '⚠️'
                              : '🔔'}
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-semibold text-[#1F2A2E]">{n.title}</p>
                            <p className="text-xs text-gray-500 line-clamp-2">{n.body}</p>
                            <div className="flex items-center gap-2 mt-1">
                              {notifProfileType && (
                                <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded-full ${isDifferentProfile ? 'bg-[#0C5C6C]/10 text-[#0C5C6C]' : 'bg-gray-100 text-gray-500'}`}>
                                  {typeEmoji(notifProfileType)} {typeLabel(notifProfileType)}
                                </span>
                              )}
                              {isDifferentProfile
                                ? <span className="text-[10px] text-[#0C5C6C] font-medium">↗ Basculer</span>
                                : isActionable && <span className="text-[10px] text-gray-400 ml-auto">→</span>}
                            </div>
                          </div>
                        </div>
                      );
                    })}
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
                <div className="w-7 h-7 rounded-full overflow-hidden bg-[#6E9E57] flex items-center justify-center flex-shrink-0 relative">
                  {effectiveAvatar ? (
                    <Image src={effectiveAvatar} alt="" width={28} height={28} className="object-cover w-full h-full" />
                  ) : (
                    <span className="text-white text-xs font-bold">{(effectiveDisplayName[0] ?? '?').toUpperCase()}</span>
                  )}
                  {/* Indicateur profil secondaire actif */}
                  {activeProfileId && (
                    <span className="absolute -bottom-0.5 -right-0.5 w-3 h-3 bg-[#6E9E57] rounded-full border border-white" />
                  )}
                </div>
                <span className="text-white text-sm font-medium truncate max-w-[100px]">{effectiveDisplayName}</span>
                <svg className={`w-4 h-4 text-white/70 transition-transform ${dropdownOpen ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              </button>

              {dropdownOpen && (
                <div className="absolute right-0 top-full mt-2 w-72 bg-white rounded-2xl shadow-xl border border-gray-100 overflow-hidden">
                  {/* Header */}
                  <div className="bg-[#0C5C6C] px-4 py-3 flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full overflow-hidden bg-[#6E9E57] flex items-center justify-center flex-shrink-0">
                      {effectiveAvatar ? (
                        <Image src={effectiveAvatar} alt="" width={40} height={40} className="object-cover w-full h-full" />
                      ) : (
                        <span className="text-white text-sm font-bold">{(effectiveDisplayName[0] ?? '?').toUpperCase()}</span>
                      )}
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="text-white font-semibold text-sm truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{effectiveDisplayName}</p>
                      <p className="text-white/60 text-xs">{typeEmoji(effectiveType)} {typeLabel(effectiveType)}</p>
                    </div>
                    {/* Bouton changer de profil */}
                    <button
                      onClick={() => setProfileSwitcherOpen(!profileSwitcherOpen)}
                      title="Changer de profil"
                      className="text-white/70 hover:text-white text-xs font-medium bg-white/10 hover:bg-white/20 rounded-full px-2 py-1 transition-colors flex-shrink-0">
                      ⇄
                    </button>
                  </div>

                  {/* Panel sélecteur de profil */}
                  {profileSwitcherOpen && (
                    <ProfileSwitcherPanel onClose={() => setProfileSwitcherOpen(false)} />
                  )}

                  {/* Sections menu */}
                  <div className="py-1 max-h-80 overflow-y-auto">
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
                            {sec.items.map((item) => {
                              const it = item as { pro?: boolean; premium?: boolean; href: string; icon: string; label: string };
                              const isProLocked = (effectiveIsEleveur && it.pro && eleveurPlan === 'free')
                                || (effectiveIsPension && it.pro && pensionPlan === 'free');
                              const isPremiumLocked = effectiveIsEleveur && it.premium && eleveurPlan !== 'premium';
                              const isLocked = isProLocked || isPremiumLocked;
                              const badge = isPremiumLocked ? 'Premium' : 'Pro';
                              const badgeCls = isPremiumLocked
                                ? 'text-[10px] font-bold bg-amber-100 text-amber-600 px-1.5 py-0.5 rounded-full mr-1'
                                : 'text-[10px] font-bold bg-amber-100 text-amber-600 px-1.5 py-0.5 rounded-full mr-1';
                              return isLocked ? (
                                <Link key={it.href} href={effectiveIsPension ? '/pension/abonnement' : '/abonnement'}
                                  onClick={() => setDropdownOpen(false)}
                                  className="flex items-center gap-3 pl-10 pr-4 py-2 text-sm text-gray-400 hover:bg-gray-50 transition-colors">
                                  <span className="text-base opacity-50">{it.icon}</span>
                                  <span className="flex-1 opacity-60">{it.label}</span>
                                  <span className={badgeCls}>{badge}</span>
                                </Link>
                              ) : (
                                <Link key={it.href} href={it.href}
                                  onClick={() => setDropdownOpen(false)}
                                  className="flex items-center gap-3 pl-10 pr-4 py-2 text-sm text-gray-600 hover:bg-gray-100 transition-colors">
                                  <span className="text-base">{it.icon}</span>
                                  {it.label}
                                </Link>
                              );
                            })}
                          </div>
                        )}
                      </div>
                    ))}

                    <div className="border-t border-gray-100 mt-1">
                      <Link href="/profil" onClick={() => setDropdownOpen(false)}
                        className="flex items-center gap-3 px-4 py-2.5 text-sm text-gray-700 hover:bg-gray-50 transition-colors">
                        <span>⚙️</span> Mon Profil
                      </Link>
                      {!effectiveIsEleveur && (
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
              {/* Profile summary + switcher */}
              <div className="bg-white/10 rounded-xl mb-3 overflow-hidden">
                <div className="flex items-center gap-3 px-4 py-3">
                  <div className="w-9 h-9 rounded-full overflow-hidden bg-[#6E9E57] flex items-center justify-center flex-shrink-0">
                    {effectiveAvatar ? (
                      <Image src={effectiveAvatar} alt="" width={36} height={36} className="object-cover w-full h-full" />
                    ) : (
                      <span className="text-white text-xs font-bold">{(effectiveDisplayName[0] ?? '?').toUpperCase()}</span>
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-white text-sm font-semibold truncate">{effectiveDisplayName}</p>
                    <p className="text-white/50 text-xs">{typeEmoji(effectiveType)} {typeLabel(effectiveType)}</p>
                  </div>
                  <button
                    onClick={() => setProfileSwitcherOpen(!profileSwitcherOpen)}
                    className="text-white/70 hover:text-white text-xs font-bold bg-white/10 hover:bg-white/20 rounded-full px-2.5 py-1 transition-colors">
                    ⇄
                  </button>
                </div>
                {profileSwitcherOpen && (
                  <div className="border-t border-white/10">
                    <ProfileSwitcherPanel onClose={() => setProfileSwitcherOpen(false)} />
                  </div>
                )}
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
                      {sec.items.map((item) => {
                        const it = item as { pro?: boolean; premium?: boolean; href: string; icon: string; label: string };
                        const isProLocked = (effectiveIsEleveur && it.pro && eleveurPlan === 'free')
                          || (effectiveIsPension && it.pro && pensionPlan === 'free');
                        const isPremiumLocked = effectiveIsEleveur && it.premium && eleveurPlan !== 'premium';
                        const isLocked = isProLocked || isPremiumLocked;
                        const badge = isPremiumLocked ? 'Premium' : 'Pro';
                        return isLocked ? (
                          <Link key={it.href} href={effectiveIsPension ? '/pension/abonnement' : '/abonnement'} onClick={() => setMenuOpen(false)}
                            className="flex items-center gap-2 py-2 text-white/40 text-sm">
                            <span className="opacity-50">{it.icon}</span>
                            <span className="flex-1 opacity-60">{it.label}</span>
                            <span className="text-[10px] font-bold bg-amber-500/20 text-amber-300 px-1.5 py-0.5 rounded-full">{badge}</span>
                          </Link>
                        ) : (
                          <Link key={it.href} href={it.href} onClick={() => setMenuOpen(false)}
                            className="flex items-center gap-2 py-2 text-white/70 hover:text-white text-sm">
                            <span>{it.icon}</span> {it.label}
                          </Link>
                        );
                      })}
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
