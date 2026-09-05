# Appendix F — Sensitivity to the sampled position

Extended version of Appendix F of the thesis. The thesis retains the comparison between the
uniform regions and the digit stroke, the single-reading result and the placement limitation;
this document carries the full numbers.

## Purpose

The repeated readings of the classification and scatter experiments were taken at different
positions within each target region, so the same data quantify sensitivity to the sampled
position without a separate experiment. They support two statements made in the main text:
that a uniform region tolerates within-region placement variation over the offsets tested, and
that the within-note scatter arises from sampling different positions rather than from
repeatedly measuring one point.

## Dataset

The two uniform regions are taken on the direct route; the digit stroke exists only on the
photographic route, so that part of the comparison crosses routes and shows the direction and
scale of the region effect rather than a matched comparison.

| Region and route | Notes | Readings | Repeats per note |
|---|---|---|---|
| White area, direct | 58 | 1233 | 19–29 |
| Yellow patch, direct | 58 | 936 | 13–20 |
| White area, photographic | 58 | 1365 | 13–37 |
| Yellow patch, photographic | 58 | 1319 | 18–32 |

## Method

Two measures are used. The first is the within-note scatter, the square root of the mean over
the nine channels of the variance over a note's repeated readings, computed on SNV-normalised
features and reported both raw and repeat-matched. The second is a cross-validation at the
level of individual readings rather than note means: because each measurement is at a
different position, that gives the accuracy obtainable from a single reading at one position
inside the region. Whole notes are held out, so no note contributes readings to both the
training and the test partition.

## Full results

### Position-related variation by region

| Region and route | Genuine scatter | Prop scatter |
|---|---|---|
| White area, direct | 0.0076 | 0.0282 |
| Yellow patch, direct | 0.0053 | 0.0233 |
| Printed digit stroke, photographic | 0.056 | 0.174 |

Values are in SNV units. Position-related variation on the printed digit stroke is about an
**order of magnitude larger** than on either uniform region, for both classes.

### Single-reading test

A note-grouped five-fold validation over the individual direct-route readings classifies
**all 1233 white-area readings and all 936 yellow-patch readings correctly**, matching the
note-level result. The digit stroke falls from 96.3 % note-level accuracy to **89.5 %** when a
single position is used.

The results therefore suggest that a single-reading implementation may be feasible on the
tested uniform regions, but not on the fine printed stroke, where averaging is what makes the
region usable at all.

### Relation to note condition

The point estimates of the condition analysis are consistent with wear increasing
position-dependent scatter, but no association between that sensitivity and the classification
decision was detected on the uniform regions.

## Limitations

- The step between positions was **not calibrated in millimetres**, so no placement tolerance
  can be quoted in physical units.
- **Note rotation was not tested.**
- Every sampled position stayed **inside the selected region**, so the result is a
  within-region sensitivity result and not a tolerance to crossing a region boundary.
- The digit-stroke comparison crosses measurement routes, as noted above.

## Related scripts

| Script | Role |
|---|---|
| [`../../matlab/alignment_analysis.m`](../../matlab/alignment_analysis.m) | Position sensitivity and the single-reading grouped cross-validation |
| [`../../matlab/condition_analysis.m`](../../matlab/condition_analysis.m) | Within-note scatter and the repeat-matched control |
| [`../../matlab/loadNoteSet.m`](../../matlab/loadNoteSet.m) | Feature pipeline shared with the main experiments |
