# Appendix E — Analysis of the printed £20 digit stroke

Extended version of Appendix E of the thesis. The thesis retains the key results needed to
support the comparisons made in Chapters 5 and 6; this document carries the complete
analysis, including the full spectral plots, the PCA outputs, the per-note margins, the
borderline-note recovery analysis and the additional classifier comparisons.

## Purpose

The project began on a third region, the purple printed stroke at the base of the printed
"£20" numeral, and most of the campaign was recorded there before the two uniform regions
were adopted. It is reported separately because it is a feature of one denomination rather
than of the note series, because it exists on only one of the two measurement routes, and
because the experiments it supports are properties of a finely printed region that do not
carry over to a uniform one. It does establish why the photographic route was adopted at all,
and what a three-colour measurement costs when the class difference is small.

## Dataset

- **24 genuine and 30 counterfeit notes, 1247 spectra.** This is a *different cohort* from the
  27 + 31 notes of the main experiments, which is a confound wherever the digit stroke is
  compared against the uniform regions.
- **Photographic route only.** The measurement head must rest on the target and no source fits
  between it and the note, so the only direct geometry is transmission, and the reverse of a
  prop note carries the supplier's overprint across most of its area. Over a printed region
  the two designs superimpose and the show-through dominates the reading, which rules the
  direct route out here.

## Method

Preprocessing, note-level averaging and leave-one-banknote-out validation are those of
Chapter 3 of the thesis: each channel divided by the Clear channel of the same reading, then
the standard normal variate transform per spectrum, then the mean over a note's repeated
readings. The play-money notes of Appendix D are retained in the plots below as a third class,
because they fix the scale against which the two classes of interest are close.

## Full results

### Channel-wise spectral comparison

The genuine and current-counterfeit class means follow almost the same shape and overlap once
the per-channel standard deviation is included, as expected of a high-quality imitation. The
V1 mean deviates visibly in the blue, at F2 (445 nm).

Separability by Cohen's *d*, genuine against current counterfeit:

| Channel | \|d\| |
|---|---|
| F1 (415 nm) | **1.31** |
| F3 (480 nm) | 0.96 |
| F2 (445 nm) | 0.79 |
| F7 (630 nm) | 0.72 |
| F8 (680 nm) | 0.70 |
| F6 (590 nm) | 0.43 |
| F4 (515 nm) | 0.27 |

No single channel separates the classes, so discrimination relies on a combined pattern across
several. The largest effects anywhere in this dataset all involve the V1 counterfeits, which
are present only as a reference scale.

### Principal component analysis

PCA was applied to the z-scored nine-channel feature vectors of all three classes, as a
description of the data and not as a decision rule. The first three components explain
**54.2 %, 21.4 % and 13.3 %** of the total variance, **89.0 % together**. The genuine samples
form a compact cluster, the current counterfeits are far more dispersed and partly surround
it, and the V1 counterfeits overlap the edge of that cloud, so the classes are not separated
at the individual-measurement level; that is what motivates per-note averaging and a dedicated
classifier. PC1 is dominated by F6, F7, F2 and F3.

A supervised projection such as linear discriminant analysis or PLS-DA is left as future work,
given the risk of overfitting the present sample.

### Classification results and classifier comparison

The Euclidean distance between the mean spectra of every genuine–counterfeit pair identifies
Fake30 as the most convincing imitation in the dataset, at 0.074 from Real7 and 0.081 from
Real8 — and Real7 and Real8 are the two genuine notes the single-stage classifier rejects.

| Classifier | Accuracy | FP | FN |
|---|---|---|---|
| Linear SVM | 96.30 % | 2 | 0 |
| RBF SVM | 96.30 % | 2 | 0 |
| Decision tree | 94.44 % | 1 | 2 |
| *k*-NN (*k* = 3) | 90.74 % | 3 | 2 |
| **Exploratory two-stage cascade** | **100 %** | 0 | 0 |

