# FruitySelia for iOS

Native SwiftUI implementation for iPhone and iPad. The main app targets iOS 17;
the Control Widget extension targets iOS 18.

The Xcode target, historical bundle identifiers, `seliascan://` URL scheme, and
private storage directory retain the SeliaScan identifier for update and data
compatibility. The customer-facing iOS product name is FruitySelia.

## Build and test

The checked-in project is generated from `project.yml` with XcodeGen. Xcode 26.6
was used for local verification.

```sh
cd ios
xcodegen generate
xcodebuild -project SeliaScan.xcodeproj -scheme SeliaScan \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Choose an installed simulator from `xcrun simctl list devices available`, then:

```sh
xcodebuild -project SeliaScan.xcodeproj -scheme SeliaScan \
  -destination 'platform=iOS Simulator,id=<DEVICE-UUID>' \
  CODE_SIGNING_ALLOWED=NO test
```

## Structure

- `App`: scene routing, direct cold-launch scanning, privacy cover.
- `Models`: Codable document, page, revision, analysis, output, and edit values.
- `Features`: scanner, import, Result, viewer, Recent, editing, cleanup,
  redaction, signatures/stamps, export, actions, and settings.
- `Services`: Vision, rendering, PDF, storage, Photos, Files, share, and print.
- `SystemIntegration`: iOS 17 App Intent and iOS 18 Control Widget.
- `Shared`: app identity, routing, launch arguments, icons, and UI automation IDs
  shared by the app, widget, and UI-test targets.
- `SeliaScanTests` and `SeliaScanUITests`: storage, geometry, security,
  compression, mark, searchable-PDF, and fixture-scanner flows.

## Storage and privacy

Full-resolution pages live under `Library/Caches/SeliaScan/Recent/<UUID>` and
manifests use relative references. Manifest writes are atomic. Recent is a
disposable working area bounded to eight completed scans; eviction never removes
user-saved Files or Photos outputs. Private content uses complete file protection
and is excluded from backup. Saved signature/stamp templates are protected,
backup-excluded, and bounded to 12.

FruitySelia contains no networking, analytics, advertising, account, cloud-library,
or third-party processing code. OCR, barcode detection, cleanup, redaction, image
rendering, and PDF generation use Apple frameworks on device. Recent OCR is not
indexed into Spotlight. Explicit OCR/barcode copies use local-only, expiring pasteboard
items; detected URLs are never opened automatically.

Default PDF/image folders use persistent security-scoped bookmarks. Each document
can override or clear them. Saved outputs retain an exact file bookmark or Photos
asset identifier, so missing state and deletion do not rely on filename matching.

## Rendering and export

Ordinary crop, rotation, filters, adjustments, and marks stay as edit data; the
source is rendered once at final export resolution. Smart/manual cleanup and secure
redaction create child revisions. Redaction is flattened into new pixels, resets
reversible edits, and removes intersecting OCR/barcode metadata before searchable
PDF export.

Searchable PDFs keep the scan image as the visible page and add aligned invisible
text. OCR failure leaves a valid image-backed PDF. Target-size export renders edits
once, then uses seven bounded compression passes, visual/text complexity weights,
small-text resolution floors, and barcode revalidation. If Vision revalidation is
temporarily unavailable, a conservative barcode pixel floor applies. Readability
wins over an impossible byte target and the achieved size is reported.

`Original` image export means the archived scanner/import source when no edits are
present. VisionKit supplies `UIImage`, so scanner pages are deliberately archived
once as JPEG at quality 0.98. Imported image formats are retained without relabeling.

PencilKit drawings remain drawing data until final-resolution compositing. Imported
and scanned stamps are bounded, converted to background-transparent PNG, reusable,
and placeable by drag, pinch, rotation, or numeric controls.

## Native differences from Android

- VisionKit document camera and system Photos/Files import.
- Live Text and native data detectors directly on page previews.
- Searchable PDF text layer with redaction-aware exclusion.
- Native activity, Files, Photos, print, LocalAuthentication, App Intent, Home
  quick action, and Control Center surfaces.
- Adaptive split navigation on iPad and drag page reordering.
- Standard system-language behavior through a five-language String Catalog.

## Known limits and device validation

PDF imports are rendered sequentially into bounded page working copies; preserving
the original PDF as a lazy revision source remains future work. Imported stamps use
conservative white-background removal, not generative fill. Visual signatures are
not cryptographic signatures.

Simulator tests do not validate the physical document camera, Face ID/Touch ID,
Photos authorization behavior, security-scoped third-party providers, Control
Center/Lock Screen/Action Button launch, Apple Pencil input, printing, or real-device
memory pressure. Those require signed real-device testing. LockedCameraCapture,
permanent document library, Spotlight document indexing, cloud sync, and generative
AI are intentionally not implemented.

## App Store release

Release metadata, privacy/age-rating answers, publisher-only blockers, and exact
commands live in [`AppStore/APP_STORE_CONNECT.md`](AppStore/APP_STORE_CONNECT.md).
Run `tools/validate_app_store.sh` for local checks. Full build, test, screenshot,
archive, signing, TestFlight, and submission steps require full Xcode and the
publisher's App Store Connect credentials.
