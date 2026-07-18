importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyCIeAkGcbZCZPBB7n-2rmGx6f6yU2m58dY",
  authDomain: "prepora-c2d23.firebaseapp.com",
  projectId: "prepora-c2d23",
  storageBucket: "prepora-c2d23.firebasestorage.app",
  messagingSenderId: "546702209629",
  appId: "1:546702209629:web:49233391c3654113abd3b4",
  measurementId: "G-4KD9MKZ844"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || 'PrePora';
  const options = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
  };
  self.registration.showNotification(title, options);
});