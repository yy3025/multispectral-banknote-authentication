clc; clearvars; close all;

% Larger default font + a narrower figure: both figures are placed at roughly
% half the text width in the report, so at the old 740 px / 10 pt they printed
% at about 4 pt. See the same note in banknotes.m.
set(groot, "defaultAxesFontSize", 12);
% Generate dedicated per-note spectra figures for the report subsections:
%   fig_20_per_note_spectra : genuine vs current fake (digit-"20" stroke)
%   fig_v1_per_note_spectra : genuine vs first-generation (V1) fake
% Both read the per-note SNV mean spectra from the "20"-region workbook and
% are saved into BOTH the English and Chinese report picture folders.

wb   = "D:\project\Result\result_20\banknote_results.xlsx";
T    = readtable(wb, "Sheet", "Note_mean_spectra", "VariableNamingRule", "preserve");
feat = ["F1_Clear","F2_Clear","F3_Clear","F4_Clear","F5_Clear", ...
        "F6_Clear","F7_Clear","F8_Clear","NIR_Clear"];
chLab = ["F1 415nm","F2 445nm","F3 480nm","F4 515nm","F5 555nm", ...
         "F6 590nm","F7 630nm","F8 680nm","NIR"];
X   = table2array(T(:, cellstr(feat)));
cls = string(T.Class);

colReal = [0.00 0.45 0.74];
colFake = [0.85 0.33 0.10];
colV1   = [0.49 0.18 0.56];
outdirs = ["D:\project\Report\picture", "D:\project\Report_zh\picture"];

plotPair(X, cls, chLab, "Real", "Genuine", colReal, "Fake", "Current fake", colFake, ...
    "Genuine vs current fake - digit-20 stroke (per-note SNV spectra)", ...
    "fig_20_per_note_spectra.png", outdirs);

plotPair(X, cls, chLab, "Real", "Genuine", colReal, "FakeV1", "First-generation (V1) fake", colV1, ...
    "Genuine vs first-generation (V1) fake (per-note SNV spectra)", ...
    "fig_v1_per_note_spectra.png", outdirs);

fprintf("Subsection spectra figures written to both picture folders.\n");

function plotPair(X, cls, chLab, cA, nameA, colA, cB, nameB, colB, ttl, fname, outdirs)
    fig = figure("Position", [100 100 600 430]); hold on;
    idxA = find(cls == cA);
    idxB = find(cls == cB);
    for i = idxA(:)', plot(1:9, X(i,:), '-', "Color", [colA 0.30], "LineWidth", 1.0); end
    for i = idxB(:)', plot(1:9, X(i,:), '-', "Color", [colB 0.30], "LineWidth", 1.0); end
    mA = mean(X(idxA,:), 1, "omitnan");
    mB = mean(X(idxB,:), 1, "omitnan");
    hA = plot(1:9, mA, '-o', "Color", colA, "LineWidth", 2.4, "MarkerFaceColor", colA);
    hB = plot(1:9, mB, '-o', "Color", colB, "LineWidth", 2.4, "MarkerFaceColor", colB);
    xlabel("AS7341 Channel"); ylabel("SNV-normalized value");
    title(ttl, "Interpreter", "tex");
    xticks(1:9); xticklabels(cellstr(chLab)); xtickangle(45); xlim([1 9]); grid on;
    legend([hA hB], {char(nameA + " mean"), char(nameB + " mean")}, "Location", "northwest");
    hold off;
    for d = 1:numel(outdirs)
        try
            exportgraphics(fig, fullfile(outdirs(d), fname), "Resolution", 200);
        catch ME
            warning("save failed %s: %s", fullfile(outdirs(d), fname), ME.message);
        end
    end
    close(fig);
end
