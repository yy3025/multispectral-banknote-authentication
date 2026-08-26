function scatter_direct()
% SCATTER_DIRECT  Within-note scatter on the DIRECTLY MEASURED sets.
%
% condition_analysis.m answers the same questions on result_20 / result_yellow
% / result_white, which are the DIGIT STROKE and the two uniform regions read
% from PHOTOGRAPHS. The report's scatter chapter is now about the two uniform
% regions measured DIRECTLY, and no equivalent had ever been computed, so that
% chapter was quoting screen-route numbers under a region-only label.
%
% This script recomputes, for data_white_direct and data_yellow_direct:
%   B. is the within-note scatter class-discriminative?
%   C. is it usable as a classification feature?
% using exactly the Chapter 6 pipeline (loadNoteSet -> Clear ratio, SNV per
% reading) and the same note-level leave-one-banknote-out protocol as
% direct_regions.m, including the repeat-matched control.
%
% Output: Result/result_scatter_direct/

clc; close all;
rng(0);
set(groot, "defaultAxesFontSize", 12);

root   = fileparts(fileparts(mfilename('fullpath')));
outdir = fullfile(root, 'Result', 'result_scatter_direct');
if ~exist(outdir, 'dir'); mkdir(outdir); end
logFile = fullfile(outdir, 'scatter_direct_log.txt');
if exist(logFile, 'file'); delete(logFile); end
diary(logFile); diary on;

nDraw = 400;
CB = [0 0.4470 0.7410];
CO = [0.8500 0.3250 0.0980];

regions = {
    'white',  'data_white_direct',  'Unprinted white area'
    'yellow', 'data_yellow_direct', 'Uniform yellow patch'
};

R = struct();
allRows = cell(0,7);

for r = 1:size(regions,1)
    tag = regions{r,1}; dirn = regions{r,2}; lab = regions{r,3};

    S1 = loadNoteSet(fullfile(root, dirn, 'Real'));
    S0 = loadNoteSet(fullfile(root, dirn, 'Fake'));
    X  = [vertcat(S1.mean);    vertcat(S0.mean)];
    y  = [ones(numel(S1),1);   zeros(numel(S0),1)];
    nm = [string({S1.name}),   string({S0.name})]';
    sc = [vertcat(S1.scatter); vertcat(S0.scatter)];
    rp = [vertcat(S1.repeats); vertcat(S0.repeats)];
    Sall = [S1(:); S0(:)];

    fprintf('\n================ %s, DIRECT measurement ================\n', lab);
    fprintf('genuine %d, counterfeit %d, %d to %d readings per note\n', ...
            numel(S1), numel(S0), min(rp), max(rp));

    % ---- repeat-matched scatter ----------------------------------------
    nMatch = min(rp);
    scM = zeros(numel(Sall),1);
    for i = 1:numel(Sall)
        Xi = Sall(i).X; ni = size(Xi,1);
        if ni <= nMatch
            scM(i) = sqrt(mean(var(Xi,0,1,'omitnan'),'omitnan'));
        else
            tot = 0;
            for dr = 1:nDraw
                idx = randperm(ni, nMatch);
                tot = tot + sqrt(mean(var(Xi(idx,:),0,1,'omitnan'),'omitnan'));
            end
            scM(i) = tot / nDraw;
        end
    end
    fprintf('repeat-matched at n = %d repeats per note (%d random draws)\n', nMatch, nDraw);

    % ---- B. class dependence -------------------------------------------
    fprintf('\n--- B. is the scatter class-discriminative? ---\n');
    for v = 1:2
        if v == 1
            s = sc;  what = 'raw       ';
        else
            s = scM; what = 'rep-match ';
        end
        mg = mean(s(y==1)); mf = mean(s(y==0));
        dd = cohend(s(y==0), s(y==1));
        pv = ranksum(s(y==1), s(y==0));
        fprintf('%s genuine %.4f, counterfeit %.4f, ratio %.2f, |d| = %.2f, rank-sum p = %.3g\n', ...
                what, mg, mf, mf/mg, abs(dd), pv);
        if v == 1
            R.(tag).raw = [mg mf mf/mg abs(dd) pv];
        else
            R.(tag).mat = [mg mf mf/mg abs(dd) pv];
        end
    end
    ovl = sum(sc(y==1) > min(sc(y==0))) + sum(sc(y==0) < max(sc(y==1)));
    fprintf('overlap: highest genuine %.4f, lowest counterfeit %.4f, %d of %d notes inside the other class range\n', ...
            max(sc(y==1)), min(sc(y==0)), ovl, numel(sc));
    fprintf('counterfeit scatter spans %.4f to %.4f\n', min(sc(y==0)), max(sc(y==0)));

    % ---- C. usable as a feature? ---------------------------------------
    fprintf('\n--- C. note-level leave-one-banknote-out accuracy ---\n');
    fprintf('%-24s %4s %10s %10s %5s %5s\n', 'feature set', 'p', 'linearSVM', 'rbfSVM', 'FP', 'FN');
    setName = {'9 channel means', '9 channels + scatter', 'scatter only'};
    setData = {X, [X sc], sc};
    for k = 1:3
        F = setData{k};
        pl = looPred(@(Xt,Yt) fitcsvm(Xt,Yt,'KernelFunction','linear'), F, y);
        pr = looPred(@(Xt,Yt) fitcsvm(Xt,Yt,'KernelFunction','rbf','BoxConstraint',1), F, y);
        al = mean(pl==y); ar = mean(pr==y);
        fpv = sum(pl==1 & y==0); fnv = sum(pl==0 & y==1);
        fprintf('%-24s %4d %9.1f%% %9.1f%% %5d %5d\n', setName{k}, size(F,2), 100*al, 100*ar, fpv, fnv);
        allRows(end+1,:) = {lab, setName{k}, size(F,2), 100*al, 100*ar, fpv, fnv}; %#ok<AGROW>
    end
    fprintf('majority-class rate %.1f%% (counterfeit is %d of %d)\n', ...
            100*max(mean(y),1-mean(y)), sum(y==0), numel(y));

    % ---- D. sample-level accuracy: one reading, not the note average ----
    % Note-grouped 5-fold CV over the individual readings. Whole notes stay
    % in one fold, so this is the accuracy of a single reading taken at one
    % position inside the region, with no leakage between train and test.
    Xs = []; ys = []; gs = [];
    for i = 1:numel(Sall)
        Xi = Sall(i).X;
        Xs = [Xs; Xi];                       %#ok<AGROW>
        ys = [ys; repmat(y(i), size(Xi,1), 1)];  %#ok<AGROW>
        gs = [gs; repmat(i,   size(Xi,1), 1)];   %#ok<AGROW>
    end
    K = 5;
    noteFold = mod(randperm(numel(Sall)), K) + 1;
    predS = zeros(size(ys));
    for k = 1:K
        teNote = find(noteFold == k);
        te = ismember(gs, teNote); tr = ~te;
        mu = mean(Xs(tr,:),1); sg = std(Xs(tr,:),0,1); sg(sg==0) = 1;
        m  = fitcsvm((Xs(tr,:)-mu)./sg, ys(tr), 'KernelFunction','linear');
        predS(te) = predict(m, (Xs(te,:)-mu)./sg);
    end
    fprintf('sample-level note-grouped %d-fold CV: %.2f%% over %d readings\n', ...
            K, 100*mean(predS==ys), numel(ys));

    T = table(nm, y, rp, sc, scM, 'VariableNames', ...
              {'Note','Genuine','Repeats','ScatterRaw','ScatterMatched'});
    writetable(T, fullfile(outdir, ['scatter_' tag '_direct.csv']));

    R.(tag).sc = sc; R.(tag).y = y; R.(tag).lab = lab;
