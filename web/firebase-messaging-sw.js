// Delivers hourly reminders while efoc isn't open.
//
// The sender (worker/remind.py) puts the title/body in `notification` and
// the target URL in `webpush.fcm_options.link`, so the Firebase SDK shows
// the notification and opens efoc on tap by itself.
//
// Keep the version in step with firebase_core_web's
// supportedFirebaseJsSdkVersion when upgrading Firebase packages.
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAlDgNzOW05QIwUKPxY4_2C0ppipL3GVX4',
  appId: '1:896506768903:web:e773de378336bc944d44a2',
  messagingSenderId: '896506768903',
  projectId: 'efoc-fcf44',
});

firebase.messaging();
