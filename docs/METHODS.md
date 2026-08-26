# Method notes

These notes document how the code in this repository implements the methods
reported in *Multispectral Sensing for Banknote Authentication*. They explain
the parts of the code that define a method — what a reader would need in order
to judge whether a number in the report was computed correctly, or to
reimplement the procedure. The report carries the results; this file carries
the implementation.

---

## 1. Sensor firmware

Two sensors were evaluated: the AS7262, with six visible channels between
450 and 650 nm, and the AS7341, with eight visible channels (F1–F8) together
with a Clear and a near-infrared channel. Both sketches read the device over
I²C, apply the manufacturer's channel correction, draw the spectrum as a bar
chart on an ST7735 TFT and stream the values over the serial port.

| Sketch | Role |
|---|---|
| [`arduino/AS7262_with_LED/`](../arduino/AS7262_with_LED/AS7262_with_LED.ino) | AS7262 readout and TFT display |
| [`arduino/AS7341_with_LED/`](../arduino/AS7341_with_LED/AS7341_with_LED.ino) | AS7341 readout and TFT display |
| [`arduino/AS7262_test/`](../arduino/AS7262_test/AS7262_test.ino) | minimal AS7262 serial readout |
| [`arduino/AS7341/Always_on/`](../arduino/AS7341/Always_on/Always_on.ino) | continuous AS7341 acquisition |
| [`arduino/AS7341/Always_on_with_flicker/`](../arduino/AS7341/Always_on_with_flicker/Always_on_with_flicker.ino) | continuous acquisition with flicker detection |

The measurements reported in the dissertation were taken with the on-board LED
disabled and an external lamp; the `_with_LED` sketches are the display and
diagnostic versions.

---

## 2. The shared feature pipeline

Every experiment in the report starts from the same nine features. The eight
colour channels and the near-infrared channel are each divided by the Clear
channel, which removes the overall illumination level, and a row is discarded
if the Clear channel is not positive or the whole reading is missing. Each
spectrum is then standard-normal-variate transformed: its mean across the nine
channels is subtracted and it is divided by its own standard deviation across
those channels. The *shape* of the spectrum survives, which is what makes
readings taken at different sensor heights or on differently worn notes
comparable. SNV also fixes each spectrum's across-channel spread at unity,
which is what gives the within-note scatter its interpretation as a percentage
of the note's own spectral contrast.

Implemented in [`matlab/loadNoteSet.m`](../matlab/loadNoteSet.m), shared by the
later experiment scripts so that they use exactly the pipeline of the main
script.

---

## 3. Main pipeline — [`matlab/banknotes.m`](../matlab/banknotes.m)

This script produces the datasets, the spectral comparisons, the PCA and the
classifier results of the classification chapter.

### 3.1 Region selection and data discovery

The script runs once per measurement region. The region is selected by the
`BANKNOTE_REGION` environment variable rather than by editing the file, and
each region writes to its own result folder, so the campaigns on the different
regions cannot overwrite one another. Banknote files are discovered
recursively, so notes can be added or removed without any code change. The
`FakeV1` entry appears only for the digit-stroke region, because the six
first-generation counterfeits were never measured on the two uniform regions.

```matlab
setenv("BANKNOTE_REGION", "white");   % "20" | "white" | "yellow"
banknotes
```

### 3.2 Per-channel separability

The separability of a channel is reported throughout as Cohen's *d*, the
difference between the two class means divided by their pooled standard
deviation. It is preferred to the raw difference because a channel on which the
classes differ by a large amount but scatter by more is not useful, and the
pooled form makes channels with different natural spreads comparable. The
computation runs over every pair of classes, so the three-class comparison uses
the same code as the binary one.

### 3.3 Principal component analysis

The PCA is computed on z-scored channels rather than on the raw features, so
that a channel does not dominate the projection merely because its numerical
range is larger. It is evaluated by singular value decomposition of the centred
matrix, which is numerically better conditioned than forming the covariance
matrix explicitly.

### 3.4 Leave-one-banknote-out validation

Every accuracy quoted in the report comes from this harness. One whole banknote
is held out at a time and the model is refitted on the remainder, so no
measurement of a test note can appear in training even though each note
contributes twenty or more spectra. The classifier is supplied as a function
handle, which is what allows the linear SVM, the RBF SVM, the *k*-nearest
neighbour classifier and the decision tree to be compared under identical
validation.

### 3.5 Two-stage cascade SVM and model selection

