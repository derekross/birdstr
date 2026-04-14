# BirdNET+ ONNX Models

The ONNX model files are **not included** in this repository because they are large binary files (~259 MB each) tracked with Git LFS.

## Required model files

- `BirdNET+_V3.0-preview3_Global_5K-pruned_FP16.onnx` — Audio classifier model
- `BirdNET+_Geomodel_V3.0.1_Global_5K-pruned_FP16.onnx` — Geographic species prediction model

## How to download

Clone the BirdNET Live App repository with Git LFS enabled:

```bash
git lfs install
git clone https://github.com/birdnet-team/birdnet-live-app
```

Then copy the ONNX files from `assets/models/` into this directory.

Alternatively, if you already have the repository cloned without LFS:

```bash
cd /path/to/birdnet-live-app
git lfs pull
cp assets/models/*.onnx /path/to/birds/mobile/assets/models/
```
