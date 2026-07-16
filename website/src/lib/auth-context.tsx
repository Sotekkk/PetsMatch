'use client';

import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
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

// Doit rester synchro avec _profileTypes (app: add_profile_page.dart),
// seule source de vérité des profile_type réellement enregistrés en base.
const PRO_TYPES = new Set([
  'veterinaire', 'sante', 'education', 'garde',
  'pension', 'toilettage', 'photographe', 'marechal_ferrant',
  'restauration', 'taxi_animalier',
]);

// Supabase user_profiles snake_case → web camelCase.
// `fallback` = ligne users (source primaire, historique) — utilisée quand la
// colonne équivalente sur user_profiles est vide (jamais synchronisée) ou
// vaut le placeholder "0000000000" laissé par d'anciens flux de création.
// Même logique de repli que l'app (main.dart::applyProfile), qui affiche
// correctement ces infos alors que le web (sans ce repli) les montrait vides.
function mapProfile(d: Record<string, unknown>, fallback?: Record<string, unknown> | null): UserData {
  const type = (d.profile_type as string | undefined) ?? '';
  const f = fallback ?? {};
  const pick = (profileVal: unknown, fallbackVal: unknown): string | undefined => {
    const p = (profileVal as string | undefined)?.trim();
    if (p && p.length > 0) return p;
    const fb = (fallbackVal as string | undefined)?.trim();
    return fb && fb.length > 0 ? fb : undefined;
  };
  const pickPhone = (profileVal: unknown, fallbackVal: unknown): string | undefined => {
    const p = (profileVal as string | undefined)?.trim();
    if (p && p.length > 0 && p !== '0000000000') return p;
    const fb = (fallbackVal as string | undefined)?.trim();
    return fb && fb.length > 0 ? fb : (p || undefined);
  };

  // especes_elevees peut être stocké soit en objets {espece, races} (éleveur),
  // soit en simples chaînes ["chien", "chat"] (autres profils pro) — on normalise.
  const especesEleveesRaw = (d.especes_elevees as unknown[] | undefined) ?? [];
  const especesElevees = especesEleveesRaw
    .map(e => typeof e === 'string' ? { espece: e, races: [] as string[] } : e as { espece?: string; races?: string[] })
    .filter((e): e is { espece: string; races?: string[] } => typeof e?.espece === 'string' && e.espece.length > 0);
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
    profilePictureUrl:     pick(d.avatar_url, f.profile_picture_url),
    profilePictureUrlElevage: pick(d.profile_picture_url_pro, f.profile_picture_url_elevage) ?? pick(d.avatar_url, f.profile_picture_url),
    descriptionElevage:    pick(d.description, pick(d.desc_entreprise, f.bio)),
    descEntreprise:        pick(d.description, pick(d.desc_entreprise, f.bio)),
    phone:                 pickPhone(d.phone_number, f.phone_number),
    siret:                 pick(d.siret, f.siret),
    numeroElevage:         pick(d.numero_elevage, f.numero_elevage),
    isDog:                 d.is_dog as boolean | undefined,
    isCat:                 d.is_cat as boolean | undefined,
    dogBreeds,
    catBreeds,
    especesElevees,
    lat:                   d.lat as number | undefined,
    lng:                   d.lng as number | undefined,
    bannerUrl:             pick(d.banner_url, f.banner_url),
    acacedDateObtention:   d.acaced_date_obtention as string | undefined,
    acacedDateRenewal:     d.acaced_date_renewal as string | undefined,
    acaced:                d.acaced as string | undefined,
    statutPro:             d.statut_pro as string | undefined,
    rejectionReason:       d.rejection_reason as string | undefined,
    cguAcceptedAt:         d.cgu_accepted_at as string | undefined,
    isPremium:             d.is_premium as boolean | undefined,
    kbisUrl:               d.kbis_url as string | undefined,
    acacedDocUrl:          d.diplome_url as string | undefined,
    instagram:             pick(d.instagram, f.instagram),
    facebook:              pick(d.facebook, f.facebook),
    siteWeb:               pick(d.site_web, f.site_web),
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
  // Ligne `users` complète (source primaire, historique) — sert de repli pour
  // les champs jamais synchronisés vers user_profiles (bio, banner_url,
  // phone_number...). Ref pour éviter les closures périmées dans fetchProfiles.
  const cachedUserRowRef = useRef<Record<string, unknown> | null>(null);

  const fetchProfiles = useCallback(async (uid: string) => {
    try {
      const [profilesRes, userRes] = await Promise.all([
        supabase.from('user_profiles').select('*').eq('uid', uid)
          .order('is_main', { ascending: false })
          .order('created_at', { ascending: true }),
        supabase.from('users')
          .select('cgu_accepted_at, bio, banner_url, phone_number, siret, instagram, facebook, site_web, numero_elevage, profile_picture_url, profile_picture_url_elevage')
          .eq('uid', uid).maybeSingle(),
      ]);

      const profiles = (profilesRes.data ?? []) as Profile[];
      const userRow = (userRes.data as Record<string, unknown> | null) ?? null;
      cachedUserRowRef.current = userRow;
      const cguAcceptedAt = (userRow?.cgu_accepted_at as string | undefined) ?? null;

      setAvailableProfiles(profiles);

      if (profiles.length === 0) { setUserData(null); return; }

      const mainProfile = profiles.find(p => p.is_main) ?? profiles[0];
      const storedId = localStorage.getItem(ACTIVE_PROFILE_KEY) ?? '';
      const active = profiles.find(p => p.id === storedId) ?? mainProfile;

      localStorage.setItem(ACTIVE_PROFILE_KEY, active.id);
      localStorage.setItem(ACTIVE_PROFILE_TYPE_KEY, active.profile_type ?? '');
      window.dispatchEvent(new Event(PROFILE_CHANGE_EVENT));
      setActiveProfileIdState(active.id);
      setUserData(mapProfile({ ...(active as unknown as Record<string, unknown>), cgu_accepted_at: cguAcceptedAt }, userRow));
    } catch {
      setUserData(null);
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const setActiveProfileId = useCallback((id: string) => {
    setAvailableProfiles(prev => {
      const profile = prev.find(p => p.id === id);
      localStorage.setItem(ACTIVE_PROFILE_KEY, id);
      localStorage.setItem(ACTIVE_PROFILE_TYPE_KEY, profile?.profile_type ?? '');
      window.dispatchEvent(new Event(PROFILE_CHANGE_EVENT));
      setActiveProfileIdState(id);
      if (profile) setUserData(mapProfile({ ...(profile as unknown as Record<string, unknown>), cgu_accepted_at: cachedUserRowRef.current?.cgu_accepted_at }, cachedUserRowRef.current));
      return prev;
    });
  }, []);

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
  }, [fetchProfiles]);

  const refreshUserData = useCallback(async () => {
    if (user) await fetchProfiles(user.uid);
  }, [user, fetchProfiles]);

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
