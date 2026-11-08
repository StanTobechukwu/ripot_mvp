# Ripot landing source

Recovered from the report-refresh landing package supplied in October 2026. Static HTML stays on the existing ripot-landing Firebase project, independently of the Flutter web app.

The homepage and support page link Windows customers to the Microsoft Store
listing `https://apps.microsoft.com/detail/9P91S5JQ1FK0`. The header's Get Ripot
action opens the platform choices. Microsoft Premium checkout is a separate
integration; see `docs/MICROSOFT_STORE_PREMIUM_SETUP.md` at the repository root.

Generate template assets from the repository root:

```sh
flutter test tools/export_public_templates.dart
python3 tools/landing/build_templates.py
python3 tools/landing/verify.py
```

Use the generated landing folder in the verified GitHub artifact for deployment. See ../docs/RELEASE_1.0.14_49.md for coordinated app/website release order. Deploying the landing page alone does not update Android, Windows or the web app.