FP and FN are counts over 24 genuine and 30 counterfeit notes. Every SVM-based method errs by
rejecting genuine notes rather than accepting counterfeits, which is the safer failure mode.

### Recovering the borderline notes

Real7 and Real8 are not measurement failures. After a first analysis identified them as
outliers they were recorded again from scratch several times under the same protocol, and each
time returned to the same position relative to the rest of the genuine class. They are the two
genuine notes whose printed stroke lies closest to the prop notes, as the pairwise distances
confirm, and they are recovered by a different representation rather than by more sampling.

Stage 1 of the cascade is the nine-channel SVM, whose confidence is the signed distance from
the decision boundary. The **7 of 54** notes closest to that boundary pass to Stage 2, which
re-examines them on a PCA reduction of the software-reconstructed 380–1000 nm representation.
Both rejected genuine notes are recovered, reaching 100 %.

The 621 reconstructed values are reconstructed on the PC from the same ten channel readings,
so the second stage adds no spectral information; it weights the same readings differently,
and the gain measures that change of representation.

**Control — using the reconstructed representation for every note.** Applying it to all notes
rather than only borderline ones was tested under a nested leave-one-banknote-out loop that
refits the PCA basis and reselects the component count inside each fold. It reaches 100 % on
the digit stroke and on the white area, but only **98.28 %** on the yellow patch, where the
nine channel means classify every note correctly. Substituting 621 correlated wavelengths for
nine calibrated channels can discard part of the direction that separates the classes, so the
extra detail earns its place only where the nine channels are short of information. The
nesting matters on its own account: the naive version of the same experiment returns 100 % on
the yellow patch against the nested 98.28 %, an optimism of 1.7 percentage points.

The Stage-1 margin distribution is compressed towards zero in a way that does not occur on
either uniform region.

### Within-note scatter on the digit stroke

The digit stroke exists only on the photographic route, yet there the within-note scatter is
the strongest cue available, because a halftone raster survives the camera and the display
where paper fibre does not.

| Quantity | Genuine | Prop |
|---|---|---|
| Mean repeat-matched scatter | 0.056 | 0.174 |
| Range | all below 0.083 | all above 0.095 |

Effect size **\|d\| = 3.48**, rank-sum *p* = 3.9 × 10⁻¹⁰, with the classes completely
separated. The largest single-channel effect from the *mean* spectra on this region is only
\|d\| ≈ 1.31, so the repeatability of a note carries an effect about two and a half times
larger than its colour.

The larger scatter is a property of the printing rather than of wear: it is absent on the
yellow patch recorded under the same protocol, the instability concentrates in the channels
where the synthesized purple differs most from the genuine ink — F7 (630 nm), F2 (445 nm) and
F4 (515 nm) — and the prop notes have never circulated whereas the genuine notes are
individually worn, so wear predicts the opposite ordering.

Scatter as a classification feature:

| Feature set | Features | Linear SVM | RBF SVM | FP | FN |
|---|---|---|---|---|---|
| 9 channel means | 9 | 96.3 % | 96.3 % | 2 | 0 |
| 9 channels + scatter | 10 | **100 %** | **100 %** | 0 | 0 |
| Scatter only | 1 | 98.1 % | 98.1 % | 0 | 1 |

The two genuine notes both single-stage classifiers reject are exactly the notes the extra
feature recovers, and it does so from measurements the device has already taken, where the
cascade needs the full reconstructed representation, a PCA projection and a second classifier.
The single error made by the scatter alone is an artefact of the validation procedure rather
than evidence of overlap: the classes do not overlap, but under leave-one-out the threshold is
re-fitted without the held-out note, and withholding the prop note closest to the gap places
the boundary just above it.

**Condition.** The 24 genuine notes were graded on the three-point scale of the thesis,
12/9/3 across grades 1–3. Condition grade correlates with within-note scatter at
**ρ = +0.72** (*p* = 6.7 × 10⁻⁵), the only correlation in the study that survives the
Bonferroni threshold of *p* < 0.0083 across the six tests within the genuine class, and with
the margin at ρ = +0.55 (*p* = 0.0056; Kruskal–Wallis *p* = 0.028). Because the class means
here are at best \|d\| ≈ 1.31 apart, the extra variability is enough to move a note relative to
the boundary, whereas on the uniform regions the classes stand five to nine standard
deviations apart and the same degradation disappears against that gap.

