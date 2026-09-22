fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios validate

```sh
[bundle exec] fastlane ios validate
```

Validate local release data and metadata against App Store Connect

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload localized metadata; add UPLOAD_SCREENSHOTS=1 after capture

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Upload App Store screenshots without changing metadata or binary

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Upload an exported IPA to TestFlight

### ios release_candidate

```sh
[bundle exec] fastlane ios release_candidate
```

Upload IPA and store data without submitting for review

### ios submit_review

```sh
[bundle exec] fastlane ios submit_review
```

Explicitly submit the prepared version for manual release

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
