'use client';

import { createContext, useContext, useEffect, useState } from 'react';
import { onAuthStateChanged, User } from 'firebase/auth';
import { auth } from './firebase';
import { supabase } from './supabase';

export interface UserData {
  firstname?: string;
  lastname?: string;
  isElevage?: boolean;
  isAssociation?: boolean;
  rna?: string;
  isValidate?: boolean;
  isPro?: boolean;
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
}

// Supabase snake_case → web camelCase
function mapUser(d: Record<string, unknown>): UserData {
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

  return {
    firstname:             d.firstname as string | undefined,
    lastname:              d.lastname as string | undefined,
    isElevage:             d.is_elevage as boolean | undefined,
    isAssociation:         d.is_association as boolean | undefined,
    rna:                   d.rna as string | undefined,
    isValidate:            d.is_validate as boolean | undefined,
    isPro:                 d.is_pro as boolean | undefined,
    catPro:                d.cat_pro as string | undefined,
    nameElevage:           d.name_elevage as string | undefined,
    ville:                 d.ville as string | undefined,
    codePostal:            d.code_postal as string | undefined,
    departement:           d.departement as string | undefined,
    region:                d.region as string | undefined,
    dob:                   d.date_of_birth as string | undefined,
    villeElevage:          d.ville_elevage as string | undefined,
    codePostalElevage:     d.code_postal_elevage as string | undefined,
    paysElevage:           d.pays_elevage as string | undefined,
    adressElevage:         d.adress_elevage as string | undefined,
    rueElevage:            d.rue_elevage as string | undefined,
    profilePictureUrl:     d.profile_picture_url as string | undefined,
    profilePictureUrlElevage: d.profile_picture_url_elevage as string | undefined,
    descriptionElevage:    d.desc_entreprise as string | undefined,
    descEntreprise:        d.desc_entreprise as string | undefined,
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
    acacedDocUrl:          d.acaced_doc_url as string | undefined,
    especes,
    races,
  };
}

interface AuthContextType {
  user: User | null;
  userData: UserData | null;
  loading: boolean;
  refreshUserData: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  user: null,
  userData: null,
  loading: true,
  refreshUserData: async () => {},
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [userData, setUserData] = useState<UserData | null>(null);
  const [loading, setLoading] = useState(true);

  async function fetchUserData(uid: string) {
    try {
      const { data } = await supabase
        .from('users')
        .select('*')
        .eq('uid', uid)
        .single();
      setUserData(data ? mapUser(data as Record<string, unknown>) : null);
    } catch {
      setUserData(null);
    }
  }

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (u) => {
      setUser(u);
      if (u) {
        await fetchUserData(u.uid);
      } else {
        setUserData(null);
      }
      setLoading(false);
    });
    return unsub;
  }, []);

  async function refreshUserData() {
    if (user) await fetchUserData(user.uid);
  }

  return (
    <AuthContext.Provider value={{ user, userData, loading, refreshUserData }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);
