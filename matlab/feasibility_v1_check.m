clc; clearvars;

%% =========================
% Reproduces the 100% first-generation (V1) result quoted in the feasibility
% study, from the archived feasibility dataset.
%
% Why this script exists: the V1 confusion matrix used in the report was
% produced during the early feasibility work, on a set of genuine notes that
% is NOT the region-20 set used for the main campaign. Running banknotes.m on
% the main dataset gives 96.67% for the same Real-vs-FakeV1 comparison, which
% is a different measurement, not a correction of this one. This script keeps
% the feasibility number reproducible so the two cannot be confused again.
%
% Data:
%   D:\project\data_feasibility\real   genuine notes, feasibility campaign
%   D:\project\Fake_V1                 the six first-generation counterfeits
% =========================

addpath("D:\project\matlab");

realDir = "D:\project\data_feasibility\real";
v1Dir   = "D:\project\Fake_V1";

Sreal = loadNoteSet(realDir);
Sv1   = loadNoteSet(v1Dir);

if isempty(Sreal) || isempty(Sv1)
    error("Data not found. Expected %s and %s", realDir, v1Dir);
end

X     = [vertcat(Sreal.mean); vertcat(Sv1.mean)];
Y     = [repmat("Real", numel(Sreal), 1); repmat("FakeV1", numel(Sv1), 1)];
names = [string({Sreal.name})'; string({Sv1.name})'];

fprintf("Genuine notes (feasibility set): %d\n", numel(Sreal));
fprintf("First-generation (V1) notes    : %d\n", numel(Sv1));

% Same protocol as the rest of the project: one averaged spectrum per note,
% leave one whole banknote out, linear SVM with standardized features.
n    = numel(Y);
pred = strings(n, 1);
for i = 1:n
    tr      = true(n, 1); tr(i) = false;
    mdl     = fitcsvm(X(tr, :), Y(tr), "KernelFunction", "linear", "Standardize", true);
    pred(i) = string(predict(mdl, X(i, :)));
end

acc = mean(pred == Y) * 100;
fprintf("\nBinary note-level LOO (linear SVM) accuracy = %.2f%%\n", acc);

wrong = find(pred ~= Y);
if isempty(wrong)
    fprintf("Every note classified correctly.\n");
else
    for k = wrong'
        fprintf("  MISCLASSIFIED: %-10s true=%-7s pred=%s\n", names(k), Y(k), pred(k));
    end
end

%% ---- confusion matrix figure -------------------------------------------
% Drawn exactly as banknotes.m draws figures 9a/9b, so this panel and the
% current-counterfeit panel beside it in the report match in style. The axis
% labels are set explicitly in English because the MATLAB locale on this
% machine is Chinese and confusionchart would otherwise label them in Chinese.
outPng = "D:\project\data_feasibility\fig9a_real_vs_fakeV1_confusion.png";

yTrue = categorical(Y,    ["Real" "FakeV1"], {'Real', 'FakeV1'});
yPred = categorical(pred, ["Real" "FakeV1"], {'Real', 'FakeV1'});

fig = figure;
cm = confusionchart(yTrue, yPred);
cm.XLabel   = 'Predicted class';
cm.YLabel   = 'True class';
cm.FontSize = 12;
title(sprintf("Real vs first-generation fakes (FakeV1, original 6)\nBinary note-level LOO (Linear SVM), accuracy = %.2f%%", acc));
exportgraphics(fig, outPng, "Resolution", 200);
close(fig);

fprintf("\nFigure written to %s\n", outPng);
