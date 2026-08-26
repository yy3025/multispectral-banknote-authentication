function region_full(region, route)
% REGION_FULL  Full per-region analysis of one measurement route, using the
% Chapter 6 feature pipeline (Clear ratio, SNV per reading, then the note mean)
% so that the two routes and the two regions are directly comparable.
%
%   region_full('white')             % white area, direct measurement
%   region_full('white',  'screen')  % white area, read from the photographs
%   region_full('yellow', 'direct')
%
% Produces, for the region and route given:
%   1. per-channel class separability (Cohen's d) on the note means;
%   2. principal component analysis, variance explained and PC1 loadings;
%   3. note-level leave-one-banknote-out accuracy for four classifiers;
%   4. the per-note margin towards the true class and the review band;
%   5. the within-note scatter experiment: is the scatter itself class
%      dependent, does it classify on its own, and does adding it to the nine
%      channel means change anything.
%
% Output: Result/result_<region>_<route>_full/

if nargin < 1; region = 'white'; end
if nargin < 2; route  = 'direct'; end
region = lower(region); route = lower(route);

switch region
    case 'white';  regLab = 'Unprinted white area';  dDir = 'data_white_direct';  sDir = 'data_white';
    case 'yellow'; regLab = 'Uniform yellow patch';  dDir = 'data_yellow_direct'; sDir = 'data_yellow';
    otherwise; error('unknown region %s', region);
end
switch route
    case 'direct'; folder = dDir; realSub = 'Real'; fakeSub = 'Fake'; rLab = 'direct measurement';
    case 'screen'; folder = sDir; realSub = 'real'; fakeSub = 'fake'; rLab = 'photographic route';
    otherwise; error('unknown route %s', route);
end

root   = fileparts(fileparts(mfilename('fullpath')));
outdir = fullfile(root, 'Result', ['result_' region '_' route '_full']);
if ~exist(outdir, 'dir'); mkdir(outdir); end
logFile = fullfile(outdir, 'region_full_log.txt');
if exist(logFile, 'file'); delete(logFile); end
diary(logFile); diary on;

LAB = {'F1 415','F2 445','F3 480','F4 515','F5 555','F6 590','F7 630','F8 680','NIR'};
CB  = [0 0.4470 0.7410];        % house blue  (Real)
CO  = [0.8500 0.3250 0.0980];   % house orange (Fake)

S1 = loadNoteSet(fullfile(root, folder, realSub));
S0 = loadNoteSet(fullfile(root, folder, fakeSub));
X  = [vertcat(S1.mean); vertcat(S0.mean)];
y  = [ones(numel(S1),1); zeros(numel(S0),1)];
nm = [string({S1.name}), string({S0.name})];
sc = [vertcat(S1.scatter); vertcat(S0.scatter)];
rp = [vertcat(S1.repeats); vertcat(S0.repeats)];
fprintf('==== %s, %s ====\n', regLab, rLab);
fprintf('genuine notes %d, counterfeit notes %d, %d to %d readings each\n', ...
        numel(S1), numel(S0), min(rp), max(rp));

% ---- 1. per-channel separability ---------------------------------------
d = arrayfun(@(k) cohend(X(y==1,k), X(y==0,k)), 1:9);
fprintf('\n--- 1. per-channel Cohen d on the note means (SNV) ---\n');
for k = 1:9; fprintf('%-8s %7.2f\n', LAB{k}, d(k)); end
[~, kb] = max(abs(d));
fprintf('largest |d| = %.2f at %s\n', abs(d(kb)), LAB{kb});

R1 = vertcat(S1.X); R0 = vertcat(S0.X);
dr = arrayfun(@(k) cohend(R1(:,k), R0(:,k)), 1:9);
[~, kr] = max(abs(dr));
fprintf('per-reading Cohen d (all repeats pooled, as in the region sections):\n');
for k = 1:9; fprintf('%-8s %7.2f\n', LAB{k}, dr(k)); end
fprintf('largest per-reading |d| = %.2f at %s\n', abs(dr(kr)), LAB{kr});

% ---- 2. principal component analysis ------------------------------------
[coeff, score, lat] = pca(X);
cv = 100*cumsum(lat)/sum(lat);
fprintf('\n--- 2. PCA on the note means ---\n');
fprintf('variance explained: PC1 %.2f%%, PC2 %.2f%%, PC3 %.2f%%, PC1-3 %.2f%%\n', ...
        100*lat(1)/sum(lat), 100*lat(2)/sum(lat), 100*lat(3)/sum(lat), cv(3));
w = abs(coeff(:,1)); w = 100*w/sum(w);
[~, ow] = sort(w, 'descend');
fprintf('PC1 loading share: %s %.1f%%, %s %.1f%%, %s %.1f%%\n', ...
        LAB{ow(1)}, w(ow(1)), LAB{ow(2)}, w(ow(2)), LAB{ow(3)}, w(ow(3)));

% ---- 3. classifier comparison -------------------------------------------
names = {'Linear SVM', 'RBF SVM', 'k-NN (k=3)', 'Decision Tree'};
fits  = { @(Xt,Yt) fitcsvm(Xt, Yt, 'KernelFunction', 'linear'), ...
          @(Xt,Yt) fitcsvm(Xt, Yt, 'KernelFunction', 'rbf', 'BoxConstraint', 1), ...
          @(Xt,Yt) fitcknn(Xt, Yt, 'NumNeighbors', 3, 'Standardize', true), ...
          @(Xt,Yt) fitctree(Xt, Yt) };
acc = zeros(1,4);
fprintf('\n--- 3. note-level leave-one-banknote-out ---\n');
fprintf('%-16s %9s %6s %6s\n', 'classifier', 'accuracy', 'FP', 'FN');
for i = 1:numel(fits)
    p = looPred(fits{i}, X, y);
    acc(i) = mean(p == y);
    fprintf('%-16s %8.1f%% %6d %6d\n', names{i}, 100*acc(i), ...
            sum(p == 1 & y == 0), sum(p == 0 & y == 1));
end

% ---- 4. margin and the review band --------------------------------------
[pred, marg] = looDetail(X, y);
C = zeros(2,2);
for i = 1:numel(y); C(2-y(i), 2-pred(i)) = C(2-y(i), 2-pred(i)) + 1; end
fprintf('\nconfusion matrix, linear SVM, leave-one-note-out:\n');
fprintf('              pred genuine  pred counterfeit\n');
fprintf('true genuine     %6d           %6d\n', C(1,1), C(1,2));
fprintf('true counterfeit %6d           %6d\n', C(2,1), C(2,2));
band = 0.5 * median(abs(marg));
fprintf('\n--- 4. per-note margin, linear SVM ---\n');
fprintf('genuine %.2f--%.2f, counterfeit %.2f--%.2f, all positive: %s\n', ...
        min(marg(y==1)), max(marg(y==1)), min(marg(y==0)), max(marg(y==0)), ...
        string(all(marg > 0)));
fprintf('review band |margin| < %.2f would hold %d of %d notes\n', ...
        band, sum(abs(marg) < band), numel(marg));
[~, om] = sort(marg, 'ascend');
fprintf('least confident: %s (%.2f), %s (%.2f), %s (%.2f)\n', ...
        nm(om(1)), marg(om(1)), nm(om(2)), marg(om(2)), nm(om(3)), marg(om(3)));

% ---- 5. the within-note scatter experiment ------------------------------
ds = cohend(sc(y==1), sc(y==0));
[accS, ~]  = looAcc(sc, y);
[accXS, ~] = looAcc([X sc], y);
[accX, ~]  = looAcc(X, y);
ov = sum(sc(y==0) < max(sc(y==1))) + sum(sc(y==1) > min(sc(y==0)));
fprintf('\n--- 5. within-note scatter ---\n');
fprintf('mean scatter: genuine %.4f, counterfeit %.4f, ratio %.2f\n', ...
        mean(sc(y==1)), mean(sc(y==0)), mean(sc(y==0))/mean(sc(y==1)));
fprintf('range: genuine %.4f--%.4f, counterfeit %.4f--%.4f, overlapping notes %d\n', ...
        min(sc(y==1)), max(sc(y==1)), min(sc(y==0)), max(sc(y==0)), ov);
fprintf('Cohen d of the scatter itself: %.2f\n', ds);
fprintf('accuracy from the scatter alone      %.1f%%\n', 100*accS);
fprintf('accuracy from the nine channels      %.1f%%\n', 100*accX);
fprintf('accuracy from nine channels + scatter %.1f%%\n', 100*accXS);

% ===================== figures ===========================================
tag = [regLab ', ' rLab];

f = figure('Visible','off','Position',[100 100 620 380]);
bar(abs(dr), 0.68, 'FaceColor', CB, 'EdgeColor', 'none'); grid on; box on;
set(gca,'XTick',1:9,'XTickLabel',LAB,'XTickLabelRotation',45,'FontSize',9);
ylabel('|Cohen''s d|'); xlim([0.4 9.6]);
title({tag, 'per-channel class separability'}, 'FontSize', 10);
savePad(f, fullfile(outdir,'fig_channels.png')); close(f);

f = figure('Visible','off','Position',[100 100 980 380]);
subplot(1,2,1); hold on; grid on; box on;
scatter(score(y==1,1), score(y==1,2), 42, CB, 'filled');
scatter(score(y==0,1), score(y==0,2), 42, CO, 'filled');
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

f = figure('Visible','off','Position',[100 100 620 380]);
bar(100*acc, 0.62, 'FaceColor', CB, 'EdgeColor', 'none'); grid on; box on;
set(gca,'XTickLabel',names,'FontSize',9); ylim([80 102]);
ylabel('note-level accuracy (%)');
title({tag, 'leave-one-banknote-out accuracy'}, 'FontSize', 10);
savePad(f, fullfile(outdir,'fig_classifiers.png')); close(f);

f = figure('Visible','off','Position',[100 100 520 430]);
drawConfusion(C, {'Real','Fake'}, ...
   {[tag ' (' num2str(numel(y)) ' notes)'], ...
    sprintf('Note-level LOO, linear SVM, accuracy = %.1f%%', 100*acc(1))});
savePad(f, fullfile(outdir,'fig_confusion.png')); close(f);

% The notes are split over two panels side by side: one column of fifty
% horizontal bars is taller than a page can hold beside its own text.
[ms, ord] = sort(marg, 'ascend');
nAll = numel(ord); half = ceil(nAll/2);
f = figure('Visible','off','Position',[100 100 950 max(340, 15*half)]);
xl = [min(-0.15, 1.1*min(ms)) 1.15*max(ms)];
for p = 1:2
    if p == 1; idx = 1:half; else; idx = half+1:nAll; end
    subplot(1,2,p); hold on; box on;
    for j = 1:numel(idx)
        i = idx(j);
        if y(ord(i)) == 1; col = CB; else; col = CO; end
        barh(j, ms(i), 0.72, 'FaceColor', col, 'EdgeColor', 'none');
    end
    plot([0 0], [0.4 numel(idx)+0.6], 'k--', 'LineWidth', 0.8);
    set(gca,'YTick',1:numel(idx),'YTickLabel',nm(ord(idx)),'YDir','reverse', ...
            'FontSize',8,'XGrid','on');
    ylim([0.4 numel(idx)+0.6]); xlim(xl);
    xlabel('margin towards true class');
    if p == 1
        title({[tag ': per-note margin'], ...
               'blue = Real, orange = Fake (top left = least confident)'}, 'FontSize', 10);
    end
end
savePad(f, fullfile(outdir,'fig_margin.png')); close(f);

f = figure('Visible','off','Position',[100 100 620 380]);
hold on; grid on; box on;
jit = 0.10*(rand(numel(sc),1)-0.5);
scatter(1+jit(y==1), sc(y==1), 40, CB, 'filled');
scatter(2+jit(y==0), sc(y==0), 40, CO, 'filled');
plot([0.75 1.25], mean(sc(y==1))*[1 1], 'k-', 'LineWidth', 1.4);
plot([1.75 2.25], mean(sc(y==0))*[1 1], 'k-', 'LineWidth', 1.4);
set(gca,'XTick',[1 2],'XTickLabel',{'Real','Fake'},'FontSize',9);
xlim([0.6 2.4]); ylabel('within-note scatter');
title({tag, sprintf('within-note scatter, |d| = %.2f', abs(ds))}, 'FontSize', 10);
savePad(f, fullfile(outdir,'fig_scatter.png')); close(f);

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

function [a, nerr] = looAcc(F, y)
p = looPred(@(Xt,Yt) fitcsvm(Xt, Yt, 'KernelFunction','linear'), F, y);
a = mean(p == y); nerr = sum(p ~= y);
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

function drawConfusion(C, labs, ttl)
% Same style as the confusion matrices elsewhere in the report.
n = size(C,1);
ax = axes('Position',[0.20 0.16 0.72 0.62]); hold(ax,'on');
for r = 1:n
    for c = 1:n
        v = C(r,c);
        if v == 0
            fc = [1 1 1]; tc = [0 0 0];
        elseif r == c
            t = 0.30 + 0.70*(v/max(diag(C)));
            fc = 1 - t*(1 - [0 0.4470 0.7410]);
            tc = [0 0 0]; if t > 0.75; tc = [1 1 1]; end
        else
            fc = [0.988 0.925 0.898]; tc = [0 0 0];
        end
        rectangle('Position',[c-0.5 r-0.5 1 1],'FaceColor',fc, ...
                  'EdgeColor',[0.15 0.15 0.15],'LineWidth',0.9);
        text(c, r, sprintf('%d', v), 'HorizontalAlignment','center', ...
             'VerticalAlignment','middle','FontSize',17,'Color',tc);
    end
end
set(ax,'XLim',[0.5 n+0.5],'YLim',[0.5 n+0.5],'YDir','reverse','Box','on', ...
       'XTick',1:n,'XTickLabel',labs,'YTick',1:n,'YTickLabel',labs, ...
       'TickLength',[0 0],'FontSize',10);
xlabel(ax,'Predicted class'); ylabel(ax,'True class');
title(ax, ttl, 'FontSize', 10);
end

function savePad(f, p)
exportgraphics(f, p, 'Resolution', 220);
I = imread(p); [h, w, c] = size(I); m = 24;
J = uint8(255 * ones(h + 2*m, w + 2*m, c, 'uint8'));
J(m+1:m+h, m+1:m+w, :) = I;
imwrite(J, p);
end
