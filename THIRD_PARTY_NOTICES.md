# Third-party notices

The repository's MPL 2.0 license covers original Swaddle contributions. It does not replace the terms attached to dependencies or external source materials.

## Lottie for iOS

Swaddle uses [Lottie 4.6.1](https://github.com/airbnb/lottie-ios/tree/4.6.1), an Airbnb project distributed under the [Apache License 2.0](https://github.com/airbnb/lottie-ios/blob/4.6.1/LICENSE). Swift Package Manager retrieves the dependency with its upstream license. The milestone illustrations rendered by Lottie are original Swaddle assets, not animations downloaded from LottieFiles or another marketplace.

## CDC milestone checklists

The checklists are sourced from the US Centers for Disease Control and Prevention. CDC materials are available free from the [official milestone website](https://www.cdc.gov/act-early/milestones/index.html). See the [CDC use-of-agency-materials policy](https://www.cdc.gov/other/agencymaterials.html) and the [catalog provenance](ReferenceData/Milestones/README.md).

CDC, HHS, and the US Government do not endorse Swaddle. No CDC logo, photograph, or video is included in the app. Downloaded documents and attributed text retain their source notices; translations created for Swaddle are identified in the [localization notes](ReferenceData/Localization/README.md).

## WHO growth and motor-development references

The app uses numerical reference data from the [WHO Child Growth Standards](https://www.who.int/tools/child-growth-standards). Official workbooks and documents are retained under `ReferenceData` for reproducibility, with source URLs and hashes. They are WHO materials and are not relicensed under MPL 2.0. Consult their own notices and [WHO's copyright policy](https://www.who.int/about/policies/publishing/copyright) before reusing those documents.

The app bundles generated numerical coefficients rather than the original workbooks or WHO chart artwork. See the [weight reference notes](ReferenceData/WHO/README.md), [length/height and head reference notes](ReferenceData/GrowthMeasurements/README.md), and [motor-development provenance](ReferenceData/Milestones/README.md). WHO does not endorse Swaddle.

## Historical preterm references

`ReferenceData/Preterm` and the archived Oxford tables document an earlier implementation. They do not supply percentiles in the current app. Their original source terms and attributions remain applicable; see the [historical notes](ReferenceData/Preterm/README.md). The MPL notice does not grant rights in externally authored documents or previously attributed code.

## Apple technologies

SwiftUI, CloudKit, WidgetKit, App Intents, system fonts, and SF Symbols are Apple technologies used under their applicable terms. Apple trademarks and system assets are not relicensed by this repository.
