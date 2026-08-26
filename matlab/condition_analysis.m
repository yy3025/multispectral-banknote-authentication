clc; clearvars; close all;

%% =========================
% Does the physical CONDITION of a banknote affect the system?
% (professor's feedback-6 question: "What condition are the notes in, and
% does this make any difference?")
%
% Run AFTER banknotes.m has been run for all three regions.
%
% Condition is measured by PROXY as the WITHIN-NOTE SPECTRAL SCATTER: how
% much the repeated measurements of one and the same note disagree. A note
% whose sampled area is worn, creased or unevenly inked presents a different
% surface from repeat to repeat, so its spectra scatter more. Every spectrum
% is SNV normalized before the standard deviation is taken, so this measures
% instability of spectral SHAPE, not brightness.
%
%   scatter_i = sqrt( mean_k ( std_k( spectra of note i )^2 ) )   over 9 features
%
% CRITICAL CONTROL: notes were not all measured the same number of times
% (7 to 47 repeats), and a note measured more often samples more of its own
% surface, which inflates the observed scatter. The raw scatter is therefore
% NOT comparable between notes. Every headline number below uses a
% REPEAT-MATCHED scatter instead: for each note, nMatch repeats are drawn at
% random without replacement, the scatter of that subset is computed, and
% the result is averaged over many draws. nMatch is the smallest repeat count
% in the region, so every note is described by exactly the same amount of
% data.
%
% Three questions are answered:
%   A. Does within-note scatter predict the classification margin?
%   B. Does within-note scatter differ between genuine and prop notes?
%   C. If it does, is it usable -- does adding it as a feature improve
%      leave-one-banknote-out accuracy?
%
% If a hand-graded condition file exists (D:\project\note_condition.csv with
% columns Note,Condition graded 1..3) the grade is tested directly as well,
% which is a stronger measurement than the proxy. An optional Region column
% restricts each grade to one region: the note sets are NOT shared between
% regions, so a grade assigned to "Real7" of the region-20 set must not be
% matched to the different banknote called "Real7" in the yellow/white set.
% =========================

set(groot, "defaultAxesFontSize", 12);
rng(0);   % reproducible subsampling / bootstrap

regions = {
    "20",     "D:\project\Result\result_20",     "Digit-20 stroke (purple ink)"
    "yellow", "D:\project\Result\result_yellow", "Uniform yellow patch"
    "white",  "D:\project\Result\result_white",  "Uniform white patch"
};
outFolder     = "D:\project\Result\result_condition";
conditionFile = "D:\project\note_condition.csv";   % optional, user-supplied
nDraw         = 400;      % random repeat-matched subsets per note
nBoot         = 10000;    % bootstrap resamples for the correlation CI

if ~exist(outFolder, "dir"), mkdir(outFolder); end

featureNames = ["F1_Clear", "F2_Clear", "F3_Clear", "F4_Clear", "F5_Clear", ...
                "F6_Clear", "F7_Clear", "F8_Clear", "NIR_Clear"];
channelLabels = ["F1 415nm", "F2 445nm", "F3 480nm", "F4 515nm", "F5 555nm", ...
                 "F6 590nm", "F7 630nm", "F8 680nm", "NIR"];
classColors  = [0.00 0.45 0.74; 0.85 0.33 0.10];   % Real, Fake
clsList      = ["Real", "Fake"];

haveGrades = isfile(conditionFile);
if haveGrades
    G = readtable(conditionFile, "VariableNamingRule", "preserve");
    G.Note = string(G.Note);
    fprintf("Hand-graded condition file found: %d notes.\n\n", height(G));
else
    fprintf("No hand-graded condition file at %s\n", conditionFile);
    fprintf("Running on the within-note scatter proxy only.\n\n");
end

allRows   = table();
corrTab   = table();
classCmp  = table();
chanTab   = table();
clfTab    = table();

for r = 1:size(regions, 1)
    regKey = regions{r, 1};
    resDir = regions{r, 2};
    regLab = string(regions{r, 3});
    wb     = fullfile(resDir, "banknote_results.xlsx");
    if ~isfile(wb)
        error("Workbook not found: %s (run banknotes.m for region ""%s"" first)", wb, regKey);
    end

    % --- sample-level data: one row per individual measurement ------------
    D = readtable(wb, "Sheet", "Dataset", "VariableNamingRule", "preserve");
    D.NoteName  = string(D.NoteName);
    D.ClassName = string(D.ClassName);
    keep = D.ClassName == "Real" | D.ClassName == "Fake";   % binary task only
    D    = D(keep, :);
    Xall = table2array(D(:, cellstr(featureNames)));

    % --- per-note margin (the outcome that matters) -----------------------
    R = readtable(wb, "Sheet", "Remeasure_priority", "VariableNamingRule", "preserve");
    R.Note = string(R.Note);

    notes   = R.Note;
    nNote   = numel(notes);
    repeats = zeros(nNote, 1);
    rawSc   = nan(nNote, 1);
    mchSc   = nan(nNote, 1);
    noteMu  = nan(nNote, numel(featureNames));
    chanStd = nan(nNote, numel(featureNames));

    idxOf = cell(nNote, 1);
    for i = 1:nNote
        idxOf{i}   = find(D.NoteName == notes(i));
        repeats(i) = numel(idxOf{i});
    end
    nMatch = min(repeats);

    for i = 1:nNote
        Xi = Xall(idxOf{i}, :);
        noteMu(i, :)  = mean(Xi, 1, "omitnan");
        chanStd(i, :) = std(Xi, 0, 1, "omitnan");
        rawSc(i)      = sqrt(mean(chanStd(i, :).^2, "omitnan"));

        % repeat-matched scatter: same amount of data for every note
        if repeats(i) == nMatch
            mchSc(i) = rawSc(i);
        else
            acc = 0;
            for b = 1:nDraw
                sel = randperm(repeats(i), nMatch);
                s   = std(Xi(sel, :), 0, 1, "omitnan");
                acc = acc + sqrt(mean(s.^2, "omitnan"));
            end
            mchSc(i) = acc / nDraw;
        end
    end

    T = table(repmat(regKey, nNote, 1), repmat(regLab, nNote, 1), notes, ...
        string(R.Class), repeats, rawSc, mchSc, R.TrueClassMargin, string(R.Status), ...
        'VariableNames', {'Region', 'RegionLabel', 'Note', 'Class', 'Repeats', ...
                          'ScatterRaw', 'ScatterMatched', 'Margin', 'Status'});

    if haveGrades
        % The three regions were NOT recorded on the same physical banknotes:
        % region 20 used one set of 24 genuine notes, the yellow and white
        % campaigns another set of 27. Note names therefore repeat across
        % regions while referring to different notes, so a grade may only be
        % matched inside the region it was assigned in. A Region column in the
        % grade file scopes each row; without one the grades apply everywhere,
        % which is only correct if a single note set was used throughout.
        Gr = G;
        if ismember("Region", string(G.Properties.VariableNames))
            Gr = G(string(G.Region) == string(regKey), :);
        end
        grade = nan(nNote, 1);
        if ~isempty(Gr)
            [tg, lg] = ismember(T.Note, Gr.Note);
            grade(tg) = Gr.Condition(lg(tg));
        end
        T.Condition = grade;
    end

    % margin z-scored WITHIN class so the classes can be pooled without the
    % pooled correlation merely picking up the class difference in margin
    T.MarginZ = nan(nNote, 1);
    for c = clsList
        m = T.Class == c;
        T.MarginZ(m) = (T.Margin(m) - mean(T.Margin(m))) ./ std(T.Margin(m));
    end
    allRows = [allRows; T];   %#ok<AGROW>

    fprintf("[%s] %d notes, repeats %d-%d (matched at n = %d)\n", ...
        regKey, nNote, min(repeats), max(repeats), nMatch);

    %% ---- A. scatter versus margin ---------------------------------------
    groups = {"Real", T.Class == "Real"; ...
              "Fake", T.Class == "Fake"; ...
              "Pooled", true(nNote, 1)};
    for g = 1:size(groups, 1)
        m = groups{g, 2};
        if g == 3, y = T.MarginZ(m); else, y = T.Margin(m); end
        xr = T.ScatterRaw(m);
        xm = T.ScatterMatched(m);
        n  = sum(m);

        [rhoR, pR] = corr(xr, y, "Type", "Spearman");
        [rhoM, pM] = corr(xm, y, "Type", "Spearman");
        rhoRep     = corr(xr, log(T.Repeats(m)), "Type", "Spearman");
        rhoRepM    = corr(xm, log(T.Repeats(m)), "Type", "Spearman");

        bs = nan(nBoot, 1);
        for b = 1:nBoot
            k = randi(n, n, 1);
            if numel(unique(xm(k))) > 2 && numel(unique(y(k))) > 2
                bs(b) = corr(xm(k), y(k), "Type", "Spearman");
            end
        end
        ci = prctile(bs(~isnan(bs)), [2.5 97.5]);

        corrTab = [corrTab; table(regKey, regLab, string(groups{g, 1}), n, nMatch, ...
            rhoR, pR, rhoM, pM, ci(1), ci(2), rhoRep, rhoRepM, ...
            'VariableNames', {'Region', 'RegionLabel', 'Group', 'N', 'nMatch', ...
            'Rho_raw', 'p_raw', 'Rho_matched', 'p_matched', ...
            'CI_low_matched', 'CI_high_matched', ...
            'Rho_rawScatter_vs_Repeats', 'Rho_matchedScatter_vs_Repeats'})];  %#ok<AGROW>
    end

    %% ---- B. is the scatter itself class-discriminative? -----------------
    isR = T.Class == "Real";
    for v = ["ScatterRaw", "ScatterMatched"]
        a = T.(v)(isR);  b2 = T.(v)(~isR);
        d = (mean(a) - mean(b2)) / sqrt((var(a) + var(b2)) / 2);
        p = ranksum(a, b2);
        classCmp = [classCmp; table(regKey, regLab, v, nMatch, numel(a), numel(b2), ...
            mean(a), mean(b2), d, p, ...
            'VariableNames', {'Region', 'RegionLabel', 'Measure', 'nMatch', ...
            'nReal', 'nFake', 'MeanReal', 'MeanFake', 'CohenD', 'p_ranksum'})];  %#ok<AGROW>
    end

    % per-channel breakdown of the instability (matched notes only would be
    % ideal; chanStd is used directly here to show WHERE the scatter sits)
    for k = 1:numel(featureNames)
        a = chanStd(isR, k);  b2 = chanStd(~isR, k);
        d = (mean(a) - mean(b2)) / sqrt((var(a) + var(b2)) / 2);
        chanTab = [chanTab; table(regKey, regLab, channelLabels(k), ...
            mean(a), mean(b2), d, ...
            'VariableNames', {'Region', 'RegionLabel', 'Channel', ...
            'StdReal', 'StdFake', 'CohenD'})];  %#ok<AGROW>
    end

    %% ---- C. is it usable? leave-one-banknote-out with/without scatter ---
    yBin = double(T.Class == "Fake");
    sets = {
        "9 channels (baseline)",        noteMu
        "9 channels + scatter",         [noteMu, T.ScatterMatched]
        "scatter only (1 feature)",     T.ScatterMatched
    };
    for s = 1:size(sets, 1)
        Xs = sets{s, 2};
        for kern = ["linear", "rbf"]
            pred = nan(nNote, 1);
            for i = 1:nNote
                tr = true(nNote, 1); tr(i) = false;
                if kern == "linear"
                    mdl = fitcsvm(Xs(tr, :), yBin(tr), "KernelFunction", "linear", ...
                        "Standardize", true);
                else
                    mdl = fitcsvm(Xs(tr, :), yBin(tr), "KernelFunction", "rbf", ...
                        "KernelScale", "auto", "Standardize", true);
                end
                pred(i) = predict(mdl, Xs(i, :));
            end
            acc  = mean(pred == yBin) * 100;
            fp   = sum(pred == 1 & yBin == 0) / max(1, sum(yBin == 0)) * 100;
            fn   = sum(pred == 0 & yBin == 1) / max(1, sum(yBin == 1)) * 100;
            clfTab = [clfTab; table(regKey, regLab, sets{s, 1}, kern, ...
                size(Xs, 2), acc, fp, fn, ...
                'VariableNames', {'Region', 'RegionLabel', 'FeatureSet', 'Kernel', ...
                'nFeatures', 'LOOAccuracyPct', 'FalsePositivePct', 'FalseNegativePct'})];  %#ok<AGROW>
        end
    end
end

fprintf("\n===== A. Within-note scatter versus classification margin =====\n");
disp(corrTab(:, {'Region', 'Group', 'N', 'Rho_raw', 'p_raw', 'Rho_matched', ...
                 'p_matched', 'CI_low_matched', 'CI_high_matched'}));

fprintf("\n===== B. Within-note scatter: genuine versus prop notes =====\n");
disp(classCmp);

fprintf("\n===== C. Leave-one-banknote-out accuracy with and without the scatter =====\n");
disp(clfTab);

%% --- optional: hand-graded condition -------------------------------------
gradeSummary = table();
if haveGrades
    for r = 1:size(regions, 1)
        m0 = allRows.Region == regions{r, 1} & isfinite(allRows.Condition);
        for c = ["Real", "Fake", "Pooled"]
            if c == "Pooled"
                m = m0;  y = allRows.MarginZ(m);
            else
                m = m0 & allRows.Class == c;  y = allRows.Margin(m);
            end
            gr = allRows.Condition(m);
            if numel(unique(gr)) < 2 || numel(gr) < 6, continue; end
            [rhoG, pG]   = corr(gr, y, "Type", "Spearman");
            pKW          = kruskalwallis(y, gr, "off");
            [rhoGS, pGS] = corr(gr, allRows.ScatterMatched(m), "Type", "Spearman");
            gradeSummary = [gradeSummary; table(string(regions{r, 1}), ...
                string(regions{r, 3}), c, numel(gr), rhoG, pG, pKW, rhoGS, pGS, ...
                'VariableNames', {'Region', 'RegionLabel', 'Group', 'N', ...
                'Rho_Grade_vs_Margin', 'p', 'p_KruskalWallis', ...
                'Rho_Grade_vs_Scatter', 'p_GradeScatter'})];  %#ok<AGROW>
        end
    end
    fprintf("\n===== Hand-graded condition versus margin =====\n");
    disp(gradeSummary);
end

%% --- Figure 1: scatter versus margin -------------------------------------
fig1 = figure("Position", [60 60 1150 430]);
tl = tiledlayout(fig1, 1, 3, "TileSpacing", "compact", "Padding", "compact");
for r = 1:size(regions, 1)
    ax = nexttile(tl); hold(ax, "on");
    m0 = allRows.Region == regions{r, 1};
    for ci = 1:2
        mm = m0 & allRows.Class == clsList(ci);
        scatter(ax, allRows.ScatterMatched(mm), allRows.Margin(mm), 46, ...
            classColors(ci, :), "filled", "MarkerFaceAlpha", 0.75);
    end
    row = corrTab(corrTab.Region == regions{r, 1} & corrTab.Group == "Pooled", :);
    title(ax, {char(regions{r, 3}), ...
        sprintf("pooled \\rho = %.2f (p = %.2f)", row.Rho_matched, row.p_matched)});
    xlabel(ax, "Repeat-matched within-note scatter");
    if r == 1
        ylabel(ax, "Margin towards true class");
        legend(ax, {"Genuine", "Prop (fake)"}, "Location", "southwest");
    end
    grid(ax, "on"); hold(ax, "off");
end
title(tl, "Measurement repeatability does not predict classification confidence", ...
    "FontWeight", "bold");
saveFig(fig1, fullfile(outFolder, "fig_condition_scatter_vs_margin.png"));

%% --- Figure 2: the scatter itself, per class and region ------------------
fig2 = figure("Position", [60 60 820 470]);
hold on;
pos = 0; xt = []; xl = strings(0, 1);
for r = 1:3
    for ci = 1:2
        m = allRows.Region == regions{r, 1} & allRows.Class == clsList(ci);
        v = allRows.ScatterMatched(m);
        pos = pos + 1;
        scatter(pos + (rand(numel(v), 1) - 0.5) * 0.30, v, 36, ...
            classColors(ci, :), "filled", "MarkerFaceAlpha", 0.7);
        plot(pos + [-0.32 0.32], [median(v) median(v)], "k-", "LineWidth", 2.2);
        xt(end+1) = pos;                    %#ok<AGROW>
        xl(end+1) = clsList(ci);            %#ok<AGROW>
    end
    row = classCmp(classCmp.Region == regions{r, 1} & ...
                   classCmp.Measure == "ScatterMatched", :);
    text(pos - 0.5, max(allRows.ScatterMatched) * 0.97, ...
        sprintf("|d| = %.2f", abs(row.CohenD)), "HorizontalAlignment", "center", ...
        "FontSize", 11, "FontWeight", "bold");
    pos = pos + 0.7;
end
xticks(xt); xticklabels(xl);
set(gca, "YScale", "log");
ylabel("Repeat-matched within-note scatter");
title({"Measurement repeatability per note (bar = median, log scale)", ...
       "digit-20 stroke  |  yellow patch  |  white patch"});
grid on; hold off;
saveFig(fig2, fullfile(outFolder, "fig_condition_scatter_by_class.png"));

%% --- Figure 3: per-channel instability on the digit stroke ---------------
fig3 = figure("Position", [60 60 760 460]);
sub = chanTab(chanTab.Region == "20", :);
bar([sub.StdReal, sub.StdFake]);
xticks(1:numel(channelLabels)); xticklabels(channelLabels); xtickangle(45);
ylabel("Within-note standard deviation (SNV units)");
legend(["Genuine", "Prop (fake)"], "Location", "northoutside", "Orientation", "horizontal");
title("Digit-20 stroke: where the repeat-to-repeat instability sits");
grid on;
saveFig(fig3, fullfile(outFolder, "fig_condition_channels.png"));

%% --- write tables --------------------------------------------------------
writetable(allRows,  fullfile(outFolder, "condition_per_note.csv"));
writetable(corrTab,  fullfile(outFolder, "condition_correlations.csv"));
writetable(classCmp, fullfile(outFolder, "condition_class_comparison.csv"));
writetable(chanTab,  fullfile(outFolder, "condition_per_channel.csv"));
writetable(clfTab,   fullfile(outFolder, "condition_classifier_test.csv"));
xlsxPath = fullfile(outFolder, "condition_analysis.xlsx");
if isfile(xlsxPath), delete(xlsxPath); end
writetable(allRows,  xlsxPath, "Sheet", "Per_note");
writetable(corrTab,  xlsxPath, "Sheet", "Correlations");
writetable(classCmp, xlsxPath, "Sheet", "Class_comparison");
writetable(chanTab,  xlsxPath, "Sheet", "Per_channel");
writetable(clfTab,   xlsxPath, "Sheet", "Classifier_test");
if haveGrades && ~isempty(gradeSummary)
    writetable(gradeSummary, fullfile(outFolder, "condition_grade_summary.csv"));
    writetable(gradeSummary, xlsxPath, "Sheet", "Hand_graded");
end

if ~haveGrades
    uNotes = unique(allRows(:, {'Note', 'Class'}), "rows");
    uNotes.Condition = repmat("", height(uNotes), 1);
    tmpl = fullfile(outFolder, "note_condition_TEMPLATE.csv");
    writetable(uNotes, tmpl);
    fprintf("\nTemplate for hand-graded condition written to:\n  %s\n", tmpl);
    fprintf("Fill Condition with 1 (crisp) / 2 (some wear) / 3 (heavily worn),\n");
    fprintf("save as %s, then re-run.\n", conditionFile);
end

fprintf("\nCondition analysis saved to:\n%s\n", outFolder);


function saveFig(fig, filePath)
    % The interactive axes toolbar is otherwise baked into the exported PNG.
    axs = findall(fig, "Type", "axes");
    for a = 1:numel(axs)
        try, axs(a).Toolbar.Visible = "off"; catch, end   %#ok<NOCOM>
    end
    try
        exportgraphics(fig, filePath, "Resolution", 200);
    catch
        print(fig, char(erase(string(filePath), ".png")), "-dpng", "-r200");
    end
end
