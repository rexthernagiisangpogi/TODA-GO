/* Firebase Messaging Service Worker for Flutter Web */
/* Uses compat SDK and mirrors lib/firebase_options.dart web config */

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

const firebaseConfig = {
  apiKey: "AIzaSyD1zQhG5UW305Xc9teFN1o37Jqv8vGw-20",
  authDomain: "todago-53cbf.firebaseapp.com",
  projectId: "todago-53cbf",
  storageBucket: "todago-53cbf.firebasestorage.app",
  messagingSenderId: "736872799385",
  appId: "1:736872799385:web:3fe1802b80762170e5ac08"
};

if (self.firebase?.apps?.length === 0) {
  self.firebase.initializeApp(firebaseConfig);
}

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  // Customize or forward to Flutter app via notifications
  const title = (payload?.notification && (payload.notification.title || '')) || 'Notification';
  const body = (payload?.notification && (payload.notification.body || '')) || '';
  const icon = (payload?.notification && (payload.notification.icon || '/icons/Icon-192.png')) || '/icons/Icon-192.png';
  self.registration.showNotification(title, { body, icon });
});
