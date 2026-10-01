// Notifications push web reçues quand l'onglet est fermé ou en arrière-plan
// (plan 5). La configuration (publique) est choisie selon le nom d'hôte :
// « ulmgap-prod » dans l'URL → prod, sinon dev (localhost compris).
// Clic sur une notification : ramène l'onglet de l'app au premier plan, ou
// l'ouvre (URL relative au service worker, valable sur tout domaine). Écouteur
// enregistré avant le SDK, qui sinon ne fait rien sans fcmOptions.link.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if ('focus' in c) return c.focus();
      }
      return clients.openWindow('./');
    }),
  );
});

importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

const configs = {
  dev: {
    apiKey: 'AIzaSyD_PPegQoqgf4zffj1AELkGxwEWB6P12U4',
    appId: '1:237446007254:web:db899714f2670c76da7c77',
    messagingSenderId: '237446007254',
    projectId: 'ulmgap-dev',
  },
  prod: {
    apiKey: 'AIzaSyA8tinxLOF9NvfEO0YeG-Cz3IApoDtsKc4',
    appId: '1:1009736891924:web:f08fa7d090f8cf338ef101',
    messagingSenderId: '1009736891924',
    projectId: 'ulmgap-prod',
  },
};

firebase.initializeApp(self.location.hostname.includes('ulmgap-prod') ? configs.prod : configs.dev);
// Les messages « notification » sont affichés par le SDK lui-même.
firebase.messaging();
