# Appendix D — Evaluation of the first-generation counterfeits

Extended version of Appendix D of the thesis. The thesis retains the feasibility result, the
three-class comparison and the campaign caveat; everything below is the complete record.

## Purpose

Six colour-print play-money notes were bought before the current prop notes and were used
twice: once as the sample of a small feasibility study, and once as a third class in the main
campaign. Neither result bears on the authentication task as it is finally posed, since a
counterfeit that can be told from a genuine note by eye is not the case the instrument is
for. Both are recorded so that the earlier work is not lost.

## Dataset

- **First-generation (V1) counterfeits** — six children's play-money £20 notes, listed by the
  supplier as slightly smaller than real banknotes and printed single-sided.
- **Genuine notes** — the earlier genuine set used before the main campaign. This is *not* the
  27-note cohort of the main experiments, which matters for the comparison below.
- **Current prop notes** — the 30 notes of the digit-stroke campaign, for the three-class
  comparison only.
- **Region** — the printed "£20" numeral, the same region as the digit-stroke work of
  Appendix E.

## Method

The region was recorded under the fixed acquisition conditions used later and processed with
the Clear-channel normalisation, SNV transform and note-level averaging of Chapter 3 of the
thesis. Classification used the same leave-one-banknote-out protocol. For the three-class
task, because a support vector machine is inherently binary, the multiclass classifiers were
built with the error-correcting output codes (ECOC) framework.

## Full results

### Feasibility study

The V1 mean spectrum differs from the genuine notes most clearly at F2 (445 nm), where the
colour-printed purple lacks the blue-violet reflectance of the genuine ink. On the nine
averaged channels a single linear SVM separates the two classes with **100 % note-level
accuracy** under leave-one-banknote-out validation, with no overlap at all.

The pilot therefore established feasibility, but it also showed that these samples are too
easy for the final authentication task, which moved to the more realistic current prop notes
and from this single region to three.

### Three-class comparison

The six V1 notes were added as a third class, extending the task to genuine,
current-counterfeit and V1-counterfeit notes under the same leakage-free protocol with one
averaged spectrum per note.

| Classifier | Accuracy | Notes correct |
|---|---|---|
| Multiclass linear SVM | **95.0 %** | 57 / 60 |
| The other three (RBF SVM, *k*-NN, decision tree) | 88.3 – 93.3 % | — |

The multiclass linear SVM was the best of the four. The per-classifier breakdown of the
remaining three was not retained in the surviving result files, so only the range is stated
here; it is reported the same way in the thesis. No counterfeit of either generation was
accepted as genuine, and no SVM or *k*-NN classifier confused the two generations.

Against genuine notes under a binary linear SVM, the 6 V1 counterfeits are perfectly separable
at 100 %, whereas the 30 current counterfeits reach 96.3 %. Every error in the
current-counterfeit case is a genuine note rejected, so the limiting factor there is the
spread of the genuine class rather than the counterfeits.

Extending the two-stage cascade to the three-class task did not improve multiclass accuracy,
which stays at 93.3 % before and after the second stage, although the composition of the
errors improves slightly and no V1 note is ever labelled genuine.

### Margin analysis

The Stage-1 margin towards the true class, computed for every note together with its strongest
competing class, measures how closely each counterfeit imitates a genuine note. All six V1
counterfeits compete only with the current counterfeit class, whereas roughly half of the
current counterfeits have the genuine class as their nearest competitor, and the only negative
margin in the dataset belongs to Fake30 (−0.10). The current generation therefore imitates
genuine notes far more closely than the first; neither set represents a professional
counterfeit.

## Additional figures

| Figure | File |
|---|---|
| Per-note spectra of the V1 counterfeits and the genuine notes | [`figures/appendix_D/fig_v1_per_note_spectra.png`](figures/appendix_D/fig_v1_per_note_spectra.png) |
| Genuine against V1 counterfeits, binary linear SVM confusion matrix | [`figures/appendix_D/fig9a_real_vs_fakeV1_confusion.png`](figures/appendix_D/fig9a_real_vs_fakeV1_confusion.png) |
| Genuine against current counterfeits, binary linear SVM confusion matrix | [`figures/appendix_D/fig9b_real_vs_fake_confusion.png`](figures/appendix_D/fig9b_real_vs_fake_confusion.png) |

Photographs of the recognition region itself are not included; see the note on banknote
imagery in [`README.md`](README.md).

## Limitations

- The V1 and current-counterfeit binary results come from **different measurement campaigns**,
  the V1 result being the feasibility measurement on the earlier set of genuine notes. The
  comparison therefore shows the direction of the difference and is not a matched comparison.
- Six V1 notes is a small sample, and the notes are visibly unrealistic, so the 100 % figure
  says nothing about a counterfeit designed to pass inspection.
- Neither generation is a criminal counterfeit; both are lawful products required to differ
  from genuine currency in construction.

## Related scripts

| Script | Role |
|---|---|
| [`../../matlab/feasibility_v1_check.m`](../../matlab/feasibility_v1_check.m) | The feasibility study |
| [`../../matlab/banknotes.m`](../../matlab/banknotes.m) | Main classification pipeline, including the ECOC multiclass path |
| [`../../matlab/loadNoteSet.m`](../../matlab/loadNoteSet.m) | Feature pipeline: Clear ratio then SNV per spectrum |
