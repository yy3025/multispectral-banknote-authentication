clc; clearvars; close all;
rng(0);

%% =========================
% Why did the digit-stroke accuracy fall, and what recovers it?
%
% Three tests, all under the same note-level leave-one-banknote-out protocol
% used in the report:
%   1. REPEAT-COUNT SWEEP. Sub-sample every note to n repeats and re-run.
%      If accuracy rises as n falls, the earlier 100% was an artefact of
%      estimating each note mean from too few measurements. If it does not,
%      the repeat count is not the cause and the difference lies in WHERE on
%      the stroke the earlier session sampled.
%   2. FULL SPECTRUM. Use the reconstructed 380-1000 nm spectrum as the
%      primary feature (PCA-reduced) instead of only the nine channels.
%   3. MULTI-REGION FUSION. Concatenate the nine channel means of the same
%      note measured on two or three regions, as a device with two or three
%      sensing spots would do.
% =========================

featureNames = ["F1_Clear","F2_Clear","F3_Clear","F4_Clear","F5_Clear", ...
                "F6_Clear","F7_Clear","F8_Clear","NIR_Clear"];
regions = struct( ...
    "key",  {"20", "yellow", "white"}, ...
    "dir",  {"D:\project\Result\result_20", "D:\project\Result\result_yellow", "D:\project\Result\result_white"});

% ---- load sample-level data for each region (binary classes only) --------
S = struct();
for r = 1:numel(regions)
    wb = fullfile(regions(r).dir, "banknote_results.xlsx");
    D  = readtable(wb, "Sheet", "Dataset", "VariableNamingRule", "preserve");
    D.NoteName  = string(D.NoteName);
    D.ClassName = string(D.ClassName);
    D = D(D.ClassName == "Real" | D.ClassName == "Fake", :);
    S.(matlab.lang.makeValidName(regions(r).key)).X     = table2array(D(:, cellstr(featureNames)));
    S.(matlab.lang.makeValidName(regions(r).key)).note  = D.NoteName;
    S.(matlab.lang.makeValidName(regions(r).key)).class = D.ClassName;
end

looAcc = @(X, y) mean(arrayfun(@(i) predict(fitcsvm(X(setdiff(1:numel(y), i), :), ...
    y(setdiff(1:numel(y), i)), "KernelFunction", "linear", "Standardize", true), ...
    X(i, :)) == y(i), 1:numel(y))) * 100;

%% ---- Test 1: repeat-count sweep on the digit stroke ---------------------
A  = S.x20;
notes  = unique(A.note, "stable");
nNote  = numel(notes);
yBin   = zeros(nNote, 1);
idxOf  = cell(nNote, 1);
for i = 1:nNote
    idxOf{i} = find(A.note == notes(i));
    yBin(i)  = double(A.class(idxOf{i}(1)) == "Fake");
end
reps = cellfun(@numel, idxOf);
fprintf("Digit stroke: %d notes, repeats %d-%d\n\n", nNote, min(reps), max(reps));

nList  = [4 6 8 11 14 17];
nDraw  = 40;
sweep  = table();
for nn = nList
    accs = nan(nDraw, 1);
    for b = 1:nDraw
        M = nan(nNote, numel(featureNames));
        for i = 1:nNote
            sel = idxOf{i}(randperm(reps(i), min(nn, reps(i))));
            M(i, :) = mean(A.X(sel, :), 1, "omitnan");
        end
        accs(b) = looAcc(M, yBin);
    end
    sweep = [sweep; table(nn, mean(accs), std(accs), min(accs), max(accs), ...
        'VariableNames', {'RepeatsPerNote','MeanAccPct','StdAccPct','MinAccPct','MaxAccPct'})];  %#ok<AGROW>
    fprintf("  n = %2d repeats/note : %.2f%% +/- %.2f  (range %.2f-%.2f)\n", ...
        nn, mean(accs), std(accs), min(accs), max(accs));
end
% full data reference
Mfull = nan(nNote, numel(featureNames));
for i = 1:nNote, Mfull(i, :) = mean(A.X(idxOf{i}, :), 1, "omitnan"); end
accFull = looAcc(Mfull, yBin);
fprintf("  all repeats        : %.2f%%\n\n", accFull);

