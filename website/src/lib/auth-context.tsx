'use client';

import { createContext, useContext, useEffect, useState } from 'react';
import { onAuthStateChanged, User } from 'firebase/auth';
import { auth } from './firebase';
import { supabase } from './supabase';
import { ACTIVE_PROFILE_KEY, ACTIVE_PROFILE_TYPE_KEY, PROFILE_CHANGE_EVENT } from '@/hooks/useActiveProfile';

export interface UserData {
  firstname?: string;
  lastname?: string;
  isElevage?: boolean;
  isAssociation?: boolean;
  isPro?: boolean;
  profileType?: string;
  rna?: string;
  isValidate?: boolean;
  catPro?: string;
  nameElevage?: string;
  ville?: string;
  codePostal?: string;
  departement?: string;
  region?: string;
  dob?: string;
  villeElevage?: string;
  codePostalElevage?: string;
  paysElevage?: string;
  adressElevage?: string;
  rueElevage?: string;
  especes?: string[];
  races?: string[];
  descriptionElevage?: string;
  descEntreprise?: string;
  profilePictureUrl?: string;
  profilePictureUrlElevage?: string;
  phone?: string;
  siret?: string;
  numeroElevage?: string;
  isDog?: boolean;
  isCat?: boolean;
  dogBreeds?: string[];
  catBreeds?: string[];
  especesElevees?: { espece: string; races?: string[] }[];
  lat?: number;
  lng?: number;
  bannerUrl?: string;
  acacedDateObtention?: string;
  acacedDateRenewal?: string;
  acaced?: string;
  statutPro?: string;
  rejectionReason?: string;
  cguAcceptedAt?: string;
  isPremium?: boolean;
  kbisUrl?: string;
  acacedDocUrl?: string;
  instagram?: string;
  facebook?: string;
  siteWeb?: string;
  numeroTva?: string;
}

export interface Profile {
  id: string;
  uid: string;
  profile_type: string | null;
  is_main: boolean;
  nom: string | null;
  firstname: string | null;
  lastname: string | null;
  avatar_url: string | null;
  profile_picture_url_pro: string | null;
  statut_pro: string | null;
  is_validate: boolean | null;
  ville: string | null;
  ville_pro: string | null;
  [key: string]: unknown;
}

const PRO_TYPES = new Set([
  'veterinaire', 'para_medical', 'education', 'petsitter',
  'pension', 'promeneur', 'photographe', 'marechal_ferrant',
]);

// Supabase user_profiles snake_case → web camelCase
function mapProfile(d: Record<string, unknown>): UserData {
  const type = (d.profile_type as string | undefined) ?? '';

  const especesElevees = (d.especes_elevees as { espece: string; races?: string[] }[] | undefined) ?? [];
  const dogBreeds = (d.dog_breeds as string[] | undefined) ?? [];
  const catBreeds = (d.cat_breeds as string[] | undefined) ?? [];

  const especes = especesElevees.length > 0
    ? especesElevees.map(e => e.espece.charAt(0).toUpperCase() + e.espece.slice(1))
    : [
        ...(d.is_dog ? ['Chien'] : []),
        ...(d.is_cat ? ['Chat'] : []),
      ];
  const races = especesElevees.length > 0
    ? [...new Set(especesElevees.flatMap(e => e.races ?? []))]
    : [...new Set([...dogBreeds, ...catBreeds])];

  // nom = colonne renommée depuis name_elevage en V2
  const nameElevage = (d.nom as string | undefined)
    ?? (d.name_elevage as string | undefined);

  // Adresse perso
  const ville      = (d.ville as string | undefined);
  const codePostal = (d.code_postal as string | undefined);
  // Adresse pro (suffixe _pro ajouté en V2)
  const villePro      = (d.ville_pro as string | undefined) ?? ville;
  const codePostalPro = (d.code_postal_pro as string | undefined) ?? codePostal;

  return {
    firstname:             d.firstname as string | undefined,
    lastname:              d.lastname as string | undefined,
    profileType:           type || undefined,
    isElevage:             type === 'eleveur',
    isAssociation:         type === 'association',
    isPro:                 PRO_TYPES.has(type),
    rna:                   d.rna as string | undefined,
    isValidate:            d.is_validate as boolean | undefined,
    catPro:                d.cat_pro as string | undefined ?? (PRO_TYPES.has(type) ? type : undefined),
    nameElevage,
    ville,
    codePostal,
    departement:           d.departement as string | undefined,
    region:                d.region as string | undefined,
    dob:                   d.date_of_birth as string | undefined,
    villeElevage:          villePro,
    codePostalElevage:     codePostalPro,
    paysElevage:           (d.pays_pro as string | undefined) ?? (d.pays as string | undefined),
    adressElevage:         (d.rue_pro as string | undefined) ?? (d.rue as string | undefined),
    rueElevage:            (d.rue_pro as string | undefined) ?? (d.rue as string | undefined),
    profilePictureUrl:     (d.avatar_url as string | undefined),
    profilePictureUrlElevage: (d.profile_picture_url_pro as string | undefined) ?? (d.avatar_url as string | undefined),
    descriptionElevage:    d.description as string | undefined,
    descEntreprise:        d.description as string | undefined,
    phone:                 d.phone_number as string | undefined,
    siret:                 d.siret as string | undefined,
    numeroElevage:         d.numero_elevage as string | undefined,
    isDog:                 d.is_dog as boolean | undefined,
    isCat:                 d.is_cat as boolean | undefined,
    dogBreeds,
    catBreeds,
    especesElevees,
    lat:                   d.lat as number | undefined,
    lng:                   d.lng as number | undefined,
    bannerUrl:             d.banner_url as string | undefined,
    acacedDateObtention:   d.acaced_date_obtention as string | undefined,
    acacedDateRenewal:     d.acaced_date_renewal as string | undefined,
    acaced:                d.acaced as string | undefined,
    statutPro:             d.statut_pro as string | undefined,
    rejectionReason:       d.rejection_reason as string | undefined,
    cguAcceptedAt:         d.cgu_accepted_at as string | undefined,
    isPremium:             d.is_premium as boolean | undefined,
    kbisUrl:               d.kbis_url as string | undefined,
    acacedDocUrl:          d.diplome_url as string | undefined,
    instagram:             d.instagram   as string | undefined,
    facebook:              d.facebook    as string | undefined,
    siteWeb:               d.site_web    as string | undefined,
    numeroTva:             d.numero_tva  as string | undefined,
    especes,
    races,
  };
}

