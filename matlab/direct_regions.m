function direct_regions(region)
% DIRECT_REGIONS  Full per-region analysis of a directly measured set, using
% exactly the Chapter 6 feature pipeline (Clear ratio, then SNV per reading,
% then the note mean) so the numbers are comparable with the screen campaign.
%
%   direct_regions            % unprinted white area (default)
%   direct_regions('yellow')  % uniform yellow patch
%
% Produces, for the region given:
%   1. per-channel class separability (Cohen's d) on the note means;
%   2. principal component analysis, variance explained and PC1 loadings;
%   3. note-level leave-one-banknote-out accuracy for four classifiers;
%   4. the per-note margin towards the true class, and whether any note falls
%      in the review band the two-stage cascade would send to Stage 2.
%
% Output: Result/result_direct_<region>_full/

if nargin < 1; region = 'white'; end
switch lower(region)
    case 'white';  dirDirect = 'data_white_direct';  regLab = 'Unprinted white area';
    case 'yellow'; dirDirect = 'data_yellow_direct'; regLab = 'Uniform yellow patch';
    otherwise; error('unknown region %s', region);
end

root   = fileparts(fileparts(mfilename('fullpath')));
outdir = fullfile(root, 'Result', ['result_direct_' lower(region) '_full']);
if ~exist(outdir, 'dir'); mkdir(outdir); end
logFile = fullfile(outdir, 'direct_regions_log.txt');
if exist(logFile, 'file'); delete(logFile); end
diary(logFile); diary on;

LAB = {'F1 415','F2 445','F3 480','F4 515','F5 555','F6 590','F7 630','F8 680','NIR'};
CB  = [0 0.4470 0.7410];        % house blue  (Real)
CO  = [0.8500 0.3250 0.0980];   % house orange (Fake)

S1 = loadNoteSet(fullfile(root, dirDirect, 'Real'));
S0 = loadNoteSet(fullfile(root, dirDirect, 'Fake'));
X  = [vertcat(S1.mean); vertcat(S0.mean)];
y  = [ones(numel(S1),1); zeros(numel(S0),1)];
nm = [string({S1.name}), string({S0.name})];
sc = [vertcat(S1.scatter); vertcat(S0.scatter)];
rp = [vertcat(S1.repeats); vertcat(S0.repeats)];
fprintf('==== %s, direct measurement ====\n', regLab);
fprintf('genuine notes %d, counterfeit notes %d, %d to %d readings each\n', ...
        numel(S1), numel(S0), min(rp), max(rp));

% ---- 1. per-channel separability ---------------------------------------
d = arrayfun(@(k) cohend(X(y==1,k), X(y==0,k)), 1:9);
fprintf('\n--- 1. per-channel Cohen d on the note means (SNV) ---\n');
for k = 1:9; fprintf('%-8s %7.2f\n', LAB{k}, d(k)); end
[~, kb] = max(abs(d));
fprintf('largest |d| = %.2f at %s\n', abs(d(kb)), LAB{kb});

% ---- 2. principal component analysis ------------------------------------
[coeff, score, lat] = pca(X);
cv = 100*cumsum(lat)/sum(lat);
fprintf('\n--- 2. PCA on the note means ---\n');
fprintf('variance explained: PC1 %.2f%%, PC2 %.2f%%, PC3 %.2f%%, PC1-3 %.2f%%\n', ...
        100*lat(1)/sum(lat), 100*lat(2)/sum(lat), 100*lat(3)/sum(lat), cv(3));
w = abs(coeff(:,1)); w = 100*w/sum(w);
[~, ow] = sort(w, 'descend');
fprintf('PC1 loading share: ');
fprintf('%s %.1f%%  ', LAB{ow(1)}, w(ow(1)), LAB{ow(2)}, w(ow(2)), LAB{ow(3)}, w(ow(3)));
fprintf('\n');

% ---- 3. classifier comparison -------------------------------------------
names = {'Linear SVM', 'RBF SVM', 'k-NN (k=3)', 'Decision Tree'};
fits  = { @(Xt,Yt) fitcsvm(Xt, Yt, 'KernelFunction', 'linear'), ...
          @(Xt,Yt) fitcsvm(Xt, Yt, 'KernelFunction', 'rbf', 'BoxConstraint', 1), ...
          @(Xt,Yt) fitcknn(Xt, Yt, 'NumNeighbors', 3, 'Standardize', true), ...
          @(Xt,Yt) fitctree(Xt, Yt) };
acc = zeros(1,4); fp = zeros(1,4); fn = zeros(1,4);
fprintf('\n--- 3. note-level leave-one-banknote-out ---\n');
fprintf('%-16s %9s %6s %6s\n', 'classifier', 'accuracy', 'FP', 'FN');
for i = 1:numel(fits)
    p = looPred(fits{i}, X, y);
    acc(i) = mean(p == y);
    fp(i)  = sum(p == 1 & y == 0);      % counterfeit accepted as genuine
    fn(i)  = sum(p == 0 & y == 1);      % genuine rejected
    fprintf('%-16s %8.1f%% %6d %6d\n', names{i}, 100*acc(i), fp(i), fn(i));
end

% ---- 4. margin and the review band --------------------------------------
[pred, marg] = looDetail(X, y);
band = 0.5 * median(abs(marg));
fprintf('\n--- 4. per-note margin, linear SVM ---\n');
fprintf('genuine %.2f--%.2f, counterfeit %.2f--%.2f, all positive: %s\n', ...
        min(marg(y==1)), max(marg(y==1)), min(marg(y==0)), max(marg(y==0)), ...
        string(all(marg > 0)));
fprintf('review band |margin| < %.2f would hold %d of %d notes\n', ...
        band, sum(abs(marg) < band), numel(marg));
[~, ow2] = sort(marg, 'ascend');
fprintf('least confident notes: %s (%.2f), %s (%.2f), %s (%.2f)\n', ...
        nm(ow2(1)), marg(ow2(1)), nm(ow2(2)), marg(ow2(2)), nm(ow2(3)), marg(ow2(3)));
fprintf('within-note scatter: genuine %.4f, counterfeit %.4f, ratio %.2f\n', ...
        mean(sc(y==1)), mean(sc(y==0)), mean(sc(y==0))/mean(sc(y==1)));

% ===================== figures ===========================================
% (a) per-channel separability
f = figure('Visible','off','Position',[100 100 620 380]);
b = bar(abs(d), 0.68, 'FaceColor', CB, 'EdgeColor', 'none'); grid on; box on;
set(gca,'XTick',1:9,'XTickLabel',LAB,'XTickLabelRotation',45,'FontSize',9);
ylabel('|Cohen''s d|'); xlim([0.4 9.6]);
title({[regLab ', direct measurement'], 'per-channel class separability'}, 'FontSize', 10);
savePad(f, fullfile(outdir,'fig_channels.png')); close(f);
if ~isempty(b); end

% (b) PCA: scores and PC1 loadings
f = figure('Visible','off','Position',[100 100 980 380]);
subplot(1,2,1); hold on; grid on; box on;
scatter(score(y==1,1), score(y==1,2), 46, CB, 'filled');
scatter(score(y==0,1), score(y==0,2), 46, CO, 'filled');
xlabel(sprintf('PC1 (%.1f%%)', 100*lat(1)/sum(lat)));
ylabel(sprintf('PC2 (%.1f%%)', 100*lat(2)/sum(lat)));
legend({'Real','Fake'}, 'Location','best');
title('Principal component scores', 'FontSize', 10);
subplot(1,2,2); hold on; grid on; box on;
bar(w, 0.68, 'FaceColor', [0.45 0.45 0.45], 'EdgeColor', 'none');
set(gca,'XTick',1:9,'XTickLabel',LAB,'XTickLabelRotation',45,'FontSize',9);
ylabel('share of |PC1| loading (%)'); xlim([0.4 9.6]);
title('Channel contribution to PC1', 'FontSize', 10);
savePad(f, fullfile(outdir,'fig_pca.png')); close(f);

% (c) classifier comparison
f = figure('Visible','off','Position',[100 100 620 380]);
bar(100*acc, 0.62, 'FaceColor', CB, 'EdgeColor', 'none'); grid on; box on;
set(gca,'XTickLabel',names,'FontSize',9); ylim([80 102]);
ylabel('note-level accuracy (%)');
title({[regLab ', direct measurement'], 'leave-one-banknote-out accuracy'}, 'FontSize', 10);
savePad(f, fullfile(outdir,'fig_classifiers.png')); close(f);

% (d) per-note margin
[ms, ord] = sort(marg, 'ascend');
f = figure('Visible','off','Position',[100 100 620 460]);
hold on; box on;
for i = 1:numel(ord)
    if y(ord(i)) == 1; col = CB; else; col = CO; end
    barh(i, ms(i), 0.72, 'FaceColor', col, 'EdgeColor', 'none');
end
plot([0 0], [0.4 numel(ord)+0.6], 'k--', 'LineWidth', 0.8);
set(gca,'YTick',1:numel(ord),'YTickLabel',nm(ord),'YDir','reverse','FontSize',8,'XGrid','on');
ylim([0.4 numel(ord)+0.6]); xlim([min(-0.15,1.1*min(ms)) 1.15*max(ms)]);
xlabel('margin towards true class');
title({[regLab ': per-note margin, direct measurement'], ...
       'blue = Real, orange = Fake (top = least confident)'}, 'FontSize', 10);
savePad(f, fullfile(outdir,'fig_margin.png')); close(f);

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

function [pred, marg] = looDetail(F, y)
n = numel(y); pred = zeros(n,1); marg = zeros(n,1);
for i = 1:n
    tr = true(n,1); tr(i) = false;
    mu = mean(F(tr,:),1); sg = std(F(tr,:),0,1); sg(sg==0) = 1;
    m = fitcsvm((F(tr,:)-mu)./sg, y(tr), 'KernelFunction','linear');
    [q, s] = predict(m, (F(i,:)-mu)./sg);
    pred(i) = q; marg(i) = (2*y(i)-1) * s(2);
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