%% ---- Test 2: full 380-1000 nm spectrum as the primary feature ----------
wb20 = fullfile(regions(1).dir, "banknote_results.xlsx");
Draw = readtable(wb20, "Sheet", "Dataset", "VariableNamingRule", "preserve");
% the Dataset sheet holds only the 9 features; the per-nm spectrum lives in
% the source CSVs, so rebuild the note-level full spectra from there
folders = ["D:\project\data_20\real", "D:\project\data_20\fake"];
fullNote = strings(0,1); fullClass = strings(0,1); fullSpec = [];
for f = 1:2
    files = dir(fullfile(folders(f), "**", "*.csv"));
    for k = 1:numel(files)
        p = fullfile(files(k).folder, files(k).name);
        T = readtable(p, "FileType", "text", "Delimiter", ";", ...
            "VariableNamingRule", "preserve");
        vn = string(T.Properties.VariableNames);
        nmCols = vn(~cellfun(@isempty, regexp(vn, '^\d+ nm$', 'once')));
        if isempty(nmCols), continue; end
        Sp = table2array(T(:, cellstr(nmCols)));
        Sp = Sp(all(isfinite(Sp), 2), :);
        if isempty(Sp), continue; end
        Sp = (Sp - mean(Sp, 2)) ./ std(Sp, 0, 2);            % SNV per spectrum
        fullSpec(end+1, :) = mean(Sp, 1);                    %#ok<AGROW>
        fullNote(end+1)    = string(erase(files(k).name, ".csv"));  %#ok<AGROW>
        fullClass(end+1)   = ternary(f == 1, "Real", "Fake");       %#ok<AGROW>
    end
end
yFull = double(fullClass(:) == "Fake");
fprintf("Full-spectrum matrix: %d notes x %d wavelengths\n", size(fullSpec,1), size(fullSpec,2));
accFullSpec = table();
for nc = [3 5 10 20]
    [~, sc] = pca(fullSpec, "NumComponents", nc);
    a = looAcc(sc, yFull);
    accFullSpec = [accFullSpec; table(nc, a, 'VariableNames', {'PCAComponents','LOOAccPct'})]; %#ok<AGROW>
    fprintf("  full spectrum, %2d PCs : %.2f%%\n", nc, a);
end
fprintf("\n");

%% ---- Test 3: multi-region fusion ---------------------------------------
% notes present in every region (region 20 has the smaller note set)
common = notes;
for r = 2:3
    common = intersect(common, unique(S.(matlab.lang.makeValidName(regions(r).key)).note), "stable");
end
fprintf("Notes common to all three regions: %d\n", numel(common));

noteMeanOf = @(st, nm) mean(st.X(st.note == nm, :), 1, "omitnan");
Mreg = struct();
for r = 1:3
    st = S.(matlab.lang.makeValidName(regions(r).key));
    Mr = nan(numel(common), numel(featureNames));
    for i = 1:numel(common), Mr(i, :) = noteMeanOf(st, common(i)); end
    Mreg.(matlab.lang.makeValidName(regions(r).key)) = Mr;
end
yc = zeros(numel(common), 1);
for i = 1:numel(common)
    yc(i) = double(A.class(find(A.note == common(i), 1)) == "Fake");
end

combos = {
    "digit stroke only",              {"20"}
    "yellow only",                    {"yellow"}
    "white only",                     {"white"}
    "digit stroke + yellow",          {"20","yellow"}
    "digit stroke + white",           {"20","white"}
    "yellow + white",                 {"yellow","white"}
    "all three regions",              {"20","yellow","white"}
};
fusion = table();
for c = 1:size(combos, 1)
    Xc = [];
    for r = 1:numel(combos{c, 2})
        Xc = [Xc, Mreg.(matlab.lang.makeValidName(combos{c, 2}{r}))]; %#ok<AGROW>
    end
    a = looAcc(Xc, yc);
    fusion = [fusion; table(string(combos{c,1}), size(Xc,2), a, ...
        'VariableNames', {'FeatureSet','nFeatures','LOOAccPct'})]; %#ok<AGROW>
    fprintf("  %-24s (%2d features) : %.2f%%\n", combos{c,1}, size(Xc,2), a);
end

out = "D:\project\Result\result_recovery";
if ~exist(out, "dir"), mkdir(out); end
writetable(sweep,       fullfile(out, "repeat_sweep.csv"));
writetable(accFullSpec, fullfile(out, "full_spectrum.csv"));
writetable(fusion,      fullfile(out, "region_fusion.csv"));
fprintf("\nSaved to %s\n", out);

function o = ternary(c, a, b)
    if c, o = a; else, o = b; end
end
