# Supplementary material

Extended versions of the supplementary experiments reported in Appendices D–F of the
MSc thesis *Multispectral Sensing for Banknote Authentication* (Imperial College London,
Department of Electrical and Electronic Engineering).

The thesis appendices retain the experimental rationale, the key quantitative results and
the limitations needed to support Chapters 5 and 6. The documents here carry the complete
secondary analyses: the full spectral plots, the principal-component outputs, the per-note
margins, the classifier-by-classifier comparisons and the extended discussion that the
thesis does not have room for.

## Map to the thesis

| Thesis appendix | Supplementary document | Subject |
|---|---|---|
| Appendix D | [`appendix_D_first_generation.md`](appendix_D_first_generation.md) | The first-generation (V1) play-money counterfeits: early feasibility study and the three-class comparison against the current prop notes |
| Appendix E | [`appendix_E_digit_stroke.md`](appendix_E_digit_stroke.md) | The printed £20 digit stroke: channel-wise comparison, PCA, classifier comparison, the two-stage cascade, within-note scatter, the three-region comparison and the photograph-colour comparison |
| Appendix F | [`appendix_F_position_sensitivity.md`](appendix_F_position_sensitivity.md) | Sensitivity to the sampled position and the single-reading test |

Each document is organised as **Purpose → Dataset → Method → Full results → Additional
figures → Limitations → Related scripts**.

## What is and is not included

Raw measurement files and cropped banknote images are not included; the supplementary
material documents the complete analysis and derived results. Specifically:

- **Included** — the complete written analysis, the MATLAB scripts under [`../../matlab/`](../../matlab/),
  the classifier settings, the summary tables, and derived statistical plots that contain no
  banknote imagery.
- **Not included** — the per-note CSV measurement files and any photograph or crop of a
  banknote. This is the same boundary the thesis states in Appendix B, and it is deliberate:
  the CSV files are tied to individually identified notes in the sample, and reproductions of
  a British currency note are restricted under the Forgery and Counterfeiting Act 1981.

Because of that boundary, the numbers reported in the thesis and here cannot be recomputed
from this repository alone. The scripts and the written record are provided so that the
method can be inspected and reimplemented, not so that the figures can be regenerated
byte-for-byte.

## Citing a fixed version

The repository version corresponding to the submitted thesis is identified by the release
tag used at submission. Cite that tag rather than the `main` branch, which continues to
change.
