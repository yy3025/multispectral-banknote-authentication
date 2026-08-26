clc; clearvars; close all;

% Larger default font: the figure is scaled down in the report (see the same
% note in banknotes.m).
set(groot, "defaultAxesFontSize", 12);

%% =========================
% Region comparison: digit-"20" stroke vs uniform yellow patch
%
% Reads the merged result workbooks produced by banknotes.m for each
% measurement region and quantifies the professor's region-sensitivity
% question: how much does the CHOICE of measurement area change the
% Real-vs-Fake separability and the classifier performance?
% Run AFTER banknotes.m has been run for both regions.
% =========================

regions = {
    "20",     "D:\project\Result\result_20",     "Digit-20 stroke (purple ink)";
    "yellow", "D:\project\Result\result_yellow", "Uniform yellow patch";
    "white",  "D:\project\Result\result_white",  "Uniform white patch"
};
outFolder = "D:\project\Result\result_region_comparison";
if ~exist(outFolder, "dir"), mkdir(outFolder); end

featureOrder  = ["F1_Clear", "F2_Clear", "F3_Clear", "F4_Clear", ...
                 "F5_Clear", "F6_Clear", "F7_Clear", "F8_Clear", "NIR_Clear"];
channelLabels = ["F1 415nm", "F2 445nm", "F3 480nm", "F4 515nm", ...
                 "F5 555nm", "F6 590nm", "F7 630nm", "F8 680nm", "NIR"];

nReg    = size(regions, 1);
dMat    = nan(numel(featureOrder), nReg);   % |Cohen's d| per channel per region
regName = strings(nReg, 1);

% One column of summary metrics per region.
metricNames = ["Real notes"; "Fake notes"; "Samples"; ...
    "Single-stage acc (%)"; "Final (deployed) acc (%)"; ...
    "Linear SVM LOO acc (%)"; "RBF SVM LOO acc (%)"; "Cascade LOO acc (%)"; ...
    "Sample-level grouped CV acc (%)"; "Deployed model"; ...
    "Borderline notes (Stage-2 band)"; "Max |Cohen's d|"; "Mean |Cohen's d|"; ...
    "Best channel"; "Min Real-Fake note distance"];
metricVals = strings(numel(metricNames), nReg);

for r = 1:nReg
    resFolder  = regions{r, 2};
    regName(r) = string(regions{r, 3});
    wb         = fullfile(resFolder, "banknote_results.xlsx");
    if ~isfile(wb)
        error("Workbook not found: %s (run banknotes.m for region ""%s"" first)", ...
            wb, regions{r, 1});
    end

    % --- Channel separability (binary Real vs Fake pair only) -------------
    chd = readtable(wb, "Sheet", "Channel_difference", "VariableNamingRule", "preserve");
    chd = chd(string(chd.Pair) == "Real vs Fake", :);
    for k = 1:numel(featureOrder)
        row = string(chd.Feature) == featureOrder(k);
        dMat(k, r) = abs(chd.CohenD(row));
    end

    % --- Classifier metrics ----------------------------------------------
    met  = readtable(wb, "Sheet", "SVM_metrics", "VariableNamingRule", "preserve");
    getA = @(name) met.AccuracyPercent(startsWith(string(met.Model), name));
    sm   = readtable(wb, "Sheet", "Summary", "VariableNamingRule", "preserve");

    % --- Borderline notes (inside the Stage-2 review band) ----------------
    np      = readtable(wb, "Sheet", "Note_predictions", "VariableNamingRule", "preserve");
    nBorder = sum(logical(np.Uncertain));

    % --- Closest Real-Fake pair (hardest cross-class pair) ----------------
    cp = readtable(wb, "Sheet", "Closest_cross_pairs", "VariableNamingRule", "preserve");
    cp = cp(string(cp.PairType) == "Real-Fake", :);
    minDist = min(cp.EuclideanDistance);

    [dMax, kBest] = max(dMat(:, r));
    metricVals(:, r) = [
        string(sm.RealNotes); string(sm.FakeNotes); string(sm.Samples);
        compose("%.2f", sm.SingleStageAccPct); compose("%.2f", sm.FinalAccPct);
        compose("%.2f", getA("Linear SVM")); compose("%.2f", getA("RBF SVM"));
        compose("%.2f", getA("Cascade SVM")); compose("%.2f", getA("SampleLevel_GroupedCV"));
        string(sm.ChosenMethod); string(nBorder);
        compose("%.2f", dMax); compose("%.2f", mean(dMat(:, r)));
        channelLabels(kBest); compose("%.3f", minDist)];
end

comparisonTable = [table(metricNames, 'VariableNames', {'Metric'}), ...
                   array2table(metricVals, "VariableNames", cellstr(regName))];
disp("Region comparison (Real vs Fake):");
disp(comparisonTable);
writetable(comparisonTable, fullfile(outFolder, "region_comparison.xlsx"), ...
    "Sheet", "Comparison");

dTable = [table(featureOrder(:), channelLabels(:), ...
              'VariableNames', {'Feature', 'Channel'}), ...
          array2table(dMat, "VariableNames", cellstr(regName))];
writetable(dTable, fullfile(outFolder, "region_comparison.xlsx"), ...
    "Sheet", "CohensD_per_channel");

% --- Figure: per-channel separability, one bar group per channel ----------
fig = figure;
bar(dMat);
xlabel("AS7341 Channel"); ylabel("|Cohen's d| (Real vs Fake separability)");
title(sprintf("Separability of the %d Measurement Regions", nReg));
xticks(1:numel(channelLabels)); xticklabels(channelLabels); xtickangle(45);
ylim([0, max(dMat(:)) * 1.18]);   % headroom so the top legend clears the tallest bar
legend(cellstr(regName), "Location", "north"); grid on;
try
    exportgraphics(fig, fullfile(outFolder, "fig_region_separability.png"), ...
        "Resolution", 200);
catch
    print(fig, char(fullfile(outFolder, "fig_region_separability")), "-dpng", "-r200");
end

fprintf("Region comparison saved to:\n%s\n", outFolder);
