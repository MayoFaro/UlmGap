// Notifications push web reçues quand l'onglet est fermé ou en arrière-plan
// (plan 5). La configuration (publique) est choisie selon le nom d'hôte :
// « ulmgap-prod » dans l'URL → prod, sinon dev (localhost compris).
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
