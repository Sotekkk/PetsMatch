'use client';

// Espace employé d'une clinique vétérinaire : la clinique où l'on est employé
// est le profil ACTIF (sélecteur de profils, profil marqué
// `_is_employe_clinique` par auth-context). Les pages véto travaillent alors
// au nom de la clinique (uid du titulaire + profil clinique), limitées par
// les autorisations de l'employé (employe_permissions) ; un vétérinaire
// employé ne voit que SES RDV et SES patients, l'ASV toute la clinique.
// Miroir appli : AgendaContexte.ouvrirEspace (lib/utils/contexte_pro.dart).
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

export interface EspaceClinique {
  /** Profil actif = clinique où l'on est employé. */
  espace: boolean;
  /** uid du COMPTE pro sur lequel on travaille (titulaire de la clinique en espace employé). */
  uid: string;
  /** Rôle dans la clinique (veterinaire / asv), null hors espace. */
  role: string | null;
  /** Profil de l'employé dans la clinique (= instructeur_profile_id de ses RDV). */
  monProfil: string | null;
  /** Vétérinaire employé : ses RDV / patients seulement. */
  praticien: boolean;
  /** Autorisation accordée (toujours vrai hors espace employé). */
  peut: (droit: string) => boolean;
  /** Rôle et droits chargés (immédiat hors espace employé). */
  charge: boolean;
}

export function useEspaceClinique(): EspaceClinique {
  const { user, availableProfiles, activeProfileId } = useAuth();
  const profil = availableProfiles.find(p => p.id === activeProfileId) as (Record<string, unknown> | undefined);
  const espace = profil?._is_employe_clinique === true;
  const titulaire = espace ? String(profil?._employeur_uid ?? '') : '';
  const [info, setInfo] = useState<{ pour: string; role: string | null; monProfil: string | null; droits: string[] } | null>(null);

  useEffect(() => {
    if (!espace || !user?.uid || !activeProfileId) return;
    let annule = false;
    (async () => {
      const { data: e } = await supabase.from('employes').select('employe_profile_id, role_pro')
        .eq('eleveur_profile_id', activeProfileId).eq('uid_employe', user.uid).eq('actif', true).maybeSingle();
      const monProfil = (e?.employe_profile_id as string | null) ?? null;
      const { data: perms } = monProfil
        ? await supabase.from('employe_permissions').select('permission')
          .eq('eleveur_profile_id', activeProfileId).eq('employe_profile_id', monProfil)
        : { data: [] };
      if (!annule) setInfo({ pour: activeProfileId, role: (e?.role_pro as string | null) ?? null, monProfil,
        droits: ((perms ?? []) as { permission: string }[]).map(p => p.permission) });
    })();
    return () => { annule = true; };
  }, [espace, user?.uid, activeProfileId]);

  const i = espace && info?.pour === activeProfileId ? info : null;
  return {
    espace,
    uid: espace ? titulaire : (user?.uid ?? ''),
    role: i?.role ?? null,
    monProfil: i?.monProfil ?? null,
    praticien: i?.role === 'veterinaire',
    peut: (droit: string) => !espace || !!i?.droits.includes(droit),
    charge: !espace || !!i,
  };
}
