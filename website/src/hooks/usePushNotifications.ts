'use client';

import { useEffect } from 'react';
import { getMessaging, getToken } from 'firebase/messaging';
import { doc, setDoc } from 'firebase/firestore';
import app, { db } from '@/lib/firebase';
import { useAuth } from '@/lib/auth-context';

const VAPID_KEY = process.env.NEXT_PUBLIC_FIREBASE_VAPID_KEY ?? '';

export function usePushNotifications() {
  const { user } = useAuth();

  useEffect(() => {
    if (!user || typeof window === 'undefined' || !('serviceWorker' in navigator) || !VAPID_KEY) return;

    (async () => {
      try {
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
