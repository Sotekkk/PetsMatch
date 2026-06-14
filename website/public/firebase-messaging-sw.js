importScripts('https://www.gstatic.com/firebasejs/10.11.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.11.0/firebase-messaging-compat.js');

// Reçoit la config Firebase depuis la page principale (postMessage)
self.addEventListener('message', (event) => {
  if (event.data?.type !== 'FIREBASE_CONFIG') return;
  if (firebase.apps.length) return; // déjà initialisée
  firebase.initializeApp(event.data.config);
  const messaging = firebase.messaging();
  messaging.onBackgroundMessage((payload) => {
    const title = payload.notification?.title ?? 'PetsMatch';
    const body  = payload.notification?.body  ?? '';
    self.registration.showNotification(title, {
      body,
      icon:  '/Logo_petsmatch_fond_blanc.png',
      badge: '/Logo_pets_match_sans_fond.png',
      data:  payload.data ?? {},
      vibrate: [200, 100, 200],
    });
  });
});