The two-stage cascade is the model deployed on the digit stroke. Stage 1 is an
RBF SVM on the nine averaged channels. Rather than accepting its decision for
every note, the cascade identifies the notes it is least sure of, using the
absolute Stage-1 score as the measure of confidence and half the median score
as the threshold; this gate uses no labels, so it can be applied to an unseen
note in the field. Only those notes are passed to Stage 2, which fits a PCA to
the full 380–1000 nm spectrum of the training notes and classifies the held-out
note with an RBF SVM in that space. Both the projection and the classifier are
refitted inside every fold, so the held-out note influences neither.

The final model is then chosen automatically on leave-one-out accuracy, ties
being broken towards fewer missed counterfeits and then towards the simpler
model, which is why the two uniform regions deploy a plain linear SVM and only
the digit stroke deploys the cascade.

---

## 4. Later experiments

The experiments added after the main campaign were written as separate scripts
so that each could be run independently.

### 4.1 Repeat-matched within-note scatter — [`matlab/condition_analysis.m`](../matlab/condition_analysis.m)

The within-note scatter needs one control before it can be compared between
notes. The notes were not all measured the same number of times, and because
every repeat falls at a fresh position, a note measured more often covers more
of the region and appears less repeatable for that reason alone. Each note is
therefore reduced to the same number of repeats as the least-measured note in
its region: a random subset of that size is drawn, its scatter computed, and
the result averaged over four hundred draws.

The script also tests whether the scatter is usable as a feature rather than
merely descriptive. Because a note's scatter is computed from its own repeats
only, no information crosses between notes and the leave-one-banknote-out
validation remains leakage-free.

Related: [`scatter_direct.m`](../matlab/scatter_direct.m),
[`scatter_routes.m`](../matlab/scatter_routes.m),
[`scatter_figs.m`](../matlab/scatter_figs.m).

### 4.2 Nested cross-validation over the full spectrum — [`matlab/fullspectrum_nested.m`](../matlab/fullspectrum_nested.m)

The full-spectrum result required a stricter validation than the rest of the
report. Using the 621 per-nanometre values needs a PCA, and the number of
components is a choice; selecting it by looking at leave-one-out accuracy would
use the test notes to tune the model and inflate the result. The procedure is
therefore wrapped in a second loop. An inner leave-one-out over the training
notes alone selects the component count, ties resolving towards the fewest
components; the outer fold then refits the PCA and the SVM with that count and
predicts the note that neither loop has seen. Comparing this against the naive
figure is what gives the optimism of the shortcut quoted in the report.

### 4.3 The three controls of the ageing experiment — [`matlab/ageing_analysis.m`](../matlab/ageing_analysis.m)

Three controls make the ageing experiment interpretable, and all three are in
this script.

1. **The session-drift floor.** Because a treatment takes days, the before and
   after recordings are necessarily separate sessions, and this project has
   already been shown to be sensitive to session-to-session variation. The
   untreated control notes carried through both sessions give the movement
   attributable to the session alone, and the script warns when the treated
   notes did not move at least twice as far. It is computed per region and
   never pooled, since pooling would hide a region whose controls moved.

2. **The genuine-class radius.** Used to distinguish crossing the decision
   boundary from becoming genuine: the largest distance any genuine note
   reaches from the centre of its own class, computed leave-one-genuine-out so
   that no note helps to define the centre it is measured against, which makes
   the radius slightly generous and the test correspondingly conservative.

3. **Reduced channel sets.** The classifier is retrained on reduced channel
   sets, to test whether simply discarding the attacked channels would repair
   the failure; baseline accuracy is reported alongside, because a feature set
   that rejects everything is not a fix.

Each route is scored by the classifier trained on its own reference set: a
direct recording scored against a screen-trained model would measure the change
of route rather than the ageing.

### 4.4 Other experiments

| Script | Question it answers |
|---|---|
| [`alignment_analysis.m`](../matlab/alignment_analysis.m) | effect of misalignment and misorientation |
| [`rgb_vs_multispectral.m`](../matlab/rgb_vs_multispectral.m) | what the extra spectral channels buy over plain RGB |
| [`recovery_tests.m`](../matlab/recovery_tests.m) | why the digit-stroke accuracy fell, and what recovers it |
| [`feasibility_v1_check.m`](../matlab/feasibility_v1_check.m) | reproduces the first-generation feasibility result |
| [`region_comparison.m`](../matlab/region_comparison.m), [`region_full.m`](../matlab/region_full.m), [`direct_regions.m`](../matlab/direct_regions.m), [`direct_vs_rgb.m`](../matlab/direct_vs_rgb.m) | per-region and per-route analyses |
| [`pair_check.m`](../matlab/pair_check.m), [`pairedSubset.m`](../matlab/pairedSubset.m) | matching the direct and photographic campaigns to the same physical notes |
