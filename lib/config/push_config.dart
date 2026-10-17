/// Public "Web Push certificate" key for Firebase Cloud Messaging.
///
/// Firebase console → Project settings → Cloud Messaging → Web
/// configuration → Web Push certificates → Generate key pair, then paste
/// the key here. It's a public key, safe to commit.
///
/// While empty, the Hourly reminders switch explains that reminders
/// aren't set up yet instead of failing.
const String kWebPushVapidKey =
    'BG5qsBlVOFoCc2RlXkxUzeggrb8e2fhVHQon_2IOA4lr5xcwoJ9jaFNnXqaSn2XTS1qq8rkRQUBFHa8WYBEIOKw';
