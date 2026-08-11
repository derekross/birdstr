# BirdStr

A Flutter mobile app that identifies bird sounds on-device using BirdNET and publishes observations to Nostr.

Listen for birds. Identify them. Share what you hear.

## How It Works

**BirdStr** uses your phone's microphone to listen for bird sounds, identifies the species using machine learning, and lets you publish your sightings to the Nostr network where other birders can discover them.

### Bird Identification (BirdNET)

Bird sound identification is powered by [BirdNET](https://birdnet.cornell.edu/), an open-source neural network developed by the [Cornell Lab of Ornithology](https://www.birds.cornell.edu/) and [Chemnitz University of Technology](https://www.tu-chemnitz.de/).

**All identification happens locally on your device.** The BirdNET+ V3.0 ONNX model runs entirely on-device via ONNX Runtime. No audio is sent to any server for identification. Your microphone data never leaves your phone unless you explicitly choose to publish an observation.

- **Model:** BirdNET+ V3.0 (FP16, ~145MB)
- **Species coverage:** 6,500+ bird species globally
- **Inference:** Runs on a background Dart isolate, processes 3-second audio windows
- **Audio format:** 32kHz mono PCM captured from the device microphone
- **Privacy:** Zero cloud dependency for identification. Fully offline capable.

The BirdNET source code is MIT licensed. The trained model weights are CC BY-NC-SA 4.0 (non-commercial use).

### Nostr Publishing

When you identify a bird and choose to publish it, BirdStr creates a **kind:30747** addressable event on Nostr containing:

- Species (scientific + common name)
- Confidence score from BirdNET
- Geolocation (geohash) if GPS is available
- Audio clip (trimmed WAV uploaded to Blossom)
- Field notes
- Taxonomy labels (NIP-32) for discoverability

The audio clip is encoded as WAV and uploaded to your configured Blossom media server (BUD-01/BUD-03). The event references the audio via NIP-92 `imeta` tags.

## Features

### Listen & Identify
- Real-time bird sound identification from your phone's mic
- Session list accumulates all species heard (deduplicated, best confidence kept)
- Animated listen button with audio level visualization
- Tap any detection to see Wikipedia info (photo, description) and publish

### Publish to Nostr
- Publish individual observations as kind:30747 events
- Audio waveform trimmer with playback preview
- GPS location auto-detected and encoded as geohash
- Audio clips uploaded to Blossom, referenced via `imeta` tags

### Social Feed
- **Following** feed using NIP-65 outbox model (queries each user's write relays)
- **Nearby** feed (geohash-based proximity search)
- **Global** feed (all kind:30747 events)
- Bird photo cards with Wikipedia images
- Inline audio playback on observation cards
- Cross-post observations as kind:1 notes
- Follow other birders
- Peer verification (NIP-32 labels: confirm/dispute IDs)

### History & Life List
- Local discovery log persists every detection with audio clips
- Life list tracks unique species across all sessions
- History survives app restarts (stored as local JSON + WAV files)
- Tap any entry for Wikipedia info and publish option

### Profile
- Public profile shows your published observations from Nostr relays
- Public life list derived from published kind:30747 events
- Separate from local history (you control what's public)

### Map
- OpenStreetMap view with observation pins
- Pins color-coded by confidence score
- Tap a pin for observation details

### Settings
- **Account:** NIP-46 remote signing (Amber/bunker) or local nsec import
- **Relays:** NIP-65 relay list management, read/write per relay, publish kind:10002
- **Blossom:** Server list management, reorderable priority, publish kind:10063

## Nostr Event Spec

### Kind 30747: Bird Observation

```json
{
  "kind": 30747,
  "content": "Field notes about the observation",
  "tags": [
    ["d", "<unique-observation-id>"],
    ["alt", "Bird observation: Northern Cardinal at Central Park, NY"],
    ["species", "Cardinalis cardinalis"],
    ["common-name", "Northern Cardinal"],
    ["confidence", "0.9500"],
    ["g", "dr5ru6"],
    ["location", "Central Park, New York, NY"],
    ["start", "1713021600"],
    ["observation-type", "audio"],
    ["t", "birding"],
    ["t", "birdwatching"],
    ["t", "northern-cardinal"],
    ["L", "org.birds.taxonomy"],
    ["l", "Cardinalis cardinalis", "org.birds.taxonomy"],
    ["imeta",
      "url https://blossom.band/<sha256>.wav",
      "m audio/wav",
      "x <sha256>",
      "alt Northern Cardinal song recording"
    ]
  ]
}
```

## Tech Stack

| Component | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Bird ID model | BirdNET+ V3.0 ONNX (on-device) |
| Inference runtime | ONNX Runtime Flutter plugin |
| Audio capture | `record` package (32kHz mono) |
| Nostr protocol | nostr_sdk (events, signing, relays, NIPs) |
| Nostr signing | NIP-46 remote signing + local nsec |
| Relay management | NIP-65 (kind:10002) |
| Media hosting | Blossom (BUD-01, kind:10063 server list) |
| State management | BLoC/Cubit |
| Map | flutter_map + OpenStreetMap |
| Bird info | Wikipedia REST API |

## Privacy

- **Bird identification is 100% local.** The BirdNET model runs on your phone. No audio is uploaded for identification.
- **Audio is only uploaded when you publish.** The trimmed WAV clip is uploaded to your Blossom server only when you explicitly tap "Publish to Nostr."
- **GPS is optional.** Location is only captured when publishing and only if you grant permission.
- **Local history stays local.** Your detection log and life list are stored on-device and never shared unless you publish individual observations.
- **You control your relays and servers.** Configure which Nostr relays and Blossom servers to use in Settings.

## Building

### Prerequisites

- Flutter 3.41+ / Dart 3.11+
- Android SDK 24+ or iOS 14+

### Setup

```bash
cd mobile
flutter pub get
```

### ONNX Models

The BirdNET ONNX model files (~150MB) are excluded from git. Download them from the [birdnet-live-app](https://github.com/birdnet-team/birdnet-live-app) repository (requires Git LFS) and place them in `mobile/assets/models/`:

- `BirdNET+_V3.0-preview3_Global_5K-pruned_FP16.onnx` (~145MB)
- `BirdNET+_Geomodel_V3.0.1_Global_5K-pruned_FP16.onnx` (~5.9MB)

### Build

```bash
cd mobile
flutter build apk --debug    # Android
flutter build ios --debug     # iOS
```

## Credits

- [BirdNET](https://birdnet.cornell.edu/) by Cornell Lab of Ornithology & Chemnitz University of Technology
- [birdnet-live-app](https://github.com/birdnet-team/birdnet-live-app) for the Flutter inference code
- [Divine](https://divine.video) for the Nostr SDK and Blossom upload packages
- [Nostr](https://nostr.com/) protocol

## License

App source code: MIT — see the [LICENSE](LICENSE) file for details.

BirdNET model weights: CC BY-NC-SA 4.0 (non-commercial use only). Contact the [Cornell Lab of Ornithology](https://www.birds.cornell.edu/) for commercial licensing.