The sign of the margin correlation is positive: the more worn a genuine note is, the *more*
confidently it is accepted as genuine, and Real7 and Real8 were both graded 1. Wear may thin
the purple ink and let more of the polymer substrate show through, moving the spectrum away
from the synthesized purple of the prop notes, but the yellow patch is printed as well and
shows no margin effect, so the mechanism should be read as plausible rather than established.
The grading was also not blind, although the bias that invites would be to grade the failing
notes as worn and the grades run the opposite way.

### Comparison of the three measurement regions

| | Digit "2" stroke | Yellow patch | White area |
|---|---|---|---|
| Genuine / counterfeit notes | 24 / 30 | 27 / 31 | 27 / 31 |
| Spectral measurements | 1247 | 1319 | 1365 |
| Linear SVM accuracy | 96.30 % | 100 % | 100 % |
| RBF SVM accuracy | 96.30 % | 100 % | 100 % |
| Cascade SVM accuracy | 100 % | 100 % | 100 % |
| Sample-level grouped CV | 89.49 % | 99.92 % | 100 % |
| Borderline notes (Stage-2 band) | 7 | 1 | 1 |
| Mean \|Cohen's d\| | 0.70 | 3.87 | 5.24 |
| Largest \|Cohen's d\| | 1.31 (F1) | 5.74 (F1) | 8.84 (F2) |
| Smallest cross-class distance | 0.074 | 0.194 | 0.250 |
| Best-performing model | Cascade SVM | Linear SVM | Linear SVM |

The choice of region affects the system far more than the choice of classifier, and the mean
per-channel separability differs by a factor of five to seven. A large part of this is
geometric: a uniform region fills the field of view with the same material even under slight
misalignment, so the within-class variance collapses, whereas the fine printed stroke makes
every reading sensitive to the exact point sampled. The three regions also expose different
physical signatures: the ink-synthesis method on the purple stroke, the pigment formulation on
the yellow patch and the substrate on the white area. Per channel, the white area dominates in
F1–F3 and F8, the yellow patch in F4–F5, and the digit stroke is the least separable in every
channel.

### Classification from the photographs themselves

The cropped photograph the sensor was pointed at was kept for every note, so what the nine
channels add over the three colours the photograph already carries can be settled by
measurement. The mean colour over the sampled area is what an RGB camera would have returned;
the stored RGB values are linearised and divided by their sum, which reduces common
exposure-level variation as dividing by the Clear channel reduces common illumination-level
variation in the spectra.

| Features | Digit stroke | Yellow patch | White area |
|---|---|---|---|
| Nine channels, SNV (main pipeline) | 96.3 | 100 | 100 |
| Nine channels, Clear ratio | 90.7 | 100 | 100 |
| Three broad bands from the same nine | 83.3 | 100 | 100 |
| Three narrow channels F2, F5, F7 | 83.3 | 100 | 100 |
| Best single channel | 83.3 | 100 | 100 |
| Three colours of the photograph | **63.0** | 100 | 100 |

Both uniform regions are at ceiling, so only the digit stroke separates the feature sets.
Three broad bands synthesised from the sensor's own channels classify 83.3 % against 63.0 %
from the three colours of the photograph — 9 notes wrong against 20 — and going from those
bands to all nine channels raises 83.3 % to 90.7 %, 4 notes of 54. The result is a
representation-dependent difference in performance, not additional independent spectral
dimensions after the camera–display chain.

Two qualifications. Keeping the absolute level instead of normalising it away takes both the
photograph's colours and the nine channels to 94.4 %, but the level depends on the exposure
and the genuine notes were photographed as one batch, so that route separates the recording
sessions as much as the notes. And a linear model of the three image colours explains most of
every channel on the two uniform regions, median *R²* 0.89 and 0.87, except the near-infrared
channel, which is unpredictable from the photograph everywhere, consistent with the
camera–display chain retaining little independent near-infrared information.