end

% ---- figure: scatter by class, both direct regions ---------------------
f = figure('Visible','off','Position',[100 100 760 380]);
tags = {'white','yellow'};
for r = 1:2
    subplot(1,2,r); hold on; grid on; box on;
    s = R.(tags{r}).sc; yy = R.(tags{r}).y;
    n1 = sum(yy==1); n0 = sum(yy==0);
    scatter(1+0.14*(rand(n1,1)-0.5), s(yy==1), 42, CB, 'filled', 'MarkerFaceAlpha', 0.75);
    scatter(2+0.14*(rand(n0,1)-0.5), s(yy==0), 42, CO, 'filled', 'MarkerFaceAlpha', 0.75);
    plot([0.75 1.25], [1 1]*mean(s(yy==1)), 'k-', 'LineWidth', 1.6);
    plot([1.75 2.25], [1 1]*mean(s(yy==0)), 'k-', 'LineWidth', 1.6);
    set(gca,'XTick',[1 2],'XTickLabel',{'Genuine','Counterfeit'},'FontSize',9);
    xlim([0.5 2.5]); ylabel('within-note scatter');
    title(R.(tags{r}).lab, 'FontSize', 10);
end
savePad(f, fullfile(outdir,'fig_scatter_direct.png')); close(f);

C = cell2table(allRows, 'VariableNames', ...
     {'Region','FeatureSet','nFeatures','LinearSVM','RbfSVM','FP','FN'});
writetable(C, fullfile(outdir,'scatter_direct_classifier.csv'));

fprintf('\nwritten to %s\n', outdir);
diary off;
end

% ------------------------------------------------------------------------
function p = looPred(fitFcn, F, y)
n = numel(y); p = zeros(n,1);
for i = 1:n
    tr = true(n,1); tr(i) = false;
    mu = mean(F(tr,:),1); sg = std(F(tr,:),0,1); sg(sg==0) = 1;
    m = fitFcn((F(tr,:)-mu)./sg, y(tr));
    p(i) = predict(m, (F(i,:)-mu)./sg);
end
end

function d = cohend(a, b)
na = numel(a); nb = numel(b);
sp = sqrt(((na-1)*var(a) + (nb-1)*var(b)) / (na+nb-2));
d  = (mean(a) - mean(b)) / sp;
end

function savePad(f, p)
exportgraphics(f, p, 'Resolution', 220);
I = imread(p); [h, w, c] = size(I); m = 24;
J = uint8(255 * ones(h + 2*m, w + 2*m, c, 'uint8'));
J(m+1:m+h, m+1:m+w, :) = I;
imwrite(J, p);
end
