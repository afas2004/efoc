@echo off
flutter build web --release --pwa-strategy=none
firebase deploy