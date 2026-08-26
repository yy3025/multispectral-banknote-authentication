clc; clearvars; close all;
rng(0);

%% =========================
% Is the full 380-1000 nm spectrum a usable alternative to the two-stage
% cascade on the digit-stroke region?
%
% An earlier exploratory run reduced the full spectrum by PCA and reported
% 100% leave-one-banknote-out accuracy at 10 components. That figure is not
% reportable: the number of components was chosen AFTER seeing the
% leave-one-out result, and the PCA basis was fitted on all notes including
% the held-out one. Both are forms of selection on the test data.
%
% This script re-runs the same idea under a protocol that removes both:
%
%   OUTER loop  : leave one banknote out (54 folds).
%   INNER loop  : within the 53 training notes only, a second leave-one-out
%                 chooses the number of PCA components from a candidate list
%                 (ties resolved in favour of the smaller model).
%   PCA         : refitted from scratch on the training notes of whichever
%                 loop is active, then applied to project the held-out note.
%
% The held-out note therefore influences neither the projection nor the
% choice of its dimensionality. The naive (non-nested) figure is computed
% alongside so that the size of the optimism can be quoted.
% =========================

regions = {
    "20",     "D:\project\data_20",     "Digit-20 stroke"
    "yellow", "D:\project\data_yellow", "Uniform yellow patch"
    "white",  "D:\project\data_white",  "Uniform white patch"
};
classOf    = ["Real", "Fake"];
nCompList  = [3 5 8 10 15 20];
outFolder  = "D:\project\Result\result_fullspectrum";
if ~exist(outFolder, "dir"), mkdir(outFolder); end

allNaive = table(); allNest = table(); allFold = table();
for rr = 1:size(regions, 1)
region   = regions{rr, 1};
regLabel = regions{rr, 3};
dataDirs = [fullfile(regions{rr, 2}, "real"), fullfile(regions{rr, 2}, "fake")];
fprintf("\n########## %s ##########\n", regLabel);

%% ---- build one full-spectrum row per banknote ---------------------------
noteName = strings(0, 1); noteClass = strings(0, 1); Xfull = [];
for f = 1:2
    files = dir(fullfile(dataDirs(f), "**", "*.csv"));
    for k = 1:numel(files)
        T = readtable(fullfile(files(k).folder, files(k).name), ...
            "FileType", "text", "Delimiter", ";", "VariableNamingRule", "preserve");
        vn = string(T.Properties.VariableNames);
        nmCols = vn(~cellfun(@isempty, regexp(vn, '^\d+ nm$', 'once')));
        if isempty(nmCols), continue; end
        Sp = table2array(T(:, cellstr(nmCols)));
        Sp = Sp(all(isfinite(Sp), 2), :);
        if isempty(Sp), continue; end
        Sp = (Sp - mean(Sp, 2)) ./ std(Sp, 0, 2);     % SNV per spectrum
        Xfull(end+1, :)  = mean(Sp, 1);               %#ok<AGROW>  per-note mean
        noteName(end+1)  = string(erase(files(k).name, ".csv"));   %#ok<AGROW>
        noteClass(end+1) = classOf(f);                             %#ok<AGROW>
    end
end
y = double(noteClass(:) == "Fake");
N = numel(y);
fprintf("Full-spectrum matrix: %d notes x %d wavelengths (%d Real / %d Fake)\n\n", ...
    size(Xfull, 1), size(Xfull, 2), sum(y == 0), sum(y == 1));

svmFit = @(Xt, yt) fitcsvm(Xt, yt, "KernelFunction", "linear", "Standardize", true);

%% ---- naive procedure, for comparison only -------------------------------
% PCA on ALL notes, then leave-one-out, then pick the best component count.
naive = nan(numel(nCompList), 1);
[~, scoreA] = pca(Xfull);
for c = 1:numel(nCompList)
    S = scoreA(:, 1:nCompList(c));
    pr = nan(N, 1);
    for i = 1:N
        tr = true(N, 1); tr(i) = false;
        pr(i) = predict(svmFit(S(tr, :), y(tr)), S(i, :));
    end
    naive(c) = mean(pr == y) * 100;
    fprintf("  naive (PCA on all notes), %2d PCs : %.2f%%\n", nCompList(c), naive(c));
end
fprintf("  naive best-of-list              : %.2f%%  <- NOT a valid estimate\n\n", max(naive));

