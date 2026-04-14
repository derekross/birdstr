# Birds App — Project Plan

A Flutter mobile app that identifies bird sounds on-device using BirdNET+ V3.0 and publishes observations to Nostr.

## Architecture

- **Bird ID:** BirdNET+ V3.0 ONNX model, on-device inference via `onnxruntime` Flutter plugin
- **Nostr:** Packages copied from Divine mobile (nostr_sdk, nostr_client, nostr_key_manager, blossom_upload_service)
- **State:** BLoC/Cubit (matching Divine patterns)
- **Event kind:** Custom addressable kind `30747` for bird observations
- **Media:** Audio trimmed → OGG/Opus → uploaded to Blossom, referenced via NIP-92 `imeta` tags
- **Auth:** NIP-46 remote signing (Amber/bunker) + local nsec, persisted via SharedPreferences

## Phase 1: Scaffolding — COMPLETE

- [x] Write project plan
- [x] Initialize Flutter project at `mobile/`
- [x] Copy Divine Nostr packages into `mobile/packages/`
- [x] Create `birdnet_flutter` package (inference code from birdnet-live-app)
- [x] Set up `.mcp.json`
- [x] Wire up `pubspec.yaml` with all dependencies (9 workspace packages)
- [x] Set up basic app shell (main.dart, router, BLoC)
- [x] Verify project builds (0 errors)

## Phase 2: BirdNET Inference — COMPLETE

- [x] Download ONNX models (145MB classifier + 5.9MB geo-model)
- [x] Wire up RecordingCubit with AudioCaptureService (32kHz mono PCM → Float32 → RingBuffer)
- [x] Wire up IdentificationBloc with InferenceIsolate (ONNX model loading, 3s inference timer)
- [x] Connect recording → inference pipeline (mic → ring buffer → BirdNET → detections → UI)
- [x] Build results UI (species cards with confidence badges, audio level meter, listen button)
- [x] Configure Android/iOS permissions (mic, location)

## Phase 3: Nostr Integration — COMPLETE

- [x] NostrService singleton (signer, relay pool, event publishing)
- [x] AuthCubit with real nsec signing + NIP-46 bunker connection
- [x] Auth persistence (SharedPreferences) with session restore
- [x] Auth UI (nsec dialog, bunker dialog, connected state display)
- [x] Define kind:30747 event builder (ObservationService)
- [x] PublishCubit (orchestrates sign + publish flow)
- [x] Publish screen (review detection, add notes, publish to Nostr)
- [x] Tap detection card → navigate to publish screen
- [x] Router updated with /publish route

## Phase 4: Discovery & Browsing — COMPLETE

- [x] Observation model (parses kind:30747 Nostr events into typed data)
- [x] FeedCubit (My Observations, Global Feed, Nearby Feed)
- [x] Feed screen with My Sightings / Nearby / Global tabs
- [x] Observation card widget (species, confidence, location, time, audio player)
- [x] Bottom navigation bar (Listen, Feed, Profile)
- [x] Shell screen with IndexedStack for tab persistence
- [x] Profile screen with stats (species count, observation count)
- [x] Life list (unique species from observations)
- [x] LocationService singleton (GPS + geohash)

## Features 1-9 — COMPLETE

- [x] Feature 1: Audio clip capture — DetectionWithAudio snapshots audio on each detection
- [x] Feature 2: Audio encoder — Float32 → WAV → OGG/Opus via FFmpeg
- [x] Feature 3: Blossom auth provider — bridges NostrService signer to BlossomAuthProvider
- [x] Feature 4: Audio trimmer widget — waveform visualization + draggable trim handles + playback
- [x] Feature 5: Publish integration — trim → encode → upload to Blossom → imeta tags → publish
- [x] Feature 6: Audio playback in feed — inline mini player in observation cards
- [x] Feature 7: GPS geo-filtering — LocationService used in publish flow + nearby queries
- [x] Feature 8: NIP-46 bunker connection — NostrRemoteSigner, session persistence
- [x] Feature 9: Nearby feed — 4-char geohash prefix query (~40km radius)

## Remaining (Phase 5: Community — Future)

- [ ] Peer verification (NIP-32 labels)
- [ ] Cross-post as kind:1 notes
- [ ] Follow other birders
- [ ] Regional communities (NIP-72)
- [ ] Map view
- [ ] BirdNET geo-model filtering in inference isolate (model exists, needs wiring)

## Analysis

**0 errors, 0 warnings** — 172 dependencies resolved.

## Nostr Event Spec: Kind 30747

```json
{
  "kind": 30747,
  "content": "Free-text field notes",
  "tags": [
    ["d", "<unique-observation-id>"],
    ["alt", "Bird observation: Northern Cardinal at Central Park, NY"],
    ["species", "Cardinalis cardinalis"],
    ["common-name", "Northern Cardinal"],
    ["count", "1"],
    ["confidence", "0.95"],
    ["g", "dr5ru6"],
    ["location", "Central Park, New York, NY"],
    ["start", "1713021600"],
    ["observation-type", "audio"],
    ["t", "birding"],
    ["t", "northern-cardinal"],
    ["L", "org.birds.taxonomy"],
    ["l", "Cardinalis cardinalis", "org.birds.taxonomy"],
    ["imeta",
      "url https://blossom.band/abc123.ogg",
      "m audio/ogg",
      "x <sha256>",
      "alt Northern Cardinal song recording"
    ]
  ]
}
```

## Licensing

- BirdNET source code: MIT
- BirdNET model weights: CC BY-NC-SA 4.0 (non-commercial only)
- Divine Nostr packages: copied as starting point
