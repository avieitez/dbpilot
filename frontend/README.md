# DBPilot

## Firebase Android configuration

`android/app/google-services.json` is committed because Firebase client
configuration is required at build time. Treat the file as public client
configuration, not as a backend secret.

Before publishing, restrict the Firebase/Google API key in Google Cloud to:

- Android app package: `com.avieitez.dbpilot`
- Release certificate SHA-1/SHA-256 fingerprints

Do not commit signing keys, keystores, `key.properties`, service account JSON or
backend environment variables.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