%% ---- nested cross-validation --------------------------------------------
predOuter = nan(N, 1);
chosen    = nan(N, 1);
tic;
for i = 1:N
    trIdx = setdiff(1:N, i);
    Xtr = Xfull(trIdx, :); ytr = y(trIdx);
    nTr = numel(trIdx);

    % --- inner leave-one-out over the training notes only ----------------
    innerAcc = zeros(numel(nCompList), 1);
    for j = 1:nTr
        inTr = setdiff(1:nTr, j);
        mu   = mean(Xtr(inTr, :), 1);
        cf   = pca(Xtr(inTr, :) - mu, "NumComponents", max(nCompList));
        Ztr  = (Xtr(inTr, :) - mu) * cf;
        Zte  = (Xtr(j, :)     - mu) * cf;
        for c = 1:numel(nCompList)
            nc = nCompList(c);
            p  = predict(svmFit(Ztr(:, 1:nc), ytr(inTr)), Zte(:, 1:nc));
            innerAcc(c) = innerAcc(c) + (p == ytr(j));
        end
    end
    innerAcc = innerAcc / nTr;
    best = find(innerAcc == max(innerAcc), 1, "first");   % ties -> fewest components
    nc   = nCompList(best);
    chosen(i) = nc;

    % --- outer fold, using the component count chosen inside -------------
    mu = mean(Xtr, 1);
    cf = pca(Xtr - mu, "NumComponents", nc);
    Ztr = (Xtr - mu) * cf;
    Zte = (Xfull(i, :) - mu) * cf;
    predOuter(i) = predict(svmFit(Ztr, ytr), Zte);
end
t = toc;

accNested = mean(predOuter == y) * 100;
fp = sum(predOuter == 1 & y == 0) / sum(y == 0) * 100;
fn = sum(predOuter == 0 & y == 1) / sum(y == 1) * 100;
wrong = noteName(predOuter ~= y);

fprintf("Nested CV finished in %.0f s\n", t);
fprintf("  NESTED leave-one-banknote-out accuracy : %.2f%%\n", accNested);
fprintf("  false positives (Real->Fake)           : %.2f%%\n", fp);
fprintf("  false negatives (Fake->Real)           : %.2f%%\n", fn);
if isempty(wrong)
    fprintf("  every note classified correctly\n");
else
    fprintf("  misclassified: %s\n", strjoin(wrong, ", "));
end
fprintf("  components chosen by the inner loop    : ");
u = unique(chosen);
for k = 1:numel(u), fprintf("%d(x%d) ", u(k), sum(chosen == u(k))); end
fprintf("\n  optimism of the naive procedure        : %.2f percentage points\n\n", ...
    max(naive) - accNested);

%% ---- collect -------------------------------------------------------------
reg = repmat(string(region), numel(nCompList), 1);
allNaive = [allNaive; table(reg, repmat(string(regLabel), numel(nCompList), 1), ...
    nCompList(:), naive, 'VariableNames', ...
    {'Region', 'RegionLabel', 'PCAComponents', 'NaiveLOOAccPct'})];        %#ok<AGROW>
allNest = [allNest; table(string(region), string(regLabel), N, accNested, ...
    max(naive), max(naive) - accNested, fp, fn, numel(wrong), ...
    strjoin(string(u'), "/"), strjoin(wrong, " "), 'VariableNames', ...
    {'Region', 'RegionLabel', 'Notes', 'NestedAccPct', 'NaiveBestPct', ...
     'OptimismPts', 'FalsePositivePct', 'FalseNegativePct', 'NumErrors', ...
     'ComponentsChosen', 'MisclassifiedNotes'})];                          %#ok<AGROW>
allFold = [allFold; table(repmat(string(region), N, 1), noteName(:), noteClass(:), ...
    chosen, predOuter, predOuter == y, 'VariableNames', ...
    {'Region', 'Note', 'Class', 'ComponentsChosen', 'Predicted', 'Correct'})]; %#ok<AGROW>
end   % region loop

fprintf("\n================ SUMMARY ================\n");
disp(allNest(:, {'RegionLabel','Notes','NestedAccPct','NaiveBestPct','OptimismPts', ...
                 'FalsePositivePct','FalseNegativePct','MisclassifiedNotes'}));
writetable(allNaive, fullfile(outFolder, "fullspectrum_naive.csv"));
writetable(allNest,  fullfile(outFolder, "fullspectrum_nested.csv"));
writetable(allFold,  fullfile(outFolder, "fullspectrum_folds.csv"));
fprintf("Saved to %s\n", outFolder);
