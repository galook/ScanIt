# FruitySelia App Store release

This directory is the source of truth for App Store Connect answers. Localized product-page copy lives under `fastlane/metadata`; executable automation lives under `tools`.

## Already prepared

- Current product name: **FruitySelia**.
- Historical bundle ID retained: `com.majkeylab.seliascan`.
- Version `2.0`, with a unique UTC build number supplied by the archive script.
- Free app; Productivity primary category and Utilities secondary category.
- Localized metadata for English, Czech, German, Spanish, and Simplified Chinese.
- App Review path and permission explanations.
- Privacy answers: **Data Not Collected** and **No Tracking** for the iOS app.
- Export compliance: no encryption implemented by the app; `ITSAppUsesNonExemptEncryption = false`.
- Content rights: app does not provide third-party catalog content.
- Age-rating answers: none of Apple's listed content descriptors apply. Users only edit their own local documents; there is no in-app publishing, chat, or public user-generated-content service.
- A privacy manifest declaring the app's own UserDefaults and file-timestamp API reasons.
- App icon: 1024×1024, opaque.
- Public marketing, support, and iOS privacy-policy source pages under `docs/fruityselia`.
- Native scripts for project generation, build/test, release archive/export, and localized screenshot capture.
- Fastlane lanes for App Store configuration/status, metadata validation/upload, TestFlight upload, release-candidate upload, and explicitly gated review submission.

## Publisher-only values and decisions

These cannot be truthfully invented or completed from source code:

1. Confirm that **FruitySelia** is available as the App Store name and create the App Store Connect app record with SKU `fruityselia-ios`.
2. Create an App Store Connect API key with the least privilege needed for upload. Put it outside the repository and fill `.env.appstore` from `.env.appstore.example`.
3. Copy `fastlane/metadata/review_information/phone_number.txt.example` to `phone_number.txt` and enter a real internationally dialable reviewer phone number.
4. Declare the publisher's EU Digital Services Act trader status and provide any required verified address, phone, and email. This is a legal/business declaration, not a code inference.
5. Confirm territory availability. The suggested price is free, manual release, no phased release.
6. Confirm agreements, tax, and banking status in App Store Connect. A free app normally needs no paid-app bank setup, but account banners control the actual requirement.
7. Run signed tests on real iPhone and iPad hardware, including camera, Photos permissions, Face ID/Touch ID, Files providers, Control Center, printing, Pencil, and memory pressure.
8. Have native speakers approve localized store copy.
9. Publish the `docs/fruityselia` pages before uploading metadata, then verify all three HTTPS URLs without authentication.

## One-time setup

```sh
cd ios
cp .env.appstore.example .env.appstore
cp fastlane/metadata/review_information/phone_number.txt.example \
  fastlane/metadata/review_information/phone_number.txt
bash tools/bootstrap-release.sh
```

Fill both ignored files. Do not put the `.p8` key in this repository.

For the manual GitHub Actions release workflow, protect an environment named
`app-store-production` and add these environment secrets:

- `APP_STORE_APP_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`
- `APP_REVIEW_PHONE`
- `APPLE_DISTRIBUTION_CERTIFICATE_BASE64`
- `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `APPLE_BUILD_KEYCHAIN_PASSWORD`

Encode the `.p8` key and distribution `.p12` as one-line base64 values. Use a
dedicated random keychain password. Add required reviewers to the protected
environment so the workflow cannot publish without human approval.

## Release flow

```sh
cd ios
bash tools/build-and-test.sh
bash tools/capture-app-store-screenshots.sh
bash tools/archive-app-store.sh --unsigned
bash tools/validate_app_store.sh --submission
bash tools/archive-app-store.sh
bash tools/bundle.sh exec fastlane ios configure
bash tools/bundle.sh exec fastlane ios status
bash tools/bundle.sh exec fastlane ios validate
UPLOAD_SCREENSHOTS=1 bash tools/bundle.sh exec fastlane ios release_candidate
```

The configure lane applies the free USA base price, availability in all current
territories and new territories, Productivity/Utilities categories, the checked-in
age-rating answers, content rights, manual release, export compliance, and review
contact details. It is idempotent. Without `APP_REVIEW_PHONE`, it applies everything
else and prints the remaining reviewer-phone blocker. The status lane reads Apple
back and reports the processed build, disclosures, localizations, screenshot counts,
pricing, and all territory states without printing credentials or the phone number.

Test the processed build in TestFlight. After checking the generated product page, privacy answers, age rating, territories, reviewer contact, and compliance questions:

```sh
CONFIRM_SUBMIT=YES bash tools/bundle.sh exec fastlane ios submit_review
```

The submission lane uses manual release and deliberately refuses to run without the confirmation variable.

## App Privacy answers

Choose **No, we do not collect data from this app**. Choose **No** for tracking. The iOS target has no network client, analytics, advertising, login, cloud library, or third-party SDK. Document pixels, OCR, barcodes, settings, recent scans, and saved marks remain on device unless the user explicitly selects a system share, print, Photos, Files, or third-party file-provider destination. Do not reuse the Android/Google Play privacy answers for this iOS binary.

## Review notes

No login is required. The app opens Apple's document camera on first launch. The reviewer can cancel it and use Import to test with an image or PDF. Photos permission is requested only for an explicit Photos save or tracked-output deletion. Device authentication is optional and off by default. Visual signatures are marks, not cryptographic signatures.

## Screenshot set

The screenshot UI test captures Result, Viewer, Actions, Sign/Stamp, File Details, and Recent. The script captures a 6.9-inch iPhone and 13-inch iPad in all five supported languages and exports files to Fastlane's locale folders. Inspect every image for private data, clipped localization, status-bar anomalies, and simulator-only artifacts before upload.
