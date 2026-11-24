'use client';

// Vrai si l'utilisateur connecté est admin (même règle que la page /admin :
// users.isAdmin dans Firestore). Sert à laisser l'admin consulter les fiches
// publiques d'un profil encore en cours de validation.

import { useEffect, useState } from 'react';
import { doc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { useAuth } from '@/lib/auth-context';

export function useEstAdmin(): boolean {
  const { user } = useAuth();
  const [admin, setAdmin] = useState(false);
  useEffect(() => {
    if (!user) { setAdmin(false); return; }
    let actif = true;
    getDoc(doc(db, 'users', user.uid))
      .then(s => { if (actif) setAdmin(s.exists() && s.data()?.isAdmin === true); })
      .catch(() => {});
    return () => { actif = false; };
  }, [user]);
  return admin;
}
