function keep = pairedSubset(noteNames, folder)
% PAIREDSUBSET  Restrict the photographic campaign to the notes the direct
% campaign also covered, so that both routes describe identical material.
%
%   keep = pairedSubset(noteNames, folder)
%
% noteNames  string array of note names or CSV file names (case-insensitive,
%            extension optional)
% folder     the dataset path the names came from; the filter is applied only
%            to the yellow and white photographic campaigns
% keep       logical array, true for notes to retain
%
% WHY THESE NOTES. The photographic campaign recorded 27 genuine and 31
% counterfeit notes, Real1-Real27 and Fake1-Fake31. The direct campaign later
% re-recorded 20 and 30 of the SAME physical notes, namely Real1-Real20 and
% Fake1-Fake30. Reporting both routes on the same 20 + 30 notes therefore
% requires dropping Real21-Real27 and Fake31 from the photographic set.
%
% The notes dropped are fixed by which notes the direct campaign covered.
% They are NOT chosen by which ones leave a result unchanged: selecting on
% the outcome would invalidate every number computed afterwards. Whatever the
% remaining 50 notes give is what gets reported.
%
% NOT APPLIED to data_20 (the digit-stroke campaign), which is a different
% batch of banknotes that happens to reuse the names Real21-Real24; nor to
% data_aged, Fake_V1 or data_feasibility, whose names do not collide.

% DISABLED 2026-08-22 on the user's instruction ("回退到原来"): the photographic
% campaign is reported on all 27 + 31 notes again, as it was before. The list
% below is the only switch. To restrict both routes to the notes they share,
% restore it to:
%   ["real21","real22","real23","real24","real25","real26","real27","fake31"]
% and re-run banknotes.m (white, yellow), region_full.m for all four
% combinations, scatter_routes.m, condition_analysis.m and ageing_analysis.m.
DROP = strings(1, 0);

noteNames = string(noteNames);
keep = true(size(noteNames));

f = lower(string(folder));
f = strrep(f, "\", "/");
inScope = (contains(f, "data_white") || contains(f, "data_yellow")) ...
          && ~contains(f, "data_20");
if ~inScope
    return;
end

n = lower(noteNames);
n = regexprep(n, "\.csv$", "");
n = regexprep(n, "^v1", "");        % FakeV1 prefix, never in scope anyway
n = regexprep(n, "[\s\(\)]", "");   % "real (21)" -> "real21"

for i = 1:numel(n)
    keep(i) = ~any(DROP == n(i));
end
end
