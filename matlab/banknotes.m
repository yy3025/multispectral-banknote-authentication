clc; clearvars; close all;

% Every figure below is scaled down when it is placed in the report, so the
% default 10 pt axes font ends up at only 4-5 pt on the printed page. Raising
% the default here (rather than per figure) makes the whole figure set land at
% roughly 8 pt on paper. Figures that set FontSize explicitly (the two margin
% charts) are unaffected. See saveFigure for the export resolution.
set(groot, "defaultAxesFontSize", 12);

%% =========================
% 1. Folder paths and options
% =========================

% Measurement region on the note (professor's region-sensitivity request):
%   "20"     = thick stroke at the base of the digit "2" in the printed
%              "GBP20" marking (original dataset, purple ink block)
%   "yellow" = uniform yellow colour-patch area (second region)
%   "white"  = uniform white / unprinted paper area (third region)
% Select via the BANKNOTE_REGION environment variable before starting
% MATLAB, e.g. PowerShell:
%   $env:BANKNOTE_REGION="yellow"; matlab -batch "run('D:\project\matlab\banknotes.m')"
% No env var = "20", the original behaviour. Each region writes to its own
% result folder so runs never overwrite each other.
region = string(getenv("BANKNOTE_REGION"));
if strlength(region) == 0, region = "20"; end

% Each class lives in its own folder tree. To add or remove banknotes later,
% just drop CSV files anywhere inside (or delete them from) these folders.
% Discovery is recursive, so it does not matter whether the files sit in a
% "CSV", "data" or any other subfolder. No code change is required.
% Columns: {folder, class name, note-name prefix}. FakeV1 holds the ORIGINAL
% six colour-print fakes from the first experiment; its files are also named
% Fake1..Fake6, so the "V1" prefix keeps note names unique across classes.
% regionLabel is the human-readable name used in figure titles; it matches
% the column names in region_comparison.m exactly.
switch region
    case "20"
        regionLabel  = "Digit-20 stroke (purple ink)";
        dataFolder   = "D:\project\data_20";
        resultFolder = "D:\project\Result\result_20";
        classFolders = {
            fullfile(dataFolder, "real"),      "Real",   "";
            fullfile(dataFolder, "fake"),      "Fake",   "";
            fullfile("D:\project", "Fake_V1"), "FakeV1", "V1"
        };
    case "yellow"
        regionLabel  = "Uniform yellow patch";
        dataFolder   = "D:\project\data_yellow";
        resultFolder = "D:\project\Result\result_yellow";
        % The FakeV1 notes were only ever measured on the "20" region, so
        % the yellow-patch run is binary Real vs Fake.
        classFolders = {
            fullfile(dataFolder, "real"), "Real", "";
            fullfile(dataFolder, "fake"), "Fake", ""
        };
    case "white"
        regionLabel  = "Uniform white patch";
        dataFolder   = "D:\project\data_white";
        resultFolder = "D:\project\Result\result_white";
        % Binary Real vs Fake, for the same reason as the yellow region.
        classFolders = {
            fullfile(dataFolder, "real"), "Real", "";
            fullfile(dataFolder, "fake"), "Fake", ""
        };
    otherwise
        error("Unknown BANKNOTE_REGION ""%s"" (expected ""20"", ""yellow"" or ""white"").", region);
end

fprintf("Measurement region: %s (%s)  (data: %s)\n", region, regionLabel, dataFolder);

classList   = string(classFolders(:, 2));
classColors = [0.00 0.45 0.74;    % Real   - blue
               0.85 0.33 0.10;    % Fake   - red-orange
               0.49 0.18 0.56];   % FakeV1 - purple

% --- Analysis options -----------------------------------------------------
% The LED is always OFF during measurement, so LED filtering is permanently
% disabled. Do NOT turn this on for the current data.
useLEDFilter = false;

% SNV (Standard Normal Variate): per-spectrum shape normalization. It removes
% overall brightness, which is exactly the nuisance here: real notes look
% lighter where the purple is worn, and the colour-synthesised fake reflects
% with inconsistent intensity. After SNV the classifier compares spectral
% SHAPE (which pigment / ink mix) instead of how bright the reading is.
applySNV = true;

if applySNV
    yLab     = "SNV-normalized value";
    normTag  = "Clear-ratio + SNV";
else
    yLab     = "Normalized value (ratio to Clear)";
    normTag  = "Clear-ratio";
end

if ~exist(dataFolder, "dir")
    error("Data folder does not exist: %s", dataFolder);
end

% Refresh the result folder: keep only the newest run by clearing old
% outputs before writing the current ones.
if ~exist(resultFolder, "dir")
    mkdir(resultFolder);
else
    oldOut = [dir(fullfile(resultFolder, "*.csv")); ...
              dir(fullfile(resultFolder, "*.png")); ...
              dir(fullfile(resultFolder, "*.xlsx"))];
    for q = 1:numel(oldOut)
        delete(fullfile(oldOut(q).folder, oldOut(q).name));
    end
    if ~isempty(oldOut)
        fprintf("Cleared %d old output file(s) in %s\n", numel(oldOut), resultFolder);
    end
end

featureNames = ["F1_Clear", "F2_Clear", "F3_Clear", "F4_Clear", ...
                "F5_Clear", "F6_Clear", "F7_Clear", "F8_Clear", "NIR_Clear"];

channelLabels = ["F1 415nm", "F2 445nm", "F3 480nm", "F4 515nm", ...
                 "F5 555nm", "F6 590nm", "F7 630nm", "F8 680nm", "NIR"];


%% =========================
% 2. Discover all CSV files (dynamic, add/remove friendly)
% =========================

% files columns: {full path, note name, class name}
files = cell(0, 3);

for c = 1:size(classFolders, 1)
    folder    = classFolders{c, 1};
    className = string(classFolders{c, 2});
    prefix    = string(classFolders{c, 3});

    if ~exist(folder, "dir")
        warning("Class folder not found, skipping: %s", folder);
        continue;
    end

    % Recursive search: finds *.csv in this folder and any subfolder.
    listing = dir(fullfile(folder, "**", "*.csv"));
    listing = listing(~[listing.isdir]);

    if isempty(listing)
        warning("No CSV files found under %s", folder);
        continue;
    end

    % Keep the photographic yellow/white campaigns to the same 20 + 30 notes
    % the direct campaign covered; no effect on the digit-stroke or V1 sets.
    listing = listing(pairedSubset(erase(string({listing.name}), ".csv"), folder));
    if isempty(listing)
        warning("No CSV files left under %s after the paired-subset filter", folder);
        continue;
    end

    order   = naturalSortOrder(string({listing.name}));
    listing = listing(order);

    for k = 1:numel(listing)
        fp = fullfile(listing(k).folder, listing(k).name);
        [~, noteName] = fileparts(string(listing(k).name));
        noteName = prefix + noteName;
        files(end + 1, :) = {char(fp), char(noteName), char(className)}; %#ok<SAGROW>
    end
end

if isempty(files)
    error("No CSV files were discovered under %s", dataFolder);
end

fprintf("Discovered %d banknote files (%d classes). Features: %s.\n\n", ...
    size(files, 1), size(classFolders, 1), normTag);


%% =========================
% 3. Read and process all files
% =========================

allX         = [];
allY         = [];
allNoteName  = strings(0, 1);
allClassName = strings(0, 1);
allNoteIdx   = [];                 % sample -> note index (for grouped CV)

numNotes     = size(files, 1);
noteMean     = nan(numNotes, numel(featureNames));
noteStd      = nan(numNotes, numel(featureNames));
noteFullMean = [];                 % per-note mean of full 380-1000 nm spectrum
wlFull       = [];                 % wavelength axis for the full spectrum
noteNames    = strings(numNotes, 1);
classNames   = strings(numNotes, 1);
sampleCounts = zeros(numNotes, 1);

for i = 1:numNotes

    filePath  = files{i, 1};
    noteName  = string(files{i, 2});
    className = string(files{i, 3});

    if ~isfile(filePath)
        error("Cannot find file: %s", filePath);
    end

    [X_one, ~, ~, Xfull_one, wl] = readAS7341Normalized(filePath, useLEDFilter);

    if isempty(X_one)
        warning("No valid data found in %s, note skipped.", filePath);
        continue;
    end

    if applySNV
        X_one = applySNVrows(X_one);
        if ~isempty(Xfull_one), Xfull_one = applySNVrows(Xfull_one); end
    end

    n = size(X_one, 1);

    % Numeric label = position in classList - 1 (Real=0, Fake=1, FakeV1=2).
    Y_one = repmat(find(classList == className) - 1, n, 1);

    allX         = [allX; X_one];                           %#ok<AGROW>
    allY         = [allY; Y_one];                           %#ok<AGROW>
    allNoteName  = [allNoteName; repmat(noteName, n, 1)];   %#ok<AGROW>
    allClassName = [allClassName; repmat(className, n, 1)]; %#ok<AGROW>
    allNoteIdx   = [allNoteIdx; repmat(i, n, 1)];           %#ok<AGROW>

    noteMean(i, :) = mean(X_one, 1, "omitnan");
    noteStd(i, :)  = std(X_one, 0, 1, "omitnan");

    % Accumulate the per-note mean of the full high-resolution spectrum.
    if ~isempty(Xfull_one)
        if isempty(noteFullMean)
            noteFullMean = nan(numNotes, size(Xfull_one, 2));
            wlFull       = wl;
        end
        if size(Xfull_one, 2) == size(noteFullMean, 2)
            noteFullMean(i, :) = mean(Xfull_one, 1, "omitnan");
        end
    end

    noteNames(i)    = noteName;
    classNames(i)   = className;
    sampleCounts(i) = n;
end

% Drop any notes that produced no valid samples.
validNote    = sampleCounts > 0;
noteMean     = noteMean(validNote, :);
noteStd      = noteStd(validNote, :);
noteNames    = noteNames(validNote);
classNames   = classNames(validNote);
sampleCounts = sampleCounts(validNote);
if ~isempty(noteFullMean)
    noteFullMean = noteFullMean(validNote, :);
end

remap                  = zeros(numNotes, 1);
remap(find(validNote)) = 1:nnz(validNote); %#ok<FNDSB>
allNoteIdx             = remap(allNoteIdx);
numNotes               = nnz(validNote);

X = allX;
Y = allY;

for c = 1:numel(classList)
    fprintf("%s notes: %d (%d samples)\n", classList(c), ...
        sum(classNames == classList(c)), sum(allClassName == classList(c)));
end
fprintf("Total notes: %d, total samples: %d\n\n", numNotes, size(X, 1));


%% =========================
% 4. Save sample-level and per-note (averaged) datasets
% =========================

cleanTable           = array2table(X, "VariableNames", cellstr(featureNames));
cleanTable.Label     = Y;
cleanTable.ClassName = allClassName;
cleanTable.NoteName  = allNoteName;
writetable(cleanTable, fullfile(resultFolder, "banknote_dataset.csv"));

% Per-note mean spectrum: one robust, denoised row per banknote. This is the
% "use the average of the measurements" representation.
noteMeanTable           = array2table(noteMean, "VariableNames", cellstr(featureNames));
noteMeanTable.Note      = noteNames(:);
noteMeanTable.Class     = classNames(:);
noteMeanTable.Samples   = sampleCounts(:);
noteMeanTable = movevars(noteMeanTable, {'Note', 'Class', 'Samples'}, "Before", 1);
writetable(noteMeanTable, fullfile(resultFolder, "banknote_note_mean_spectra.csv"));

fprintf("Sample-level and per-note mean datasets saved to:\n%s\n\n", resultFolder);


%% =========================
% 5. Per-note summary table (mean +/- std per channel)
% =========================

summaryTable = table(noteNames(:), classNames(:), sampleCounts(:), ...
    'VariableNames', {'Note', 'Class', 'Samples'});

for k = 1:numel(featureNames)
    summaryTable.("Mean_" + featureNames(k)) = noteMean(:, k);
    summaryTable.("Std_"  + featureNames(k)) = noteStd(:, k);
end

writetable(summaryTable, fullfile(resultFolder, "banknote_summary.csv"));


%% =========================
% 6. Pairwise distance between note mean spectra
% =========================

pairA        = strings(0, 1);
pairB        = strings(0, 1);
pairDistance = [];
nDuplicate   = 0;

pairType    = strings(0, 1);
pairIsCross = false(0, 1);

for i = 1:size(noteMean, 1)
    for j = i+1:size(noteMean, 1)
        d = norm(noteMean(i, :) - noteMean(j, :));

        pairA        = [pairA; noteNames(i)];   %#ok<AGROW>
        pairB        = [pairB; noteNames(j)];   %#ok<AGROW>
        pairDistance = [pairDistance; d];       %#ok<AGROW>

        pairType    = [pairType; classNames(i) + "-" + classNames(j)];   %#ok<AGROW>
        pairIsCross = [pairIsCross; classNames(i) ~= classNames(j)];     %#ok<AGROW>

        if d < 1e-6
            nDuplicate = nDuplicate + 1;
            warning("%s and %s have almost identical mean spectra. Check for duplicated data.", ...
                noteNames(i), noteNames(j));
        end
    end
end

pairwiseDistanceTable = table(pairA, pairB, pairType, pairDistance, ...
    'VariableNames', {'NoteA', 'NoteB', 'PairType', 'EuclideanDistance'});
writetable(pairwiseDistanceTable, fullfile(resultFolder, "banknote_pairwise_mean_distance.csv"));

% --- Closest cross-class pairs (professor's request #1) ------------------
% Cross-class pairs with the SMALLEST spectral distance are the hardest to
% tell apart. With three classes the PairType column tells which two classes
% each pair belongs to (Real-Fake, Real-FakeV1, Fake-FakeV1).
crossTable      = pairwiseDistanceTable(pairIsCross, :);
crossTable      = sortrows(crossTable, "EuclideanDistance", "ascend");
writetable(crossTable, fullfile(resultFolder, "closest_cross_class_pairs.csv"));

% For each non-Real note, its nearest Real note: ranks how real-like each
% fake is (both the current fakes and the old V1 fakes).
fakeIdx = find(classNames ~= "Real");
realIdx = find(classNames == "Real");
nearReal     = strings(numel(fakeIdx), 1);
nearRealDist = zeros(numel(fakeIdx), 1);
for a = 1:numel(fakeIdx)
    dists = vecnorm(noteMean(realIdx, :) - noteMean(fakeIdx(a), :), 2, 2);
    [nearRealDist(a), b] = min(dists);
    nearReal(a) = noteNames(realIdx(b));
end
fakeNearestRealTable = table(noteNames(fakeIdx), classNames(fakeIdx), nearReal, nearRealDist, ...
    'VariableNames', {'FakeNote', 'FakeClass', 'NearestRealNote', 'Distance'});
fakeNearestRealTable = sortrows(fakeNearestRealTable, "Distance", "ascend");
writetable(fakeNearestRealTable, fullfile(resultFolder, "fake_nearest_real.csv"));

fprintf("Pairwise distances saved (%d pairs, %d near-duplicates).\n", ...
    height(pairwiseDistanceTable), nDuplicate);
fprintf("Closest cross-class pairs (hardest to separate):\n");
disp(crossTable(1:min(5, height(crossTable)), :));
fprintf("Most real-like fakes (nearest real note):\n");
disp(fakeNearestRealTable(1:min(5, height(fakeNearestRealTable)), :));
fprintf("\n");


%% =========================
% 7. Class-level mean and difference analysis
% =========================

% Per-class sample-level mean and std (used by the figures below).
nClass     = numel(classList);
classMeanX = zeros(nClass, numel(featureNames));
classStdX  = zeros(nClass, numel(featureNames));
classNsamp = zeros(nClass, 1);
for c = 1:nClass
    m = allClassName == classList(c);
    classMeanX(c, :) = mean(X(m, :), 1, "omitnan");
    classStdX(c, :)  = std(X(m, :), 0, 1, "omitnan");
    classNsamp(c)    = sum(m);
end

% Pairwise Cohen's d for EVERY pair of classes. |d| ranks how separable each
% channel is once brightness is removed, which matters more than the raw
% difference when the within-class spread is large.
pairList  = nchoosek(1:nClass, 2);
nPair     = size(pairList, 1);
pairNames = strings(nPair, 1);
dMatrix   = zeros(numel(featureNames), nPair);   % channel x class pair, signed d

analysisTable = table();
for p = 1:nPair
    a = pairList(p, 1); b = pairList(p, 2);
    pairNames(p) = classList(a) + " vs " + classList(b);

    mA = classMeanX(a, :); mB = classMeanX(b, :);
    sA = classStdX(a, :);  sB = classStdX(b, :);
    nA = classNsamp(a);    nB = classNsamp(b);

    pooledStd = sqrt(((nA - 1) * sA.^2 + (nB - 1) * sB.^2) ./ (nA + nB - 2));
    dP        = (mB - mA) ./ pooledStd;
    diffP     = mB - mA;
    dMatrix(:, p) = dP(:);

    Tp = table(repmat(pairNames(p), numel(featureNames), 1), ...
        featureNames(:), channelLabels(:), mA(:), mB(:), sA(:), sB(:), ...
        diffP(:), abs(diffP(:)), dP(:), ...
        'VariableNames', {'Pair', 'Feature', 'Channel', 'MeanA', 'MeanB', ...
        'StdA', 'StdB', 'BMinusA', 'AbsDifference', 'CohenD'});
    analysisTable = [analysisTable; Tp]; %#ok<AGROW>
end

analysisTable = sortrows(analysisTable, "CohenD", "descend", "ComparisonMethod", "abs");

disp("Channel difference analysis (all class pairs), sorted by |Cohen's d|:");
disp(analysisTable);

writetable(analysisTable, fullfile(resultFolder, "banknote_channel_difference_analysis.csv"));
fprintf("Channel difference analysis saved.\n\n");


%% =========================
% 8. Figure 1: per-note mean spectra coloured by class
% =========================

fig1 = figure;
hold on;

firstH = gobjects(nClass, 1);
for i = 1:size(noteMean, 1)
    c = find(classList == classNames(i));
    h = plot(1:9, noteMean(i, :), '-', "Color", [classColors(c, :) 0.30], "LineWidth", 1.0);
    if ~isgraphics(firstH(c)), firstH(c) = h; end
end

meanH = gobjects(nClass, 1);
for c = 1:nClass
    meanH(c) = plot(1:9, classMeanX(c, :), '-o', "Color", classColors(c, :), ...
        "LineWidth", 2.4, "MarkerFaceColor", classColors(c, :));
end

xlabel("AS7341 Channel"); ylabel(yLab);
title("Per-Note Mean Spectra and Class Means");
xticks(1:9); xticklabels(channelLabels); xtickangle(45); xlim([1 9]); grid on;

legHandles = gobjects(0);
legLabels  = strings(0, 1);
for c = 1:nClass
    if isgraphics(firstH(c))
        legHandles(end+1) = firstH(c);                    %#ok<AGROW>
        legLabels(end+1)  = classList(c) + " notes";      %#ok<AGROW>
    end
    legHandles(end+1) = meanH(c);                         %#ok<AGROW>
    legLabels(end+1)  = classList(c) + " mean";           %#ok<AGROW>
end
legend(legHandles, legLabels, "Location", "northoutside", ...
    "Orientation", "horizontal", "NumColumns", 3, "FontSize", 9);
hold off;

saveFigure(fig1, fullfile(resultFolder, "fig1_per_note_spectra.png"));


%% =========================
% 9. Figure 2: class mean comparison with error bars
% =========================

fig2 = figure;
hold on;
for c = 1:nClass
    errorbar(1:9, classMeanX(c, :), classStdX(c, :), '-o', "Color", classColors(c, :), ...
        "LineWidth", 1.5, "MarkerSize", 6, "DisplayName", classList(c) + " mean +/- std");
end
xlabel("AS7341 Channel"); ylabel(yLab);
title("Class Mean Spectral Comparison");
xticks(1:9); xticklabels(channelLabels); xtickangle(45); xlim([1 9]); grid on;
legend("Location", "northoutside", "Orientation", "horizontal");
hold off;

saveFigure(fig2, fullfile(resultFolder, "fig2_class_mean_comparison.png"));


%% =========================
% 10. Figure 3: separability (|Cohen's d|) per channel
% =========================

fig3 = figure;
bar(abs(dMatrix));   % one group per channel, one bar per class pair
xlabel("AS7341 Channel"); ylabel("|Cohen's d| (separability)");
title("Channel Separability for Each Class Pair");
xticks(1:9); xticklabels(channelLabels); xtickangle(45); grid on;
legend(cellstr(pairNames), "Location", "northoutside", "Orientation", "horizontal");

saveFigure(fig3, fullfile(resultFolder, "fig3_channel_separability.png"));


%% =========================
% 11. PCA calculation (z-scored channels)
% =========================

mu    = mean(X, 1);
sigma = std(X, 0, 1);
sigma(sigma == 0) = eps;

Xz         = (X - mu) ./ sigma;
X_centered = Xz - mean(Xz, 1);

[U, S, V] = svd(X_centered, "econ");

score     = U * S;
latent    = diag(S).^2 / (size(X_centered, 1) - 1);
explained = latent / sum(latent) * 100;


%% =========================
% 12. Save PCA tables
% =========================

numPC  = numel(explained);
PCName = "PC" + (1:numPC)';
pcaExplainedTable = table(PCName, explained(:), cumsum(explained(:)), ...
    'VariableNames', {'PrincipalComponent', 'ExplainedVariancePercent', 'CumulativeExplainedVariancePercent'});
writetable(pcaExplainedTable, fullfile(resultFolder, "PCA_explained_variance.csv"));

nPCsave = min(3, numPC);
pcaScoreTable = array2table(score(:, 1:nPCsave), "VariableNames", "PC" + (1:nPCsave));
pcaScoreTable.Label     = Y;
pcaScoreTable.ClassName = allClassName;
pcaScoreTable.NoteName  = allNoteName;
writetable(pcaScoreTable, fullfile(resultFolder, "PCA_scores.csv"));

coeff = V;
loadingTable = array2table(coeff(:, 1:nPCsave), "VariableNames", "PC" + (1:nPCsave), ...
    "RowNames", cellstr(featureNames));
writetable(loadingTable, fullfile(resultFolder, "PCA_loading.csv"), "WriteRowNames", true);

fprintf("PCA tables saved. Variance PC1-PC3: %.1f%% + %.1f%% + %.1f%% = %.1f%%\n\n", ...
    explained(1), explained(2), explained(3), sum(explained(1:3)));


%% =========================
% 13. Figure 4: 3D PCA visualization
% =========================

fig4 = figure;
hold on;
for c = 1:nClass
    m = allClassName == classList(c);
    scatter3(score(m, 1), score(m, 2), score(m, 3), 60, classColors(c, :), ...
        "filled", "DisplayName", classList(c));
end
xlabel(sprintf("PC1 (%.1f%%)", explained(1)));
ylabel(sprintf("PC2 (%.1f%%)", explained(2)));
zlabel(sprintf("PC3 (%.1f%%)", explained(3)));
title(sprintf("3D PCA (%s)\nPC1 + PC2 + PC3 = %.1f%%", normTag, sum(explained(1:3))));
grid on; legend("Location", "best"); view(45, 25); rotate3d on;
hold off;

saveFigure(fig4, fullfile(resultFolder, "fig4_pca_3d.png"));


%% =========================
% 14. Figure 5: PC1 channel contribution
% =========================

pc1ContributionPercent = coeff(:, 1).^2 ./ sum(coeff(:, 1).^2) * 100;
pc1ContributionTable = table(featureNames(:), channelLabels(:), coeff(:, 1), ...
    abs(coeff(:, 1)), pc1ContributionPercent(:), ...
    'VariableNames', {'Feature', 'Channel', 'PC1Loading', 'AbsPC1Loading', 'ContributionToPC1Percent'});
pc1ContributionTable = sortrows(pc1ContributionTable, "ContributionToPC1Percent", "descend");
writetable(pc1ContributionTable, fullfile(resultFolder, "PCA_PC1_channel_contribution.csv"));

fig5 = figure;
bar(pc1ContributionPercent);
xlabel("AS7341 Channel"); ylabel("Contribution to PC1 (%)");
title("Percentage Contribution of AS7341 Channels to PC1");
xticks(1:9); xticklabels(channelLabels); xtickangle(45); grid on;

saveFigure(fig5, fullfile(resultFolder, "fig5_pc1_contribution.png"));


%% =========================
% 14b. Three-class discrimination: Real vs Fake (V2) vs FakeV1
%
% The Fake_V1 folder holds the ORIGINAL six colour-print fakes from the
% first experiment. This section checks whether the sensor separates all
% THREE groups at once: genuine notes, the current realistic fakes, and the
% old fakes. Same leakage-free protocol as the binary pipeline: one averaged
% spectrum per note, leave-one-note-out CV, multiclass (ECOC) classifiers.
% =========================

if exist("fitcecoc", "file") == 2 && numel(unique(classNames)) >= 3

    fprintf("Running three-class (Real / Fake / FakeV1) LOO classification...\n");

    noteClass3 = zeros(numNotes, 1);
    for c = 1:nClass
        noteClass3(classNames == classList(c)) = c - 1;   % Real=0, Fake=1, FakeV1=2
    end

    methods3 = {
        "Linear SVM (ECOC)", @(Xt,Yt) fitcecoc(Xt, Yt, "Learners", ...
                               templateSVM("KernelFunction", "linear", "Standardize", true));
        "RBF SVM (ECOC)",    @(Xt,Yt) fitcecoc(Xt, Yt, "Learners", ...
                               templateSVM("KernelFunction", "rbf", "Standardize", true, ...
                               "KernelScale", "auto", "BoxConstraint", 1));
        "k-NN (k=3)",        @(Xt,Yt) fitcknn(Xt, Yt, "NumNeighbors", 3, "Standardize", true);
        "Decision Tree",     @(Xt,Yt) fitctree(Xt, Yt)
    };

    nm3      = size(methods3, 1);
    name3    = strings(nm3, 1);
    acc3     = zeros(nm3, 1);
    bal3     = zeros(nm3, 1);
    recall3  = zeros(nm3, nClass);   % per-class recall
    missFake3 = zeros(nm3, 1);       % any fake accepted as Real (worst error)
    falseAl3  = zeros(nm3, 1);       % Real rejected as some fake
    v1v2mix3  = zeros(nm3, 1);       % V1 <-> V2 confusion (not a security error)
    predAll3  = nan(numNotes, nm3);

    for m = 1:nm3
        pred = looNotePredict(methods3{m, 2}, noteMean, noteClass3);
        predAll3(:, m) = pred;
        ok = ~isnan(pred);
        yt = noteClass3(ok); yp = pred(ok);

        name3(m) = methods3{m, 1};
        acc3(m)  = mean(yp == yt) * 100;
        bal3(m)  = balancedAccuracy(yt, yp) * 100;
        for c = 1:nClass
            mm = yt == c - 1;
            recall3(m, c) = 100 * mean(yp(mm) == yt(mm));
        end
        missFake3(m) = 100 * sum(yt > 0 & yp == 0) / max(1, sum(yt > 0));
        falseAl3(m)  = 100 * sum(yt == 0 & yp > 0) / max(1, sum(yt == 0));
        v1v2mix3(m)  = 100 * sum((yt == 1 & yp == 2) | (yt == 2 & yp == 1)) / max(1, sum(yt > 0));
    end

    % ---- Three-class cascade: Stage 1 = the better ECOC SVM, with scores --
    % Mirrors the binary pipeline: notes whose Stage-1 prediction margin is
    % small (the top class barely beats the runner-up) are re-judged by a
    % second SVM on the PCA-reduced full 380-1000 nm spectrum.
    if acc3(2) > acc3(1), s1Idx3 = 2; else, s1Idx3 = 1; end
    stage1Name3 = name3(s1Idx3);
    stage1Fit3  = methods3{s1Idx3, 2};

    score3      = nan(numNotes, nClass);   % LOO negated-loss score per class
    stage1Pred3 = nan(numNotes, 1);
    for i = 1:numNotes
        tr = true(numNotes, 1); tr(i) = false;
        mdl3 = stage1Fit3(noteMean(tr, :), noteClass3(tr));
        [lab3, negLoss3] = predict(mdl3, noteMean(i, :));
        stage1Pred3(i) = lab3;
        score3(i, :)   = negLoss3;
    end

    % Label-free confidence: gap between the best and second-best class score
    % (gates Stage 2, exactly like |score| < thr in the binary cascade).
    sortedSc3   = sort(score3, 2, "descend");
    predMargin3 = sortedSc3(:, 1) - sortedSc3(:, 2);

    % Label-aware margin TOWARDS THE TRUE CLASS: positive = the model favours
    % the true class, negative = some other class wins. The runner-up column
    % says WHICH class competes: a fake whose runner-up is Real is real-like.
    linIdx3   = sub2ind(size(score3), (1:numNotes)', noteClass3 + 1);
    trueSc3   = score3(linIdx3);
    otherSc3  = score3;
    otherSc3(linIdx3) = -inf;
    [maxOther3, runnerIdx3] = max(otherSc3, [], 2);
    trueMargin3 = trueSc3 - maxOther3;
    runnerUp3   = classList(runnerIdx3);

    thr3       = 0.5 * median(predMargin3, "omitnan");
    uncertain3 = predMargin3 < thr3;

    % Stage 2: full-spectrum multiclass SVM, only for the uncertain notes.
    fullOK3 = ~isempty(noteFullMean);
    if fullOK3
        goodWL3 = all(isfinite(noteFullMean), 1) & (std(noteFullMean, 0, 1) > 0);
        Xfull3  = noteFullMean(:, goodWL3);
        fullOK3 = size(Xfull3, 2) >= 3;
    end

    finalPred3   = stage1Pred3;
    stage2Pred3  = nan(numNotes, 1);
    usedStage2_3 = false(numNotes, 1);

    if fullOK3 && any(uncertain3)
        for i = find(uncertain3(:))'
            tr = true(numNotes, 1); tr(i) = false;
            p2 = fullSpecECOCpredict(Xfull3(tr, :), noteClass3(tr), Xfull3(i, :), 10);
            stage2Pred3(i)  = p2;
            finalPred3(i)   = p2;
            usedStage2_3(i) = true;
        end
    end

    % Cascade metrics, appended to the comparison table.
    casAcc3  = mean(finalPred3 == noteClass3) * 100;
    casBal3  = balancedAccuracy(noteClass3, finalPred3) * 100;
    casRec3  = zeros(1, nClass);
    for c = 1:nClass
        mm = noteClass3 == c - 1;
        casRec3(c) = 100 * mean(finalPred3(mm) == noteClass3(mm));
    end
    casMiss3 = 100 * sum(noteClass3 > 0 & finalPred3 == 0) / max(1, sum(noteClass3 > 0));
    casFA3   = 100 * sum(noteClass3 == 0 & finalPred3 > 0) / max(1, sum(noteClass3 == 0));
    casMix3  = 100 * sum((noteClass3 == 1 & finalPred3 == 2) | ...
                         (noteClass3 == 2 & finalPred3 == 1)) / max(1, sum(noteClass3 > 0));

    cascadeName3 = "Cascade (" + stage1Name3 + " + full spectrum)";
    name3c     = [name3;     cascadeName3];
    acc3c      = [acc3;      casAcc3];
    bal3c      = [bal3;      casBal3];
    recall3c   = [recall3;   casRec3];
    missFake3c = [missFake3; casMiss3];
    falseAl3c  = [falseAl3;  casFA3];
    v1v2mix3c  = [v1v2mix3;  casMix3];

    comparison3 = table(name3c, acc3c, bal3c, recall3c(:, 1), recall3c(:, 2), recall3c(:, 3), ...
        missFake3c, falseAl3c, v1v2mix3c, ...
        'VariableNames', {'Method', 'AccuracyPct', 'BalancedAccPct', ...
        'RecallRealPct', 'RecallFakePct', 'RecallFakeV1Pct', ...
        'AnyFakeAcceptedAsRealPct', 'RealRejectedPct', 'V1V2ConfusedPct'});
    writetable(comparison3, fullfile(resultFolder, "threeclass_classifier_comparison.csv"));

    disp("Three-class comparison (note-level LOO), Real vs Fake vs FakeV1:");
    disp(comparison3);

    fprintf(">> Three-class cascade: Stage 1 = %s (%.2f%%), final accuracy = %.2f%%\n", ...
        stage1Name3, acc3(s1Idx3), casAcc3);

    % Report what Stage 2 did.
    u3 = find(usedStage2_3);
    if isempty(u3)
        fprintf("Stage 2 not triggered (no uncertain notes or no full spectrum).\n");
    else
        info = strings(numel(u3), 1);
        for m = 1:numel(u3)
            j = u3(m);
            flip = "kept";  if stage1Pred3(j) ~= finalPred3(j), flip = "CHANGED"; end
            okS  = "wrong"; if finalPred3(j) == noteClass3(j),  okS  = "correct"; end
            info(m) = noteNames(j) + " [" + classNames(j) + "]: stage1=" + ...
                      classList(stage1Pred3(j) + 1) + " -> stage2=" + ...
                      classList(finalPred3(j) + 1) + " (" + flip + ", " + okS + ")";
        end
        fprintf("Stage 2 reviewed %d uncertain note(s):\n  %s\n", ...
            numel(u3), strjoin(info, sprintf("\n  ")));
    end

    mis3 = find(finalPred3 ~= noteClass3);
    if isempty(mis3)
        fprintf("Three-class cascade classifies all %d notes correctly.\n\n", numNotes);
    else
        info = strings(numel(mis3), 1);
        for m = 1:numel(mis3)
            info(m) = noteNames(mis3(m)) + " (" + classNames(mis3(m)) + " -> " + ...
                      classList(finalPred3(mis3(m)) + 1) + ")";
        end
        fprintf("Cascade misclassified: %s\n\n", strjoin(info, ", "));
    end

    % Per-note predictions of every method plus the cascade.
    pred3Table = table(noteNames(:), classNames(:), ...
        'VariableNames', {'Note', 'TrueClass'});
    safeName3 = ["LinearSVM", "RBFSVM", "kNN3", "Tree"];
    for m = 1:nm3
        col = strings(numNotes, 1);
        col(:) = "n/a";
        okm = ~isnan(predAll3(:, m));
        col(okm) = classList(predAll3(okm, m) + 1);
        pred3Table.("Pred_" + safeName3(m)) = col;
    end
    pred3Table.Pred_Cascade   = classList(finalPred3 + 1);
    pred3Table.CascadeCorrect = finalPred3 == noteClass3;
    writetable(pred3Table, fullfile(resultFolder, "threeclass_note_predictions.csv"));

    % Figures 9a/9b: instead of one 3x3 matrix, the professor asked for the
    % two authentication sub-tasks shown separately -- genuine notes against
    % the ORIGINAL six colour-print fakes (FakeV1), and genuine notes against
    % the THIRTY current fakes (Fake). Each is a proper binary note-level
    % leave-one-note-out run on the 9-channel averaged spectra (Linear SVM,
    % the best single-stage learner above), giving a clean 2x2 matrix and an
    % honest accuracy for each pair. noteMean / classNames here still hold all
    % three classes (section 14c only restricts them afterwards).
    subTasks = {
        "FakeV1", "fig9a_real_vs_fakeV1_confusion.png", ...
                  "realvs_fakeV1_confusion.csv", "Real vs first-generation fakes (FakeV1, original 6)";
        "Fake",   "fig9b_real_vs_fake_confusion.png", ...
                  "realvs_fake_confusion.csv",   "Real vs current fakes (Fake, 30 notes)"
    };

    for s = 1:size(subTasks, 1)
        fakeLbl = subTasks{s, 1};
        keep    = classNames == "Real" | classNames == fakeLbl;
        yBin    = double(classNames(keep) == fakeLbl);   % 0 = Real, 1 = this fake
        Xbin    = noteMean(keep, :);

        predBin = looNotePredict(@(Xt,Yt) fitcsvm(Xt, Yt, "KernelFunction", ...
            "linear", "Standardize", true), Xbin, yBin);
        okB     = ~isnan(predBin);
        ytB     = yBin(okB);  ypB = predBin(okB);
        accBin  = mean(ypB == ytB) * 100;

        figS = figure;
        cmS = confusionchart( ...
            categorical(ytB, [0 1], {'Real', char(fakeLbl)}), ...
            categorical(ypB, [0 1], {'Real', char(fakeLbl)}));
        cmS.XLabel = 'Predicted class';   % explicit: the MATLAB locale is Chinese
        cmS.YLabel = 'True class';
        cmS.FontSize = 12;
        title(sprintf("%s\nBinary note-level LOO (Linear SVM), accuracy = %.2f%%", ...
            subTasks{s, 4}, accBin));
        saveFigure(figS, fullfile(resultFolder, subTasks{s, 2}));

        % Backing 2x2 table so the matrix also lands in the Excel workbook.
        confSub = table(["Real"; fakeLbl], ...
            [sum(ytB==0 & ypB==0); sum(ytB==1 & ypB==0)], ...
            [sum(ytB==0 & ypB==1); sum(ytB==1 & ypB==1)], ...
            'VariableNames', {'TrueClass', 'PredictedReal_0', 'PredictedFake_1'});
        writetable(confSub, fullfile(resultFolder, subTasks{s, 3}));

        fprintf("%s: binary LOO accuracy = %.2f%% (%d Real + %d %s notes)\n", ...
            subTasks{s, 4}, accBin, sum(ytB==0), sum(ytB==1), fakeLbl);
    end

    % Figure 10: the three error types per classifier (cascade included).
    fig10 = figure;
    bar(categorical(name3c, name3c), [missFake3c, falseAl3c, v1v2mix3c]);
    ylabel("Rate (%)");
    legend({"Fake accepted as Real", "Real rejected", "V1 <-> V2 confused"}, ...
        "Location", "northoutside", "Orientation", "horizontal");
    title("Three-Class Comparison: Error Types per Classifier");
    grid on;
    saveFigure(fig10, fullfile(resultFolder, "fig10_3class_error_rates.png"));

    % ---- Margin towards true class: how real-like is each fake? ----------
    % Small margin = the note nearly fell to its runner-up class (for fakes
    % this is almost always Real), so the margin directly compares how
    % convincingly each fake generation imitates a genuine note.
    [~, prio3] = sort(trueMargin3, "ascend");
    s2col = strings(numNotes, 1);
    s2col(:) = "n/a";
    okS2  = ~isnan(stage2Pred3);
    s2col(okS2) = classList(stage2Pred3(okS2) + 1);

    margin3Table = table((1:numNotes)', noteNames(prio3), classNames(prio3), ...
        trueMargin3(prio3), predMargin3(prio3), runnerUp3(prio3), uncertain3(prio3), ...
        usedStage2_3(prio3), classList(stage1Pred3(prio3) + 1), s2col(prio3), ...
        classList(finalPred3(prio3) + 1), finalPred3(prio3) == noteClass3(prio3), ...
        'VariableNames', {'Rank', 'Note', 'Class', 'TrueClassMargin', ...
        'PredictionMargin', 'RunnerUpClass', 'Uncertain', 'UsedStage2', ...
        'Stage1Pred', 'Stage2Pred', 'FinalPred', 'Correct'});
    writetable(margin3Table, fullfile(resultFolder, "threeclass_margins.csv"));

    fprintf("Margin towards true class (mean): Fake (V2) = %.3f, FakeV1 = %.3f, Real = %.3f\n", ...
        mean(trueMargin3(noteClass3 == 1)), mean(trueMargin3(noteClass3 == 2)), ...
        mean(trueMargin3(noteClass3 == 0)));
    fprintf("A larger mean margin = easier to tell from its nearest competing class.\n\n");

    % Figure 11: per-note margins of the two fake generations, sorted so the
    % most real-like fakes sit at the top of the chart.
    fIdx3 = find(noteClass3 > 0);
    [~, ordF] = sort(trueMargin3(fIdx3), "ascend");
    fIdx3 = fIdx3(ordF);
    nF3   = numel(fIdx3);

    % Bar colours first, then split over two side-by-side panels for the same
    % legibility reason as the binary margin chart (fig13).
    cData3 = zeros(nF3, 3);
    for i = 1:nF3
        j = fIdx3(i);
        if finalPred3(j) ~= noteClass3(j)
            cData3(i, :) = [0.84 0.10 0.10];   % misclassified by the cascade
        else
            c = find(classList == classNames(j));
            cData3(i, :) = classColors(c, :);
        end
    end

    half3 = ceil(nF3 / 2);
    xLo3  = min(0, min(trueMargin3(fIdx3))) - 0.10;
    xHi3  = max(trueMargin3(fIdx3)) * 1.06;

    fig11 = figure("Position", [80 80 1000 max(400, 80 + 24 * half3)]);
    tl3   = tiledlayout(fig11, 1, 2, "TileSpacing", "compact", "Padding", "compact");
    for p = 1:2
        idx = (1 + (p - 1) * half3) : min(p * half3, nF3);
        ax  = nexttile(tl3);
        hold(ax, "on");
        b3 = barh(ax, 1:numel(idx), trueMargin3(fIdx3(idx)), ...
            "FaceColor", "flat", "EdgeColor", "none");
        b3.CData = cData3(idx, :);
        % Review-band threshold; named in the title, not with an xline label.
        xline(ax, 0, "-", "LineWidth", 1.2);
        xline(ax, thr3, "--", "LineWidth", 1.0);
        set(ax, "YTick", 1:numel(idx), "YTickLabel", noteNames(fIdx3(idx)), ...
            "YDir", "reverse", "FontSize", 12);
        ylim(ax, [0.4 half3 + 0.6]);
        xlim(ax, [xLo3 xHi3]);
        xlabel(ax, "Margin towards true class (Stage-1 ECOC score gap)");
        grid(ax, "on");
        hold(ax, "off");
    end
    title(tl3, {"Fake notes: margin towards true class (top-left = most real-like)", ...
        sprintf("orange = Fake (V2), purple = FakeV1, red = misclassified; margins < %.2f reviewed by Stage 2", thr3)}, ...
        "FontWeight", "bold");
    saveFigure(fig11, fullfile(resultFolder, "fig11_3class_margin.png"));

    fprintf("Three-class results saved.\n\n");
else
    fprintf("Three-class analysis skipped (need fitcecoc and all three class folders).\n\n");
end


%% =========================
% 14c. Restrict the remaining pipeline to Real vs Fake (V2)
%
% Everything below (cascade SVM, deployed model, FP/FN comparison,
% re-measurement priority) is the report's BINARY authentication task and
% stays Real vs Fake (V2 only), so the headline results are unaffected by
% the added FakeV1 comparison group. NOTE: this overwrites the shared
% variables in place; no section after this point may use the 3-class data.
% =========================

rfNote = classNames == "Real" | classNames == "Fake";
rfSamp = allClassName == "Real" | allClassName == "Fake";

noteRemapRF         = zeros(numNotes, 1);
noteRemapRF(rfNote) = 1:nnz(rfNote);
allNoteIdx          = noteRemapRF(allNoteIdx(rfSamp));

noteMean     = noteMean(rfNote, :);
noteStd      = noteStd(rfNote, :);
noteNames    = noteNames(rfNote);
classNames   = classNames(rfNote);
sampleCounts = sampleCounts(rfNote);
if ~isempty(noteFullMean)
    noteFullMean = noteFullMean(rfNote, :);
end

X            = X(rfSamp, :);
Y            = Y(rfSamp);
allNoteName  = allNoteName(rfSamp);
allClassName = allClassName(rfSamp);
numNotes     = nnz(rfNote);

fprintf("Binary pipeline below uses %d Real + %d Fake notes (FakeV1 excluded).\n\n", ...
    sum(classNames == "Real"), sum(classNames == "Fake"));


%% =========================
% 15. Two-stage cascade SVM classification (RBF kernel)
%
% Stage 1: fast 9-channel AS7341 note-level SVM (one averaged spectrum per
%          banknote), leave-one-note-out CV. Gives a label + a confidence
%          (signed distance to the boundary).
% Stage 2: only when Stage 1 is UNCERTAIN (note sits near the boundary), the
%          full 380-1000 nm high-resolution spectrum is PCA-reduced and fed
%          to a second RBF SVM for a finer real/fake decision. The blue/violet
%          detail that separates a synthesized purple from a real pigment
%          lives in that fine spectrum.
% Also reported: (B) sample-level note-grouped 5-fold CV as a robustness check.
% All evaluations hold out whole notes (no leakage).
% =========================

if exist("fitcsvm", "file") == 2 && numNotes >= 4 && numel(unique(Y)) == 2

    fprintf("Statistics and Machine Learning Toolbox detected. Running cascade SVM...\n");

    noteClass = double(classNames == "Fake");   % per-note label, 0 = Real, 1 = Fake
    nReal     = sum(noteClass == 0);
    nFake     = sum(noteClass == 1);

    boxC     = 1;        % BoxConstraint
    kScale   = "auto";   % KernelScale
    nCompMax = 10;       % cap on PCA components for the Stage-2 full spectrum

    % ---- Stage 1: 9-channel note-level LOO -------------------------------
    notePred  = nan(numNotes, 1);
    noteScore = nan(numNotes, 1);   % signed SVM score for class Fake (+ = Fake side)
    for i = 1:numNotes
        tr = true(numNotes, 1); tr(i) = false;
        if numel(unique(noteClass(tr))) < 2, continue; end
        mdlN = fitcsvm(noteMean(tr, :), noteClass(tr), "KernelFunction", "rbf", ...
            "Standardize", true, "BoxConstraint", boxC, "KernelScale", kScale);
        [lab, sc]    = predict(mdlN, noteMean(i, :));
        notePred(i)  = lab;
        noteScore(i) = sc(2);
    end
    nS = ~isnan(notePred);
    [nAcc, nBal, nSens, nSpec, nPrec, nF1] = classMetrics(noteClass(nS), notePred(nS));

    % Uncertain notes: those sitting close to the Stage-1 boundary.
    thr        = 0.5 * median(abs(noteScore(nS)));
    uncertain  = nS & (abs(noteScore) < thr);

    % ---- Stage 2: full-spectrum SVM, only for the uncertain notes --------
    % Keep only finite, non-constant wavelength columns for PCA.
    fullOK = ~isempty(noteFullMean);
    if fullOK
        goodWL = all(isfinite(noteFullMean), 1) & (std(noteFullMean, 0, 1) > 0);
        Xfull  = noteFullMean(:, goodWL);
        fullOK = size(Xfull, 2) >= 3;
    end

    finalPred   = notePred;             % start from Stage 1
    usedStage2  = false(numNotes, 1);
    stage2Pred  = nan(numNotes, 1);

    if fullOK && any(uncertain)
        for i = find(uncertain(:))'
            tr = true(numNotes, 1); tr(i) = false;
            if numel(unique(noteClass(tr))) < 2, continue; end
            p2 = fullSpecSVMpredict(Xfull(tr, :), noteClass(tr), Xfull(i, :), nCompMax);
            stage2Pred(i) = p2;
            finalPred(i)  = p2;
            usedStage2(i) = true;
        end
    end

    [fAcc, fBal, fSens, fSpec, fPrec, fF1] = classMetrics(noteClass(nS), finalPred(nS));

    % ---- (B) Sample-level note-grouped CV (robustness check) -------------
    K = max(2, min([5, nReal, nFake]));
    YpredCV = groupedCVPredictSVM(X, Y, allNoteIdx, noteClass, K, boxC, kScale, [], 1);
    sS = ~isnan(YpredCV);
    [sAcc, sBal, sSens, sSpec, sPrec, sF1] = classMetrics(Y(sS), YpredCV(sS));

    % ---- Linear SVM candidate (note-level LOO) ---------------------------
    linPred = looNotePredict(@(Xt,Yt) fitcsvm(Xt, Yt, "KernelFunction", "linear", ...
        "Standardize", true), noteMean, noteClass);
    lS = ~isnan(linPred);
    [lAcc, lBal, lSens, lSpec] = classMetrics(noteClass(lS), linPred(lS));

    % ---- Auto-select the best SVM to deploy ------------------------------
    % Primary criterion: highest note-level LOO accuracy. Ties are broken by
    % fewest missed fakes (FN), then fewest false alarms (FP), then by model
    % simplicity (Linear < RBF < Cascade).
    candName = ["Linear SVM"; "RBF SVM"; "Cascade SVM"];
    candAcc  = [lAcc;     nAcc;     fAcc];
    candFN   = ([1-lSens; 1-nSens; 1-fSens]) * 100;
    candFP   = ([1-lSpec; 1-nSpec; 1-fSpec]) * 100;
    candCplx = [1; 2; 3];
    [~, order]   = sortrows([-candAcc, candFN, candFP, candCplx]);
    chosenMethod = candName(order(1));

    % Predictions of the chosen model (drive the headline confusion matrix).
    switch chosenMethod
        case "Linear SVM", deployPred = linPred;
        case "RBF SVM",    deployPred = notePred;
        otherwise,         deployPred = finalPred;
    end
    [dAcc, dBal, dSens, dSpec, dPrec, dF1] = classMetrics(noteClass(nS), deployPred(nS));

    % ---- Build and save the chosen deployable model ----------------------
    if chosenMethod == "Cascade SVM"
        modelType   = "cascade";
        stage1Model = fitPosterior(fitcsvm(noteMean, noteClass, "KernelFunction", "rbf", ...
            "Standardize", true, "BoxConstraint", boxC, "KernelScale", kScale));
        stage2 = struct();
        if fullOK
            muF = mean(Xfull, 1);
            [coeffF, scF, ~, ~, explF] = pca(Xfull);
            nC = find(cumsum(explF) >= 99, 1);
            if isempty(nC), nC = size(scF, 2); end
            nC = max(2, min([nC, nCompMax, size(scF, 2)]));
            stage2.mu = muF; stage2.coeff = coeffF(:, 1:nC); stage2.nComp = nC;
            stage2.goodWL = goodWL; stage2.wl = wlFull;
            stage2.svm = fitcsvm(scF(:, 1:nC), noteClass, "KernelFunction", "rbf", ...
                "Standardize", true, "KernelScale", "auto", "BoxConstraint", 1);
        end
        save(fullfile(resultFolder, "svm_model.mat"), "chosenMethod", "modelType", ...
            "stage1Model", "stage2", "thr", "boxC", "kScale", "normTag", "featureNames");
    else
        modelType = "single";
        if chosenMethod == "Linear SVM"
            deployedModel = fitPosterior(fitcsvm(noteMean, noteClass, ...
                "KernelFunction", "linear", "Standardize", true));
        else
            deployedModel = fitPosterior(fitcsvm(noteMean, noteClass, "KernelFunction", "rbf", ...
                "Standardize", true, "BoxConstraint", boxC, "KernelScale", kScale));
        end
        save(fullfile(resultFolder, "svm_model.mat"), "chosenMethod", "modelType", ...
            "deployedModel", "normTag", "featureNames");
    end

    fprintf("Stage 1 (9ch)    : acc = %.2f%%, bal = %.2f%%, sens(Fake) = %.2f%%, spec(Real) = %.2f%%, F1 = %.3f\n", ...
        nAcc, nBal, nSens*100, nSpec*100, nF1);
    fprintf("Cascade (final)  : acc = %.2f%%, bal = %.2f%%, sens(Fake) = %.2f%%, spec(Real) = %.2f%%, F1 = %.3f\n", ...
        fAcc, fBal, fSens*100, fSpec*100, fF1);
    fprintf("(B) Sample CV    : acc = %.2f%%, bal = %.2f%%\n", sAcc, sBal);
    fprintf("Linear SVM (9ch) : acc = %.2f%%, bal = %.2f%%, sens(Fake) = %.2f%%, spec(Real) = %.2f%%\n", ...
        lAcc, lBal, lSens*100, lSpec*100);
    fprintf(">> Auto-selected deployable SVM: %s (LOO accuracy = %.2f%%)\n", chosenMethod, dAcc);

    % Report what Stage 2 did.
    u = find(usedStage2);
    if isempty(u)
        fprintf("Stage 2 not triggered (no uncertain notes or no full spectrum).\n");
    else
        info = strings(numel(u), 1);
        for m = 1:numel(u)
            j = u(m);
            s1 = "Real"; if notePred(j) == 1, s1 = "Fake"; end
            s2 = "Real"; if finalPred(j) == 1, s2 = "Fake"; end
            flip = "kept";  if notePred(j) ~= finalPred(j), flip = "CHANGED"; end
            ok   = "wrong"; if finalPred(j) == noteClass(j), ok = "correct"; end
            info(m) = noteNames(j) + " [" + classNames(j) + "]: stage1=" + s1 + ...
                      " -> stage2=" + s2 + " (" + flip + ", " + ok + ")";
        end
        fprintf("Stage 2 reviewed %d uncertain note(s):\n  %s\n", ...
            numel(u), strjoin(info, sprintf("\n  ")));
    end

    % Final (cascade) misclassifications.
    misIdx = find(nS & (finalPred ~= noteClass));
    if isempty(misIdx)
        fprintf("Cascade classifies all %d banknotes correctly.\n", numNotes);
    else
        info = strings(numel(misIdx), 1);
        for m = 1:numel(misIdx)
            predLab = "Fake"; if finalPred(misIdx(m)) == 0, predLab = "Real"; end
            info(m) = noteNames(misIdx(m)) + " (" + classNames(misIdx(m)) + " -> " + predLab + ")";
        end
        fprintf("Cascade misclassified: %s\n", strjoin(info, ", "));
    end

    % ---- Save tables -----------------------------------------------------
    yt = noteClass(nS); yp = deployPred(nS);   % confusion of the deployed model
    confusionTable = table(["Real"; "Fake"], ...
        [sum(yt==0 & yp==0); sum(yt==1 & yp==0)], ...
        [sum(yt==0 & yp==1); sum(yt==1 & yp==1)], ...
        'VariableNames', {'TrueClass', 'PredictedReal_0', 'PredictedFake_1'});
    writetable(confusionTable, fullfile(resultFolder, "SVM_confusion_matrix.csv"));

    svmResultTable = table(allNoteName(sS), allClassName(sS), Y(sS), YpredCV(sS), ...
        'VariableNames', {'NoteName', 'ClassName', 'TrueLabel', 'PredictedLabel'});
    writetable(svmResultTable, fullfile(resultFolder, "SVM_sample_predictions.csv"));

    notePredTable = table(noteNames(:), classNames(:), noteClass(:), ...
        notePred(:), noteScore(:), uncertain(:), usedStage2(:), stage2Pred(:), finalPred(:), ...
        deployPred(:), (deployPred(:) == noteClass(:)), ...
        'VariableNames', {'Note', 'TrueClass', 'TrueLabel', 'Stage1Pred', 'Stage1Score', ...
        'Uncertain', 'UsedStage2', 'Stage2Pred', 'CascadePred', 'DeployedPred', 'Correct'});
    writetable(notePredTable, fullfile(resultFolder, "SVM_note_predictions.csv"));

    metricsTable = table( ...
        ["Linear SVM"; "RBF SVM"; "Cascade SVM"; "Deployed (" + chosenMethod + ")"; "SampleLevel_GroupedCV"], ...
        [lAcc; nAcc; fAcc; dAcc; sAcc], ...
        [(1-lSens)*100; (1-nSens)*100; (1-fSens)*100; (1-dSens)*100; (1-sSens)*100], ...
        [(1-lSpec)*100; (1-nSpec)*100; (1-fSpec)*100; (1-dSpec)*100; (1-sSpec)*100], ...
        [lSens*100; nSens*100; fSens*100; dSens*100; sSens*100], ...
        [lSpec*100; nSpec*100; fSpec*100; dSpec*100; sSpec*100], ...
        'VariableNames', {'Model', 'AccuracyPercent', 'FalseNegativeRatePercent', ...
        'FalsePositiveRatePercent', 'SensitivityFakePercent', 'SpecificityRealPercent'});
    writetable(metricsTable, fullfile(resultFolder, "SVM_metrics.csv"));

    % Single-stage vs final accuracy (professor's summary request). When the
    % cascade is deployed, "single stage" = the Stage-1 9-channel RBF SVM
    % alone (nAcc) and "final" = the cascade after the full-spectrum stage
    % (dAcc). When a single SVM is deployed, only one stage exists, so the two
    % numbers are identical.
    usedCascade = chosenMethod == "Cascade SVM";
    if usedCascade
        singleStageAccPct = nAcc;
    else
        singleStageAccPct = dAcc;
    end
    finalAccPct = dAcc;

    svmSummaryTable = table(string(region), numNotes, size(X,1), nReal, nFake, K, ...
        sum(usedStage2), string(chosenMethod), usedCascade, ...
        singleStageAccPct, finalAccPct, ...
        dAcc, lAcc, nAcc, fAcc, dSens*100, dSpec*100, string(normTag), ...
        'VariableNames', {'Region', 'Notes', 'Samples', 'RealNotes', 'FakeNotes', 'Folds', ...
        'Stage2Reviewed', 'ChosenMethod', 'UsedCascade', ...
        'SingleStageAccPct', 'FinalAccPct', ...
        'DeployedAccPct', 'LinearAccPct', 'RBFAccPct', 'CascadeAccPct', ...
        'DeployedSensFakePct', 'DeployedSpecRealPct', 'Features'});
    writetable(svmSummaryTable, fullfile(resultFolder, "SVM_summary.csv"));

    fprintf("Tables and deployed model (%s) saved.\n", chosenMethod);
    if usedCascade
        fprintf(">> [%s] Single-stage (Stage 1) accuracy = %.2f%%, final cascade accuracy = %.2f%%\n\n", ...
            region, singleStageAccPct, finalAccPct);
    else
        fprintf(">> [%s] Single-stage accuracy = final accuracy = %.2f%% (cascade not triggered; %s deployed)\n\n", ...
            region, finalAccPct, chosenMethod);
    end

    % Final-result confusion matrix ONLY: yt/yp are the deployed predictions,
    % i.e. the single-stage result when a single SVM is deployed, or the final
    % cascade result when the cascade is deployed. Title = measurement region.
    % MATLAB runs in a Chinese locale on this machine, so a bare
    % confusionchart labels its axes in Chinese and shows the raw 0/1 class
    % codes. Both are set explicitly here so the figure reads correctly in
    % the English report.
    fig6 = figure;
    cm6 = confusionchart( ...
        categorical(yt, [0 1], {'Real', 'Fake'}), ...
        categorical(yp, [0 1], {'Real', 'Fake'}));
    cm6.XLabel = 'Predicted class';
    cm6.YLabel = 'True class';
    cm6.FontSize = 12;   % ConfusionMatrixChart ignores defaultAxesFontSize
    title(sprintf("%s  (accuracy = %.2f%%)", regionLabel, finalAccPct));
    saveFigure(fig6, fullfile(resultFolder, "fig6_confusion_matrix.png"));

    % ---- Re-measurement priority TABLE (credibility figure removed) ------
    % One interpretable number per note: the Stage-1 margin towards its TRUE
    % class (positive = correct side of the boundary, negative = wrong side),
    % ranked ascending so the most urgent notes to re-measure come first. The
    % Status column flags OK / Borderline / Misclassified notes. Saved only as
    % a table (remeasure_priority.csv / Remeasure_priority sheet); per user
    % request the per-note credibility bar chart is no longer drawn.
    trueMargin = (2 * noteClass - 1) .* noteScore;

    noteStatus = strings(numNotes, 1);
    noteStatus(:) = "OK";
    noteStatus(uncertain) = "Borderline";
    noteStatus(nS & (deployPred ~= noteClass)) = "Misclassified";

    [~, prio] = sort(trueMargin, "ascend");

    remeasureTable = table((1:numNotes)', noteNames(prio), classNames(prio), ...
        sampleCounts(prio), trueMargin(prio), noteScore(prio), noteStatus(prio), ...
        'VariableNames', {'Rank', 'Note', 'Class', 'Measurements', ...
        'TrueClassMargin', 'Stage1FakeScore', 'Status'});
    writetable(remeasureTable, fullfile(resultFolder, "remeasure_priority.csv"));

    fprintf("Re-measurement priority (top 10, lowest true-class margin first):\n");
    disp(remeasureTable(1:min(10, height(remeasureTable)), :));

    % ---- Figure: per-note margin towards the TRUE class (binary) ----------
    % One horizontal bar per banknote = its Stage-1 signed distance towards
    % its own class (positive = correct side of the boundary, |value| =
    % confidence). Notes are sorted so the least-confident sit at the top.
    % Colour: red = misclassified by the deployed model, amber = inside the
    % Stage-2 review band, blue = Real, orange = Fake. This is the binary
    % analogue of the three-class margin chart (fig11). No legend is used so
    % nothing can overlap the bars; the colour key lives in the title.
    [~, ordM] = sort(trueMargin, "ascend");
    nAll = numNotes;

    % Per-note bar colours, computed once and then split across two panels.
    cDataM = zeros(nAll, 3);
    for i = 1:nAll
        j = ordM(i);
        if nS(j) && (deployPred(j) ~= noteClass(j))
            cDataM(i, :) = [0.84 0.10 0.10];               % misclassified
        elseif uncertain(j)
            cDataM(i, :) = [0.93 0.69 0.13];               % Stage-2 review band (amber)
        else
            cDataM(i, :) = classColors(noteClass(j) + 1, :); % blue Real / orange Fake
        end
    end

    % All notes in a single tall column forced a tiny tick-label font, which
    % became illegible once the figure was scaled into the report. The notes
    % are therefore split over two side-by-side panels (least confident first,
    % continuing in the right-hand panel): each bar gets twice the vertical
    % space, so the note names stay readable, while the overall aspect ratio
    % stays wide and short and the figure still fits on the page.
    halfM = ceil(nAll / 2);
    % Keep -thr inside the axes so the whole Stage-2 review band (and its
    % label) stays visible even when no note has a margin that negative.
    xLoM  = min([0, min(trueMargin), -thr]) - 0.10;
    xHiM  = max(trueMargin) * 1.06;

    % Deliberately narrow (1000 px): the figure is scaled to the full text
    % width in the report, so a smaller pixel width means a LARGER effective
    % font on the printed page. 12 pt here lands at roughly 7.5 pt on paper.
    figM = figure("Position", [80 80 1000 max(400, 80 + 24 * halfM)]);
    tlM  = tiledlayout(figM, 1, 2, "TileSpacing", "compact", "Padding", "compact");
    for p = 1:2
        idx = (1 + (p - 1) * halfM) : min(p * halfM, nAll);
        ax  = nexttile(tlM);
        hold(ax, "on");
        bM = barh(ax, 1:numel(idx), trueMargin(ordM(idx)), ...
            "FaceColor", "flat", "EdgeColor", "none");
        bM.CData = cDataM(idx, :);
        % The two dashed lines mark the Stage-2 review band; it is named in the
        % figure title rather than with an xline label, which would otherwise
        % overlap the note names at the bottom of the panel.
        xline(ax, 0, "-", "LineWidth", 1.2);
        xline(ax,  thr, "--", "LineWidth", 1.0);
        xline(ax, -thr, "--", "LineWidth", 1.0);
        set(ax, "YTick", 1:numel(idx), "YTickLabel", noteNames(ordM(idx)), ...
            "YDir", "reverse", "FontSize", 12);
        ylim(ax, [0.4 halfM + 0.6]);   % same limits in both panels = equal bar heights
        xlim(ax, [xLoM xHiM]);
        xlabel(ax, "Margin towards true class (Stage-1 signed distance)");
        grid(ax, "on");
        hold(ax, "off");
    end
    title(tlM, {sprintf("%s: per-note margin towards true class (top-left = least confident)", regionLabel), ...
        sprintf("blue = Real, orange = Fake, amber = reviewed by Stage 2 (|margin| < %.2f), red = misclassified", thr)}, ...
        "FontWeight", "bold");
    saveFigure(figM, fullfile(resultFolder, "fig13_note_margin.png"));

    fprintf("Re-measurement priority table + per-note margin figure (fig13) saved.\n\n");

else
    fprintf("Classification skipped (need fitcsvm, >=4 notes, both classes).\n\n");
end


%% =========================
% 16. Classifier comparison with false-positive / false-negative rates
%     (professor's request #2)
%
% Several classifiers are compared under the SAME note-level leave-one-note-
% out CV, on the 9-channel averaged spectra. SVM stays the chosen method;
% the others quantify how much discrimination power it gives up or gains.
% Definitions follow the professor's note:
%   False Positive (FP): system says Fake, but it is Real  -> 1 - specificity
%   False Negative (FN): system says Real, but it is Fake  -> 1 - sensitivity
% (FN, a missed counterfeit, is the costlier error.)
% =========================

if exist("fitcsvm", "file") == 2 && numNotes >= 4 && numel(unique(classNames)) == 2

    noteClassC = double(classNames == "Fake");

    methods = {
        "RBF SVM",          @(Xt,Yt) fitcsvm(Xt, Yt, "KernelFunction", "rbf", ...
                              "Standardize", true, "KernelScale", "auto", "BoxConstraint", 1);
        "Linear SVM",       @(Xt,Yt) fitcsvm(Xt, Yt, "KernelFunction", "linear", "Standardize", true);
        "k-NN (k=3)",       @(Xt,Yt) fitcknn(Xt, Yt, "NumNeighbors", 3, "Standardize", true);
        "Decision Tree",    @(Xt,Yt) fitctree(Xt, Yt)
    };

    nm  = size(methods, 1);
    mName = strings(nm, 1);
    accV  = zeros(nm, 1); fpV = zeros(nm, 1); fnV = zeros(nm, 1);
    senV  = zeros(nm, 1); speV = zeros(nm, 1);

    for m = 1:nm
        pred = looNotePredict(methods{m, 2}, noteMean, noteClassC);
        ok   = ~isnan(pred);
        yt   = noteClassC(ok); yp = pred(ok);

        tp = sum(yt==1 & yp==1); fn = sum(yt==1 & yp==0);
        tn = sum(yt==0 & yp==0); fp = sum(yt==0 & yp==1);

        mName(m) = methods{m, 1};
        accV(m)  = mean(yp == yt) * 100;
        senV(m)  = 100 * tp / max(1, tp + fn);   % sensitivity (Fake recall)
        speV(m)  = 100 * tn / max(1, tn + fp);   % specificity (Real recall)
        fnV(m)   = 100 * fn / max(1, tp + fn);   % FN rate: Fake called Real
        fpV(m)   = 100 * fp / max(1, tn + fp);   % FP rate: Real called Fake
    end

    % Append the cascade (SVM + full spectrum) for reference.
    if exist("fAcc", "var") == 1
        mName(end+1) = "Cascade SVM";   %#ok<SAGROW>
        accV(end+1)  = fAcc;            %#ok<SAGROW>
        senV(end+1)  = fSens * 100;     %#ok<SAGROW>
        speV(end+1)  = fSpec * 100;     %#ok<SAGROW>
        fnV(end+1)   = (1 - fSens)*100; %#ok<SAGROW>
        fpV(end+1)   = (1 - fSpec)*100; %#ok<SAGROW>
    end

    % Mark the auto-selected deployable model.
    if exist("chosenMethod", "var") == 1
        sel = mName == chosenMethod;
        if any(sel), mName(sel) = mName(sel) + " (chosen/deployed)"; end
    end

    comparisonTable = table(mName, accV, fpV, fnV, senV, speV, ...
        'VariableNames', {'Method', 'AccuracyPct', 'FalsePositiveRatePct', ...
        'FalseNegativeRatePct', 'SensitivityFakePct', 'SpecificityRealPct'});
    writetable(comparisonTable, fullfile(resultFolder, "classifier_comparison.csv"));

    disp("Classifier comparison (note-level LOO), FP = Real->Fake, FN = Fake->Real:");
    disp(comparisonTable);

    fig7 = figure;
    bar(categorical(mName, mName), [fpV, fnV]);
    ylabel("Rate (%)");
    % Legend inside the axes (upper left is empty: only the decision tree has
    % large error rates), with headroom so it never covers a bar. An outside
    % legend sat above the title, which read awkwardly in the report.
    ylim([0, max([fpV(:); fnV(:); 1]) * 1.35]);
    legend({"False Positive (Real->Fake)", "False Negative (Fake->Real)"}, ...
        "Location", "northwest");
    title("Classifier Comparison: False Positive / False Negative Rates");
    grid on;
    saveFigure(fig7, fullfile(resultFolder, "fig7_classifier_fp_fn.png"));

    % Note-level LOO accuracy per classifier. Unlike the FP/FN chart above,
    % this stays informative even when every classifier is perfect (uniform
    % regions), and it directly ranks the classifiers. The deployed model is
    % highlighted and each bar is annotated with its accuracy; no legend is
    % used so nothing overlaps the bars.
    fig14 = figure;
    bA = bar(categorical(mName, mName), accV, 0.6, "FaceColor", "flat");
    for m = 1:numel(accV)
        if contains(mName(m), "chosen/deployed")
            bA.CData(m, :) = [0.85 0.33 0.10];   % deployed model highlighted
        else
            bA.CData(m, :) = [0.00 0.45 0.74];
        end
    end
    ylabel("Note-level LOO accuracy (%)");
    ylim([max(0, floor(min(accV)) - 8) 104]);
    text(1:numel(accV), accV, compose("%.1f", accV), ...
        "HorizontalAlignment", "center", "VerticalAlignment", "bottom", "FontSize", 8);
    title(sprintf("%s: classifier comparison (note-level LOO accuracy)", regionLabel));
    grid on;
    saveFigure(fig14, fullfile(resultFolder, "fig14_classifier_accuracy.png"));

    fprintf("Classifier comparison saved (fig7 FP/FN + fig14 accuracy).\n\n");


    %% =====================
    % 16b. Processing-time benchmark (professor's request)
    %
    % Speed matters for authentication: commercial verifiers check a note in
    % well under a second. Each candidate model is trained once on all notes,
    % then SINGLE-NOTE prediction is timed (nRep repetitions over every note,
    % after a warm-up call). The cascade time is Stage 1 plus the full-
    % spectrum Stage 2 weighted by the fraction of notes it actually reviews.
    % =====================

    nRep = 200;

    tmName  = strings(0, 1);
    trainMs = [];
    predMs  = [];
    timeAcc = [];

    for m = 1:size(methods, 1)
        t0 = tic;
        mdlT = methods{m, 2}(noteMean, noteClassC);
        tTrain = toc(t0) * 1e3;

        predict(mdlT, noteMean(1, :));   % warm-up before timing
        t0 = tic;
        for r = 1:nRep
            for i = 1:numNotes
                predict(mdlT, noteMean(i, :));
            end
        end
        tPred = toc(t0) / (nRep * numNotes) * 1e3;   % ms per note

        tmName(end+1, 1)  = methods{m, 1};  %#ok<SAGROW>
        trainMs(end+1, 1) = tTrain;         %#ok<SAGROW>
        predMs(end+1, 1)  = tPred;          %#ok<SAGROW>
        timeAcc(end+1, 1) = accV(m);        %#ok<SAGROW>
    end

    if exist("fAcc", "var") == 1 && exist("fullOK", "var") == 1 && fullOK
        % Deployment-style cascade: Stage-1 RBF SVM + full-spectrum Stage 2.
        t0 = tic;
        s1T = fitcsvm(noteMean, noteClassC, "KernelFunction", "rbf", ...
            "Standardize", true, "BoxConstraint", boxC, "KernelScale", kScale);
        muT = mean(Xfull, 1);
        [coeffT, scT, ~, ~, explT] = pca(Xfull);
        nC = find(cumsum(explT) >= 99, 1);
        if isempty(nC), nC = size(scT, 2); end
        nC = max(2, min([nC, nCompMax, size(scT, 2)]));
        s2T = fitcsvm(scT(:, 1:nC), noteClassC, "KernelFunction", "rbf", ...
            "Standardize", true, "KernelScale", "auto", "BoxConstraint", 1);
        tTrainCas = toc(t0) * 1e3;

        % Stage-1 per-note prediction time (label + score for the gate).
        [~, ~] = predict(s1T, noteMean(1, :));   % warm-up
        t0 = tic;
        for r = 1:nRep
            for i = 1:numNotes
                [~, ~] = predict(s1T, noteMean(i, :));
            end
        end
        tS1 = toc(t0) / (nRep * numNotes) * 1e3;

        % Stage-2 per-note time: PCA projection of the full spectrum + SVM.
        predict(s2T, (Xfull(1, :) - muT) * coeffT(:, 1:nC));   % warm-up
        t0 = tic;
        for r = 1:nRep
            for i = 1:numNotes
                z = (Xfull(i, :) - muT) * coeffT(:, 1:nC);
                predict(s2T, z);
            end
        end
        tS2 = toc(t0) / (nRep * numNotes) * 1e3;

        reviewFrac = mean(uncertain);   % fraction of notes Stage 2 re-examines
        tCascade   = tS1 + reviewFrac * tS2;

        tmName(end+1, 1)  = "Cascade SVM";
        trainMs(end+1, 1) = tTrainCas;
        predMs(end+1, 1)  = tCascade;
        timeAcc(end+1, 1) = fAcc;

        fprintf("Cascade timing: Stage 1 = %.4f ms/note, Stage 2 = %.4f ms/note (PCA projection + SVM), review fraction = %.1f%%\n", ...
            tS1, tS2, reviewFrac * 100);
    end

    timingTable = table(tmName, trainMs, predMs, timeAcc, ...
        'VariableNames', {'Model', 'TrainTimeMs', 'PredictTimePerNoteMs', 'LOOAccuracyPct'});
    writetable(timingTable, fullfile(resultFolder, "timing_benchmark.csv"));

    disp("Processing-time benchmark (single-note prediction, averaged over " + ...
        nRep + " repetitions):");
    disp(timingTable);

    fig12 = figure;
    scatter(predMs, timeAcc, 70, "filled");
    text(predMs * 1.08, timeAcc, tmName, "FontSize", 9);
    set(gca, "XScale", "log");
    xlim([min(predMs) * 0.7, max(predMs) * 2.5]);   % leave room for the labels
    xlabel("Prediction time per note (ms, log scale)");
    ylabel("Note-level LOO accuracy (%)");
    title("Speed vs Accuracy Trade-off of the Compared Classifiers");
    grid on;
    saveFigure(fig12, fullfile(resultFolder, "fig12_time_accuracy.png"));

    fprintf("Timing benchmark saved.\n\n");
end


%% =========================
% 17. Final interpretation
% =========================

fprintf("===== Interpretation =====\n");
fprintf("Features: Corr F1-F8 and Corr NIR, each divided by Corr Clear");
if applySNV
    fprintf(", then SNV (per-spectrum shape normalization).\n");
    fprintf("SNV removes brightness, so worn (lighter) real notes and the\n");
    fprintf("colour-synthesised fake are compared by spectral SHAPE, not intensity.\n");
else
    fprintf(".\n");
end
fprintf("LED is off during measurement and is never used for filtering.\n");
fprintf("Files are auto-discovered recursively from the real/, fake/ and Fake_V1/ folders.\n");
fprintf("Each run refreshes the result folder (old CSV/PNG removed, newest kept).\n");
fprintf("Most separable channels (|Cohen's d|):\n");
disp(analysisTable(1:min(3, height(analysisTable)), :));


%% =========================
% 18. Merge every result table into ONE Excel workbook (one sheet each)
% =========================

xlsxFile = fullfile(resultFolder, "banknote_results.xlsx");
if exist(xlsxFile, "file"), delete(xlsxFile); end

% {csv base name, Excel sheet name}. Order = reading order in the workbook.
sheetMap = {
    "SVM_summary",                          "Summary"
    "SVM_metrics",                          "SVM_metrics"
    "classifier_comparison",                "Classifier_comparison"
    "SVM_confusion_matrix",                 "Confusion_matrix"
    "SVM_note_predictions",                 "Note_predictions"
    "threeclass_classifier_comparison",     "ThreeClass_comparison"
    "threeclass_note_predictions",          "ThreeClass_predictions"
    "realvs_fakeV1_confusion",              "Conf_Real_vs_FakeV1"
    "realvs_fake_confusion",                "Conf_Real_vs_Fake"
    "threeclass_margins",                   "ThreeClass_margins"
    "timing_benchmark",                     "Timing"
    "remeasure_priority",                   "Remeasure_priority"
    "closest_cross_class_pairs",            "Closest_cross_pairs"
    "fake_nearest_real",                    "Fake_nearest_real"
    "banknote_channel_difference_analysis", "Channel_difference"
    "banknote_summary",                     "Per_note_summary"
    "banknote_note_mean_spectra",           "Note_mean_spectra"
    "banknote_pairwise_mean_distance",      "Pairwise_distance"
    "PCA_explained_variance",               "PCA_explained_variance"
    "PCA_PC1_channel_contribution",         "PCA_PC1_contribution"
    "PCA_loading",                          "PCA_loading"
    "PCA_scores",                           "PCA_scores"
    "SVM_sample_predictions",               "Sample_predictions"
    "banknote_dataset",                     "Dataset"
};

nWritten = 0;
for q = 1:size(sheetMap, 1)
    csvPath = fullfile(resultFolder, sheetMap{q, 1} + ".csv");
    if isfile(csvPath)
        T = readtable(csvPath, "VariableNamingRule", "preserve");
        writetable(T, xlsxFile, "Sheet", sheetMap{q, 2});
        nWritten = nWritten + 1;
    end
end

% Remove the individual CSVs now that everything lives in the workbook.
csvLeft = dir(fullfile(resultFolder, "*.csv"));
for q = 1:numel(csvLeft)
    delete(fullfile(csvLeft(q).folder, csvLeft(q).name));
end

fprintf("Merged %d tables into one workbook:\n%s\n", nWritten, xlsxFile);

fprintf("All outputs saved to:\n%s\n", resultFolder);
fprintf("Program finished successfully.\n");


%% =========================
% Local functions
% =========================

function foldOfNote = assignGroupedFolds(noteClass, K, seed)
    % Assign whole notes to K folds, stratified by class.
    rng(seed);
    foldOfNote = zeros(numel(noteClass), 1);
    for cl = unique(noteClass(:))'
        idx = find(noteClass == cl);
        idx = idx(randperm(numel(idx)));
        foldOfNote(idx) = mod(0:numel(idx)-1, K) + 1;
    end
end


function pred = groupedCVPredictSVM(X, Y, sampNote, noteClass, K, C, KS, costMat, seed)
    % Note-grouped K-fold CV predictions for an RBF SVM. sampNote maps each
    % sample to a contiguous note index; whole notes are held out per fold.
    foldOfNote = assignGroupedFolds(noteClass, K, seed);
    pred = nan(size(Y));
    for f = 1:K
        testNotes = find(foldOfNote == f);
        isTest    = ismember(sampNote, testNotes);
        isTrain   = ~isTest;
        if ~any(isTest) || numel(unique(Y(isTrain))) < 2
            continue;
        end
        args = {"KernelFunction", "rbf", "Standardize", true, ...
                "BoxConstraint", C, "KernelScale", KS};
        if ~isempty(costMat)
            args = [args, {"Cost", costMat}]; %#ok<AGROW>
        end
        mdl = fitcsvm(X(isTrain, :), Y(isTrain), args{:});
        pred(isTest) = predict(mdl, X(isTest, :));
    end
end


function pred = looNotePredict(fitFun, Xnote, Ynote)
    % Leave-one-note-out predictions for any classifier supplied as a fit
    % function handle fitFun(Xtrain, Ytrain) -> trained model with predict().
    n    = size(Xnote, 1);
    pred = nan(n, 1);
    for i = 1:n
        tr = true(n, 1); tr(i) = false;
        if numel(unique(Ynote(tr))) < 2, continue; end
        mdl     = fitFun(Xnote(tr, :), Ynote(tr));
        pred(i) = predict(mdl, Xnote(i, :));
    end
end


function [pred, score] = fullSpecSVMpredict(XtrFull, Ytr, XteFull, nCompMax)
    % Stage-2 classifier: PCA-reduce the full high-resolution spectrum (fit on
    % training notes only, to avoid leakage), then an RBF SVM. Returns the
    % predicted label and the signed Fake-class score for the test note(s).
    mu = mean(XtrFull, 1);
    [coeff, scoreTr, ~, ~, expl] = pca(XtrFull);

    nComp = find(cumsum(expl) >= 99, 1);
    if isempty(nComp), nComp = size(scoreTr, 2); end
    nComp = max(2, min([nComp, nCompMax, size(scoreTr, 2)]));

    Ztr = scoreTr(:, 1:nComp);
    Zte = (XteFull - mu) * coeff(:, 1:nComp);

    mdl = fitcsvm(Ztr, Ytr, "KernelFunction", "rbf", "Standardize", true, ...
        "KernelScale", "auto", "BoxConstraint", 1);
    [pred, sc] = predict(mdl, Zte);
    score = sc(:, 2);
end


function pred = fullSpecECOCpredict(XtrFull, Ytr, XteFull, nCompMax)
    % Stage-2 THREE-CLASS classifier: PCA-reduce the full high-resolution
    % spectrum (fit on training notes only, to avoid leakage), then a
    % multiclass ECOC SVM with RBF learners. Returns the predicted label.
    mu = mean(XtrFull, 1);
    [coeff, scoreTr, ~, ~, expl] = pca(XtrFull);

    nComp = find(cumsum(expl) >= 99, 1);
    if isempty(nComp), nComp = size(scoreTr, 2); end
    nComp = max(2, min([nComp, nCompMax, size(scoreTr, 2)]));

    Ztr = scoreTr(:, 1:nComp);
    Zte = (XteFull - mu) * coeff(:, 1:nComp);

    mdl  = fitcecoc(Ztr, Ytr, "Learners", templateSVM("KernelFunction", "rbf", ...
        "Standardize", true, "KernelScale", "auto", "BoxConstraint", 1));
    pred = predict(mdl, Zte);
end


function s = balancedAccuracy(yt, yp)
    % Mean of per-class recall; robust to class imbalance.
    cl   = unique(yt);
    accs = zeros(numel(cl), 1);
    for i = 1:numel(cl)
        m       = yt == cl(i);
        accs(i) = mean(yp(m) == yt(m));
    end
    s = mean(accs);
end


function [acc, bal, sens, spec, prec, f1] = classMetrics(yt, yp)
    % Binary metrics with Fake (label 1) as the positive class.
    acc  = mean(yp == yt) * 100;
    bal  = balancedAccuracy(yt, yp) * 100;
    tp   = sum(yt == 1 & yp == 1);
    fn   = sum(yt == 1 & yp == 0);
    tn   = sum(yt == 0 & yp == 0);
    fp   = sum(yt == 0 & yp == 1);
    sens = tp / max(1, tp + fn);     % recall of Fake
    spec = tn / max(1, tn + fp);     % recall of Real
    prec = tp / max(1, tp + fp);     % precision of Fake
    f1   = 2 * prec * sens / max(eps, prec + sens);
end


function Xout = applySNVrows(Xin)
    % SNV: standardize each spectrum (row) to zero mean and unit std across
    % channels, removing overall brightness and keeping spectral shape.
    m = mean(Xin, 2, "omitnan");
    s = std(Xin, 0, 2, "omitnan");
    s(s == 0) = eps;
    Xout = (Xin - m) ./ s;
end


function saveFigure(fig, filePath)
    try
        exportgraphics(fig, filePath, "Resolution", 200);
    catch
        try
            print(fig, char(erase(string(filePath), ".png")), "-dpng", "-r200");
        catch ME
            warning("Could not save figure %s: %s", filePath, ME.message);
        end
    end
end


function order = naturalSortOrder(names)
    % Natural sort order so Real2 comes before Real10. Sorts by the trailing
    % integer in each file name; names without a number keep alpha order.
    names = names(:);
    num   = nan(numel(names), 1);
    for i = 1:numel(names)
        tok = regexp(names(i), '\d+', 'match');
        if ~isempty(tok), num(i) = str2double(tok(end)); end
    end
    [~, order] = sortrows([num, (1:numel(names))']);
end


function [X, X_corr, T_used, X_full, wl] = readAS7341Normalized(filePath, useLEDFilter)

    corrCols = [
        "Corr F1 (415nm)"
        "Corr F2 (445nm)"
        "Corr F3 (480nm)"
        "Corr F4 (515nm)"
        "Corr F5 (555nm)"
        "Corr F6 (590nm)"
        "Corr F7 (630nm)"
        "Corr F8 (680nm)"
        "Corr Clear"
        "Corr NIR"
    ];

    opts = detectImportOptions(filePath, "Delimiter", ";");
    opts.VariableNamingRule = "preserve";
    T_all = readtable(filePath, opts);

    T_used = T_all;

    if useLEDFilter
        if ismember("LED_EN", string(T_all.Properties.VariableNames))
            idxLED = getLedTrueIndex(T_all);
            if any(idxLED)
                T_used = T_all(idxLED, :);
            else
                warning("%s has no LED-on rows. Using all rows.", filePath);
            end
        else
            warning("%s does not contain LED_EN. Using all rows.", filePath);
        end
    end

    existingCols = string(T_used.Properties.VariableNames);
    missingCols  = setdiff(corrCols, existingCols);
    if ~isempty(missingCols)
        disp("Missing columns:");
        disp(missingCols);
        error("Column names do not match in file: %s", filePath);
    end

    X_corr = extractNumericMatrix(T_used, corrCols);

    validRows = ~all(isnan(X_corr), 2) & X_corr(:, 9) > 0;
    X_corr    = X_corr(validRows, :);
    T_used    = T_used(validRows, :);

    F     = X_corr(:, 1:8);
    Clear = X_corr(:, 9);
    NIR   = X_corr(:, 10);
    Clear(Clear == 0) = eps;

    X = [F ./ Clear, NIR ./ Clear];

    % Full high-resolution spectrum: every "<n> nm" column (380-1000 nm).
    vnames = string(T_used.Properties.VariableNames);
    isWL   = ~cellfun('isempty', regexp(vnames, '^\s*\d+\s*nm\s*$', 'once'));
    if any(isWL)
        X_full = extractNumericMatrix(T_used, vnames(isWL));
        wl     = str2double(regexp(vnames(isWL), '\d+', 'match', 'once'));
        [wl, ord] = sort(wl);
        X_full = X_full(:, ord);
    else
        X_full = [];
        wl     = [];
    end
end


function idxLED = getLedTrueIndex(T)
    LED_column = T.("LED_EN");
    if islogical(LED_column)
        idxLED = LED_column == true;
    elseif isnumeric(LED_column)
        idxLED = LED_column ~= 0;
    else
        LED_string = lower(strtrim(string(LED_column)));
        idxLED = LED_string == "true" | LED_string == "1" | ...
                 LED_string == "yes"  | LED_string == "on";
    end
end


function X = extractNumericMatrix(T, cols)
    raw = table2array(T(:, cols));
    if isnumeric(raw)
        X = double(raw);
    else
        rawString = string(raw);
        rawString = strrep(rawString, ",", ".");
        X = str2double(rawString);
    end
end
