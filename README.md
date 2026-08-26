# Multispectral Sensing for Banknote Authentication

Source code for the MSc dissertation *Multispectral Sensing for Banknote Authentication*
(Yihao Yang, Department of Electrical and Electronic Engineering, Imperial College London;
supervisor Prof. Richard Syms).

The project distinguishes genuine Bank of England £20 polymer notes from prop
("movie money") counterfeits using the spectral response of a small region of the note,
measured with a low-cost multispectral sensor rather than a camera. This repository holds
the firmware that drives the sensors and the MATLAB code that produces every number and
figure in the report.

## Layout

```
arduino/   sensor firmware (Arduino IDE sketches, ST7735 TFT readout)
matlab/    analysis pipeline (21 scripts)
docs/      method notes — how the code implements what the report reports
```

**[docs/METHODS.md](docs/METHODS.md)** documents the methods the code implements: the
feature pipeline, the separability measure, the PCA, the leave-one-banknote-out
harness, the two-stage cascade, and the controls of each later experiment.

## Arduino firmware

| Sketch | Sensor | Notes |
|---|---|---|
| `AS7262_test/` | AS7262 (6 channels, 450–650 nm) | minimal serial readout |
| `AS7262_with_LED/` | AS7262 | TFT bar display, on-board LED enabled |
| `AS7341_with_LED/` | AS7341 (F1–F8 + Clear + NIR) | TFT bar display, on-board LED enabled |
| `AS7341/Always_on/` | AS7341 | continuous acquisition |
| `AS7341/Always_on_with_flicker/` | AS7341 | continuous acquisition with flicker detection |

Libraries: `Adafruit_AS726x`, `DFRobot_AS7341`, `Adafruit_GFX`, `Adafruit_ST7735`, `Wire`, `SPI`.

The measurements reported in the dissertation were taken with the on-board LED **disabled**
and an external lamp; the `_with_LED` sketches are the display/diagnostic versions.

## MATLAB analysis

Main pipeline:

| Script | Purpose |
|---|---|
| `banknotes.m` | main pipeline: data discovery, per-channel Cohen's *d*, PCA, leave-one-banknote-out validation, two-stage cascade SVM and model selection |
| `loadNoteSet.m` | shared feature pipeline — F1–F8 and NIR divided by Clear, then SNV per spectrum |
| `region_full.m` | full per-region analysis of one measurement route |
| `direct_regions.m` | same analysis for the directly measured sets |

Individual experiments:

| Script | Question it answers |
|---|---|
| `condition_analysis.m` | does the physical condition of a note affect the system? |
| `scatter_direct.m`, `scatter_routes.m`, `scatter_figs.m` | within-note scatter, by region and by route |
| `ageing_analysis.m` | can the prop notes be aged artificially, and does that defeat the classifier? |
| `alignment_analysis.m` | effect of misalignment and misorientation |
| `rgb_vs_multispectral.m` | what the extra spectral channels buy over plain RGB |
| `fullspectrum_nested.m` | is the full 380–1000 nm spectrum an alternative to the cascade? |
| `recovery_tests.m` | why the digit-stroke accuracy fell, and what recovers it |
| `feasibility_v1_check.m` | reproduces the first-generation feasibility result |
| `region_comparison.m` | comparison across the three candidate regions |
| `pair_check.m`, `pairedSubset.m` | matching the direct and photographic campaigns to the same physical notes |
| `make_*.m` | figure generation for the report |

Requires MATLAB with the Statistics and Machine Learning Toolbox.

## Running the code

The measurement data (AS7341 CSV exports) are **not** included in this repository. The
scripts read them from absolute paths of the form `D:\project\data_<region>` and write
results to `D:\project\Result\result_<region>`; edit those paths at the top of each script
to point at your own copy of the data.

`banknotes.m` selects the region through the `BANKNOTE_REGION` environment variable
(`"20"`, `"white"` or `"yellow"`; default `"20"`):

```matlab
setenv("BANKNOTE_REGION", "white");
banknotes
```

## Relation to the report

The dissertation does not reproduce the code. Each appendix that concerns the
software points here instead:

| Appendix | Where the code lives |
|---|---|
| A — AS7262 firmware | `arduino/AS7262_with_LED/` |
| B — AS7341 firmware | `arduino/AS7341_with_LED/` |
| C — MATLAB analysis code | `matlab/`, documented in [docs/METHODS.md](docs/METHODS.md) |

