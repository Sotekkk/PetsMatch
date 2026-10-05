'use client';

import { useEffect } from 'react';
import { deleteToken, getMessaging, getToken } from 'firebase/messaging';
import { deleteField, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import app, { db } from '@/lib/firebase';
import { useAuth } from '@/lib/auth-context';

const VAPID_KEY = process.env.NEXT_PUBLIC_FIREBASE_VAPID_KEY ?? '';

/** Navigateur de téléphone / tablette : les notifications passent par l'appli. */
function estMobile() {
  return /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
}

export function usePushNotifications() {
  const { user } = useAuth();

  useEffect(() => {
    if (!user || typeof window === 'undefined' || !('serviceWorker' in navigator) || !VAPID_KEY) return;

    (async () => {
      try {
        // Sur mobile, l'appli reçoit déjà chaque notification : abonner aussi
        // le navigateur du téléphone affichait chaque rappel EN DOUBLE (une
        // fois par l'appli, une fois par le navigateur, titre « PetsMatch »).
        // On retire l'abonnement de ce navigateur s'il était l'abonnement web
        // enregistré, sans toucher à celui d'un ordinateur.
        if (estMobile()) {
          if (Notification.permission !== 'granted') return;
          const reg = await navigator.serviceWorker.getRegistration('/');
          if (!reg) return;
          const messaging = getMessaging(app);
          const token = await getToken(messaging, { vapidKey: VAPID_KEY, serviceWorkerRegistration: reg }).catch(() => null);
          if (!token) return;
          const snap = await getDoc(doc(db, 'users', user.uid));
          if (snap.data()?.webFcmToken === token) {
            await updateDoc(doc(db, 'users', user.uid), { webFcmToken: deleteField() });
          }
          await deleteToken(messaging).catch(() => {});
          return;
        }

        const permission = await Notification.requestPermission();
        if (permission !== 'granted') return;

        const swReg = await navigator.serviceWorker.register('/firebase-messaging-sw.js', { scope: '/' });
        await navigator.serviceWorker.ready;

        // Envoyer la config Firebase au service worker
        const config = {
          apiKey:            process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
          authDomain:        process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
          projectId:         process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
          storageBucket:     process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
          messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
          appId:             process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
        };
        swReg.active?.postMessage({ type: 'FIREBASE_CONFIG', config });

        const messaging = getMessaging(app);
        const token = await getToken(messaging, { vapidKey: VAPID_KEY, serviceWorkerRegistration: swReg });

        if (token) {
          await setDoc(doc(db, 'users', user.uid), { webFcmToken: token }, { merge: true });
        }
      } catch {
        // Notifications non disponibles (navigateur bloqué, pas HTTPS, etc.)
      }
    })();
  }, [user]);
}
