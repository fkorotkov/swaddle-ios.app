# Milestone illustrations

Every milestone check-in now contains an original offline vector Lottie scene: **100 CDC skills and six WHO motor-development windows**, matching the complete app catalog. `storyboards.tsv` maps each skill ID to its action, props, and accessible description; `manifest.json` records the resulting asset, poster frame, duration, and SHA-256.

The three approved studies—waving, crawling, and stacking—retain their action rigs and proportions. The collection uses the same rounded hands without individual fingers, short tucked seated legs, narrow standing stance, shaded cotton clothing, and warm paper palette. Actions include expressions and sounds, looking and reaching, food and toy play, supported movement, walking, and everyday skills. Artwork is illustrative; the official milestone definitions and sources remain separate.

## Authoring and playback

```sh
python3 scripts/generate_milestone_illustrations.py
python3 scripts/generate_milestone_illustrations.py --check
```

The driver verifies complete storyboard coverage against the app's CDC dataset and WHO catalog. `milestone_illustration_art.py` contains the shared vector rig and approved studies; `milestone_illustration_scenes.py` builds the remaining skill-specific actions. There is no generic fallback for an unimplemented action. Generated files include 106 asset-catalog data sets, the Swift lookup, and the hashed manifest. Artwork contains no raster images, fonts, expressions, external assets, or network loading. Lottie iOS remains pinned to 4.6.1.

Each scene is 420 × 280, 30 fps, and six seconds long. `MilestoneIllustrationView` uses the native Core Animation renderer. A visible scene starts from the beginning and loops automatically. One-way actions reset during a gentle fade while the cotton ground stays still. Lottie parent layers do not inherit opacity, so the generator bakes the intended fades into the drawable layers. Every animated property returns to its starting value at the loop boundary.

Pause holds the current pose; Play resumes the full six-second loop, rather than repeating just the remaining portion. Playback pauses offscreen or when the app becomes inactive, and an explicit Pause survives those transitions. Reduce Motion uses a meaningful per-scene poster and hides the playback controls. Animations are enabled in both Debug and Release check-ins; only the open illustration plays.

For isolated Simulator review, launch with `--motion-review --helper --milestones --milestone-illustration=<skill-id>`. This uses fictional in-memory data.

## A varied cast

Child and caregiver profiles no longer collect ethnicity, skin tone, or hair color. Each milestone has a fixed cast selected by a deterministic shuffle at generation time. `milestone_illustration_cast.py` distributes six skin palettes, four child hair colors, four child hairstyles, and five adult hair colors across the collection. Child, caregiver, and incidental actors are assigned independently; each category's counts differ by at most one. The mirror retains its child's palette. The artwork does not label or infer a person's ethnicity.

The generated files contain the final colors and child hairstyles, so reopening a scene or viewing it on another device does not reshuffle its cast. The manifest records each scene's choices and the overall distribution. Runtime actor metadata and profile-based recoloring are removed. Caregiver sex still selects female/male adult silhouettes; leaving it unspecified keeps neutral artwork. `IllustrationPersonalizer` only toggles the three existing caregiver silhouette layers, preserving action geometry, animation keys, duration, fade, and reset. Check-ins resolve the viewer's canonical caregiver without changing observation authorship, growth calculations, or pumping permissions.

`MilestoneAnimationCache` keeps at most 12 parsed asset/sex variants. All 106 scenes stay offline and share their base assets. Raw vector JSON is **10,857,252 bytes**, down **178,356 bytes** from build 37; this is source artwork size, not an Apple download estimate. Legacy profile payloads still decode; newly saved profiles omit the retired fields. Historical revisions are not destructively rewritten.

For profile review, use `--motion-review --child-profile` or `--motion-review --caregiver-profile`. `--illustration-sex=female|male` sets the fictional caregiver's optional sex, and `--illustration-skill=<skill-id>` opens an actual check-in. All review flags are Debug Simulator only.

## Review evidence

See `design/milestone-collection-2026-10-11` for all 106 native-rendered posters and the reproducible gallery snippet. The original three-scene art review remains in `design/milestone-prototypes-2026-10-11`.

The build 38 cast review is in `design/illustration-diversity-2026-10-12`: nine native-rendered contact sheets cover all 106 scenes at three points in their loops, with child and caregiver profile screenshots. Package tests check distribution balance and legacy profile decoding; native tests cover profile persistence, sex selection, merging/separation, and all scene rigs.

`LittleLogTests/MilestoneIllustrationTests.swift` verifies exact catalog coverage, metadata, native Core Animation compatibility, unique parent rigs, ordered keyframes, and matching loop endpoints for all 106 scenes. A pixel-level rendering regression verifies that the hidden reset reaches the actual drawn layers and that representative posters remain visible. Release checks and hands-on playback evidence are recorded in `QA.md` and `.release/1.0-30/qa/`.