## Additional figures

| Figure | File |
|---|---|
| Per-note spectra, all three classes | [`figures/appendix_E/fig1_per_note_spectra.png`](figures/appendix_E/fig1_per_note_spectra.png) |
| Class-mean spectra | [`figures/appendix_E/fig2_class_mean_comparison.png`](figures/appendix_E/fig2_class_mean_comparison.png) |
| Per-channel separability | [`figures/appendix_E/fig3_channel_separability.png`](figures/appendix_E/fig3_channel_separability.png) |
| Three-dimensional PCA of the AS7341 features | [`figures/appendix_E/fig4_pca_3d.png`](figures/appendix_E/fig4_pca_3d.png) |
| Channel contributions to PC1 | [`figures/appendix_E/fig5_pc1_contribution.png`](figures/appendix_E/fig5_pc1_contribution.png) |
| Cascade confusion matrix | [`figures/appendix_E/fig6_confusion_matrix.png`](figures/appendix_E/fig6_confusion_matrix.png) |
| Error rates of the compared classifiers | [`figures/appendix_E/fig7_classifier_fp_fn.png`](figures/appendix_E/fig7_classifier_fp_fn.png) |
| Per-note Stage-1 margin | [`figures/appendix_E/fig_20_margin.png`](figures/appendix_E/fig_20_margin.png) |
| Within-note scatter by class and region | [`figures/appendix_E/fig_condition_scatter.png`](figures/appendix_E/fig_condition_scatter.png) |
| Per-channel condition analysis | [`figures/appendix_E/fig_condition_channels.png`](figures/appendix_E/fig_condition_channels.png) |
| Per-channel separability of the three regions | [`figures/appendix_E/fig_region_separability.png`](figures/appendix_E/fig_region_separability.png) |

Magnified photographs of the stroke itself, and the photograph of the prop-note reverse, are
not included; see the note on banknote imagery in [`README.md`](README.md).

## Limitations

- The digit stroke was recorded on a **different set of notes** from the uniform regions, so
  the region effect is confounded with any difference between the two sets: what is compared
  is region-plus-sample rather than region alone. Three things argue against the confound —
  the sets are of the same denomination, type and origin; the gap is a factor of five to seven
  in mean separability; and it has a physical explanation that predicts its direction in
  advance. Measuring one set of notes at all three regions would remove it.
- The **cascade review threshold is exploratory**: half the median absolute Stage-1 margin over
  the whole note set rather than within each training fold. A deployable cascade would require
  the band to be calibrated on an independent training set before evaluation on unseen notes.
- The **621-point curve is a software reconstruction** from the same ten channel readings, not
  an independently measured 1 nm spectrum.
- The scatter cue is **specific to a counterfeit produced by halftone printing**, so a
  continuous-tone forgery would not show it; it measures print quality rather than
  authenticity. It also requires a fine printed feature, which is the reverse of the ranking
  obtained for mean spectra.

## Related scripts

| Script | Role |
|---|---|
| [`../../matlab/region_full.m`](../../matlab/region_full.m) | Per-region, per-route analysis |
| [`../../matlab/region_comparison.m`](../../matlab/region_comparison.m) | The three-region comparison |
| [`../../matlab/fullspectrum_nested.m`](../../matlab/fullspectrum_nested.m) | Nested cascade second stage and the all-note control |
| [`../../matlab/recovery_tests.m`](../../matlab/recovery_tests.m) | Borderline-note recovery |
| [`../../matlab/condition_analysis.m`](../../matlab/condition_analysis.m) | Within-note scatter and condition |
| [`../../matlab/rgb_vs_multispectral.m`](../../matlab/rgb_vs_multispectral.m), [`../../matlab/direct_vs_rgb.m`](../../matlab/direct_vs_rgb.m) | Photograph colours against sensor representations |