interface AuthContextType {
  user: User | null;
  userData: UserData | null;
  loading: boolean;
  availableProfiles: Profile[];
  activeProfileId: string;
  setActiveProfileId: (id: string) => void;
  refreshUserData: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  user: null,
  userData: null,
  loading: true,
  availableProfiles: [],
  activeProfileId: '',
  setActiveProfileId: () => {},
  refreshUserData: async () => {},
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [userData, setUserData] = useState<UserData | null>(null);
  const [availableProfiles, setAvailableProfiles] = useState<Profile[]>([]);
  const [activeProfileId, setActiveProfileIdState] = useState<string>('');
  const [loading, setLoading] = useState(true);
  // cgu_accepted_at est dans `users`, pas dans user_profiles — on le cache au premier fetch
  const [cachedCguAcceptedAt, setCachedCguAcceptedAt] = useState<string | null>(null);

  function setActiveProfileId(id: string) {
    const profile = availableProfiles.find(p => p.id === id);
    localStorage.setItem(ACTIVE_PROFILE_KEY, id);
    localStorage.setItem(ACTIVE_PROFILE_TYPE_KEY, profile?.profile_type ?? '');
    window.dispatchEvent(new Event(PROFILE_CHANGE_EVENT));
    setActiveProfileIdState(id);
    if (profile) setUserData(mapProfile({ ...(profile as unknown as Record<string, unknown>), cgu_accepted_at: cachedCguAcceptedAt }));
  }

  async function fetchProfiles(uid: string) {
    try {
      const [profilesRes, userRes] = await Promise.all([
        supabase.from('user_profiles').select('*').eq('uid', uid)
          .order('is_main', { ascending: false })
          .order('created_at', { ascending: true }),
        supabase.from('users').select('cgu_accepted_at').eq('uid', uid).maybeSingle(),
      ]);

      const profiles = (profilesRes.data ?? []) as Profile[];
      const cguAcceptedAt = (userRes.data as { cgu_accepted_at?: string } | null)?.cgu_accepted_at ?? null;
      setCachedCguAcceptedAt(cguAcceptedAt);

      setAvailableProfiles(profiles);

      if (profiles.length === 0) { setUserData(null); return; }

      const mainProfile = profiles.find(p => p.is_main) ?? profiles[0];
      const storedId = localStorage.getItem(ACTIVE_PROFILE_KEY) ?? '';
      const active = profiles.find(p => p.id === storedId) ?? mainProfile;

      localStorage.setItem(ACTIVE_PROFILE_KEY, active.id);
      localStorage.setItem(ACTIVE_PROFILE_TYPE_KEY, active.profile_type ?? '');
      window.dispatchEvent(new Event(PROFILE_CHANGE_EVENT));
      setActiveProfileIdState(active.id);
      setUserData(mapProfile({ ...(active as unknown as Record<string, unknown>), cgu_accepted_at: cguAcceptedAt }));
    } catch {
      setUserData(null);
    }
  }

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (u) => {
      setUser(u);
      if (u) {
        await fetchProfiles(u.uid);
      } else {
        setUserData(null);
        setAvailableProfiles([]);
        setActiveProfileIdState('');
        localStorage.removeItem(ACTIVE_PROFILE_KEY);
        localStorage.removeItem(ACTIVE_PROFILE_TYPE_KEY);
      }
      setLoading(false);
    });
    return unsub;
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  async function refreshUserData() {
    if (user) await fetchProfiles(user.uid);
  }

  return (
    <AuthContext.Provider value={{
      user, userData, loading,
      availableProfiles, activeProfileId, setActiveProfileId,
      refreshUserData,
    }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);
