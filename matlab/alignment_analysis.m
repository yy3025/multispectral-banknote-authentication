clc; clearvars; close all;

%% =========================
% What is the effect of MISALIGNMENT and MISORIENTATION?
% (professor's feedback-6 question, currently still "future work" in the report)
%
% The report argues qualitatively that a uniform region tolerates placement
% error while a fine printed feature does not. This script measures it.
%
% EXPECTED DATA LAYOUT (one CSV per banknote, same format as every other
% recording in this project):
%
%   D:\project\data_align\<region>\<condition>\<class>\CSV\<Note>.csv
%
%     <region>     r20     = the digit-"20" stroke   (baseline: data_20)
%                  yellow  = the uniform yellow patch (baseline: data_yellow)
%                  white   = the unprinted white area (baseline: data_white)
%     <condition>  off0    = sensor centred on the region (the reference)
%                  off0p5  = displaced 0.5 mm   ("p" = decimal point)
%                  off1    = displaced 1 mm
%                  off1p5  = displaced 1.5 mm
%                  off2    = displaced 2 mm
%                  rot90   = note rotated 90 deg in plane, sensor recentred
%                  rot180  = note rotated 180 deg in plane, sensor recentred
%     <class>      real | fake
%
% Only the conditions that actually exist are analysed, so the experiment can
% be collected and re-run incrementally.
%
% METHOD. A classifier is trained on the EXISTING baseline dataset with the
% notes used in this experiment REMOVED, so it has never seen any of the test
% notes in any condition. Every (note, condition) pair is then averaged into
% one spectrum and pushed through that classifier. Three things are reported
% per condition:
%   1. note-level accuracy               - does the decision survive?
%   2. mean margin towards the true class - how much confidence is lost?
%   3. displacement from the note's own off0 mean - how far the spectrum moved,
%      which is classifier-independent and therefore the primary physical result
%   4. within-note scatter                - does misalignment also destabilise
%      the repeats (relevant to the scatter feature of sec:condition)
% =========================

set(groot, "defaultAxesFontSize", 12);
rng(0);

alignRoot = "D:\project\data_align";
outFolder = "D:\project\Result\result_alignment";

regions = {
    "r20",    "D:\project\data_20",     "Digit-20 stroke (purple ink)"
    "yellow", "D:\project\data_yellow", "Uniform yellow patch"
    "white",  "D:\project\data_white",  "Unprinted white area"
};

channelLabels = ["F1 415nm", "F2 445nm", "F3 480nm", "F4 515nm", "F5 555nm", ...
                 "F6 590nm", "F7 630nm", "F8 680nm", "NIR"];
classList   = ["Real", "Fake"];
classColors = [0.00 0.45 0.74; 0.85 0.33 0.10];

if ~isfolder(alignRoot)
    printProtocol(alignRoot);
    return;
end
if ~exist(outFolder, "dir"), mkdir(outFolder); end

rows = table();

for r = 1:size(regions, 1)
    regKey  = string(regions{r, 1});
    baseDir = string(regions{r, 2});
    regLab  = string(regions{r, 3});
    regDir  = fullfile(alignRoot, regKey);
    if ~isfolder(regDir), continue; end

    % ---- which conditions were recorded for this region ------------------
    d     = dir(regDir);
    conds = string({d([d.isdir]).name});
    conds = conds(~ismember(conds, [".", ".."]));
    if isempty(conds), continue; end

    % ---- collect the test set --------------------------------------------
    T = table();
    for c = 1:numel(conds)
        for k = 1:numel(classList)
            cls = classList(k);
            S   = loadNoteSet(fullfile(regDir, conds(c), lower(cls)));
            for i = 1:numel(S)
                T = [T; table(conds(c), cls, S(i).name, S(i).repeats, ...
                              S(i).scatter, S(i).mean, ...
                     'VariableNames', {'Condition', 'Class', 'Note', ...
                                       'Repeats', 'Scatter', 'Mean'})]; %#ok<AGROW>
            end
        end
    end
    if isempty(T)
        fprintf("Region %s: no CSV files found under %s\n", regKey, regDir);
        continue;
    end

    testNotes = unique(T.Note);

    % ---- train on the baseline dataset, excluding those notes ------------
    Sreal = loadNoteSet(fullfile(baseDir, "real"));
    Sfake = loadNoteSet(fullfile(baseDir, "fake"));
    if isempty(Sreal) || isempty(Sfake)
        warning("Baseline data not found for region %s at %s -- skipped.", regKey, baseDir);
        continue;
    end
    Xtr = [vertcat(Sreal.mean); vertcat(Sfake.mean)];
    Ytr = [repmat("Real", numel(Sreal), 1); repmat("Fake", numel(Sfake), 1)];
    Ntr = [string({Sreal.name})'; string({Sfake.name})'];

    keep = ~ismember(Ntr, testNotes);
    fprintf("\n########## %s ##########\n", regLab);
    fprintf("Baseline notes: %d total, %d used for training (%d held out as test notes)\n", ...
            numel(keep), sum(keep), sum(~keep));
    % Print the names actually withheld. The note sets differ between regions,
    % so a test note named after a note of the OTHER set would silently remove
    % the wrong banknote from training -- this line makes that visible.
    fprintf("Held out of training: %s\n", strjoin(sort(Ntr(~keep))', ", "));
    missing = setdiff(testNotes, Ntr);
    if ~isempty(missing)
        warning(['Test note(s) %s do not exist in the baseline set for region %s. ' ...
                 'Check that the alignment notes come from this region''s own note set.'], ...
                strjoin(missing, ", "), regKey);
    end
    fprintf("Conditions recorded: %s\n", strjoin(sort(conds), ", "));

    mdlLin = fitcsvm(Xtr(keep, :), Ytr(keep), "KernelFunction", "linear", ...
                     "ClassNames", classList);
    mdlRbf = fitcsvm(Xtr(keep, :), Ytr(keep), "KernelFunction", "rbf", ...
                     "KernelScale", "auto", "ClassNames", classList);

    % ---- predict every (note, condition) ---------------------------------
    [predL, scL] = predict(mdlLin, T.Mean);
    [predR, scR] = predict(mdlRbf, T.Mean);
    isFake  = T.Class == "Fake";
    margL   = scL(:, 1); margL(isFake) = scL(isFake, 2);   % towards true class
    margR   = scR(:, 1); margR(isFake) = scR(isFake, 2);

    % ---- displacement from each note's own off0 spectrum -----------------
    disp0 = nan(height(T), 1);
    for i = 1:height(T)
        ref = T.Mean(T.Note == T.Note(i) & T.Condition == "off0", :);
        if ~isempty(ref)
            disp0(i) = norm(T.Mean(i, :) - ref(1, :));
        end
    end

    % ---- SANITY CHECK: does the reference condition reproduce the note's
    % baseline spectrum at all? Each condition here is measured at ONE sensor
    % placement, whereas a baseline note mean averages over many placements.
    % On a region where placement matters, one placement is a single draw from
    % that distribution and can sit far from its mean, which makes the accuracy
    % and margin columns meaningless. Flag it rather than let it pass silently.
    dBase = nan(height(T), 1);
    for i = 1:height(T)
        b = Xtr(Ntr == T.Note(i), :);
        if ~isempty(b), dBase(i) = norm(T.Mean(i, :) - b(1, :)); end
    end
    Dcross  = pdist2(Xtr(Ytr == "Real", :), Xtr(Ytr == "Fake", :));
    minCross = min(Dcross(:));
    dRef = mean(dBase(T.Condition == "off0"), "omitnan");
    fprintf("Reference check: mean distance from off0 to the note's own baseline mean = %.4f\n", dRef);
    fprintf("                 closest genuine-prop pair in the baseline set          = %.4f\n", minCross);
    if dRef > minCross
        warning(['The off0 reference does not reproduce the baseline spectra: it moves ' ...
                 'notes further (%.3f) than the closest opposite-class pair (%.3f). The ' ...
                 'accuracy and margin columns for region %s are NOT interpretable. Each ' ...
                 'condition needs several INDEPENDENT re-placements, not repeated readings ' ...
                 'at one fixed placement.'], dRef, minCross, regKey);
    end

    [ctype, cval] = parseCondition(T.Condition);

    rows = [rows; [table(repmat(regKey, height(T), 1), ...
                         repmat(regLab, height(T), 1), ...
                         T.Condition, ctype, cval, T.Note, T.Class, ...
                         T.Repeats, T.Scatter, disp0, dBase, ...
                         string(predL), margL, string(predR), margR, ...
                'VariableNames', {'Region', 'RegionLabel', 'Condition', ...
                                  'CondType', 'CondValue', 'Note', 'Class', ...
                                  'Repeats', 'Scatter', 'DisplacementFromOff0', ...
                                  'DistanceFromBaseline', ...
                                  'PredLinear', 'MarginLinear', ...
                                  'PredRBF', 'MarginRBF'}), ...
                   array2table(T.Mean, 'VariableNames', cellstr("Mean_" + channelLabels))]];  %#ok<AGROW>
end

if isempty(rows)
    fprintf("\nNo alignment data found under %s\n", alignRoot);
    printProtocol(alignRoot);
    return;
end

%% ---- per-condition summary ----------------------------------------------
summary = table();
[g, rg, cd] = findgroups(rows.Region, rows.Condition);
for i = 1:max(g)
    m   = g == i;
    sub = rows(m, :);
    summary = [summary; table(rg(i), string(sub.RegionLabel(1)), cd(i), ...
        string(sub.CondType(1)), sub.CondValue(1), height(sub), ...
        100 * mean(sub.PredLinear == sub.Class), ...
        100 * mean(sub.PredRBF    == sub.Class), ...
        mean(sub.MarginLinear), ...
        mean(sub.MarginLinear(sub.Class == "Real")), ...
        mean(sub.MarginLinear(sub.Class == "Fake")), ...
        mean(sub.DisplacementFromOff0, "omitnan"), ...
        mean(sub.DistanceFromBaseline, "omitnan"), ...
        mean(sub.Scatter, "omitnan"), ...
        'VariableNames', {'Region', 'RegionLabel', 'Condition', 'CondType', ...
                          'CondValue', 'N', 'AccLinearPct', 'AccRBFPct', ...
                          'MeanMargin', 'MeanMarginReal', 'MeanMarginFake', ...
                          'MeanDisplacement', 'MeanDistFromBaseline', ...
                          'MeanScatter'})];  %#ok<AGROW>
end
summary = sortrows(summary, {'Region', 'CondType', 'CondValue'});

fprintf("\n===== Accuracy, margin and spectral displacement by condition =====\n");
disp(summary);

%% ---- figures -------------------------------------------------------------
saveTable(rows,    fullfile(outFolder, "alignment_predictions.csv"));
saveTable(summary, fullfile(outFolder, "alignment_summary.csv"));

plotVersus(summary, "off", "AccLinearPct", "Note-level accuracy (%)", ...
    "Accuracy vs lateral displacement", ...
    fullfile(outFolder, "fig_align_accuracy.png"), [0 105]);
plotVersus(summary, "off", "MeanDisplacement", "Distance from centred spectrum", ...
    "Spectral displacement vs lateral displacement", ...
    fullfile(outFolder, "fig_align_displacement.png"), []);
plotVersus(summary, "off", "MeanMargin", "Mean margin towards true class", ...
    "Classifier margin vs lateral displacement", ...
    fullfile(outFolder, "fig_align_margin.png"), []);
plotVersus(summary, "off", "MeanScatter", "Within-note scatter", ...
    "Repeat stability vs lateral displacement", ...
    fullfile(outFolder, "fig_align_scatter.png"), []);

if any(summary.CondType == "rot")
    plotRotation(summary, fullfile(outFolder, "fig_align_rotation.png"));
end

% one workbook, like every other analysis in this project
wb = fullfile(outFolder, "alignment_analysis.xlsx");
if isfile(wb), delete(wb); end
writetable(summary, wb, "Sheet", "Summary");
writetable(rows,    wb, "Sheet", "Predictions");

fprintf("\nAlignment analysis saved to:\n%s\n", outFolder);


%% ======================= local functions ================================

function [ctype, cval] = parseCondition(cond)
    cond  = string(cond);
    ctype = strings(numel(cond), 1);
    cval  = nan(numel(cond), 1);
    for i = 1:numel(cond)
        s = cond(i);
        if startsWith(s, "off")
            ctype(i) = "off";
            cval(i)  = str2double(strrep(extractAfter(s, "off"), "p", "."));
        elseif startsWith(s, "rot")
            ctype(i) = "rot";
            cval(i)  = str2double(extractAfter(s, "rot"));
        else
            ctype(i) = "other";
        end
    end
    % off0 is also the 0 deg rotation reference
    cval(ctype == "off" & cval == 0) = 0;
end


function plotVersus(summary, wantType, yvar, ylab, ttl, outPath, ylimits)
    m = summary.CondType == wantType & ~isnan(summary.(yvar));
    if ~any(m), return; end
    S = sortrows(summary(m, :), "CondValue");

    fig = figure("Color", "w", "Position", [80 80 640 460]);
    ax  = axes(fig); hold(ax, "on"); grid(ax, "on");
    regs = unique(S.Region, "stable");
    % distinct line styles so that coincident curves stay distinguishable
    mk   = ["-o", "--s", ":^"];
    for i = 1:numel(regs)
        k = S.Region == regs(i);
        plot(ax, S.CondValue(k), S.(yvar)(k), mk(min(i, numel(mk))), ...
             "LineWidth", 1.6, "MarkerSize", 7, ...
             "DisplayName", S.RegionLabel(find(k, 1)));
    end
    xlabel(ax, "Lateral displacement from the centred position (mm)");
    ylabel(ax, ylab);
    title(ax, ttl);
    if ~isempty(ylimits), ylim(ax, ylimits); end
    legend(ax, "Location", "southwest");
    ax.Toolbar.Visible = "off";
    exportgraphics(fig, outPath, "Resolution", 200);
    close(fig);
end


function plotRotation(summary, outPath)
    m = summary.CondType == "rot" | (summary.CondType == "off" & summary.CondValue == 0);
    S = sortrows(summary(m, :), "CondValue");

    fig = figure("Color", "w", "Position", [80 80 900 400]);
    tl  = tiledlayout(fig, 1, 2, "TileSpacing", "compact", "Padding", "compact");

    ax1 = nexttile(tl); hold(ax1, "on"); grid(ax1, "on");
    ax2 = nexttile(tl); hold(ax2, "on"); grid(ax2, "on");
    regs = unique(S.Region, "stable");
    mk   = ["-o", "--s", ":^"];
    for i = 1:numel(regs)
        k  = S.Region == regs(i);
        st = mk(min(i, numel(mk)));
        plot(ax1, S.CondValue(k), S.AccLinearPct(k), st, "LineWidth", 1.6, ...
             "MarkerSize", 7, "DisplayName", S.RegionLabel(find(k, 1)));
        plot(ax2, S.CondValue(k), S.MeanDisplacement(k), st, "LineWidth", 1.6, ...
             "MarkerSize", 7, "DisplayName", S.RegionLabel(find(k, 1)));
    end
    xlabel(ax1, "In-plane rotation of the note (deg)");
    ylabel(ax1, "Note-level accuracy (%)"); ylim(ax1, [0 105]);
    title(ax1, "Accuracy vs orientation");
    legend(ax1, "Location", "southwest");
    xlabel(ax2, "In-plane rotation of the note (deg)");
    ylabel(ax2, "Distance from 0 deg spectrum");
    title(ax2, "Spectral displacement vs orientation");
    ax1.Toolbar.Visible = "off"; ax2.Toolbar.Visible = "off";
    exportgraphics(fig, outPath, "Resolution", 200);
    close(fig);
end


function saveTable(T, path)
    W = T;
    for v = string(W.Properties.VariableNames)
        if iscategorical(W.(v)), W.(v) = string(W.(v)); end
    end
    writetable(W, path);
end


function printProtocol(alignRoot)
    fprintf("\nNo alignment data yet. Expected layout:\n\n");
    fprintf("  %s\\<region>\\<condition>\\<class>\\CSV\\<Note>.csv\n\n", alignRoot);
    fprintf("  <region>    r20 | yellow | white\n");
    fprintf("  <condition> off0 off0p5 off1 off1p5 off2   (lateral displacement, mm)\n");
    fprintf("              rot90 rot180                   (in-plane rotation, deg)\n");
    fprintf("  <class>     real | fake\n\n");
    fprintf("Minimum useful set: regions r20 and yellow, conditions off0/off1/off2/rot90/rot180,\n");
    fprintf("4 genuine + 4 prop notes, 10 repeats each. See EXPERIMENT_PROTOCOL.md.\n");
end
