function scatter_routes()
% SCATTER_ROUTES  Within-note scatter on both uniform regions, both routes.
%
% Extends scatter_direct.m to the photographic campaign, so that Chapter 7
% can report the direct group and the photographic group under the same
% statistics and then compare them. Four combinations:
%
%   white  direct      data_white_direct   (20 genuine + 30 counterfeit)
%   yellow direct      data_yellow_direct  (20 + 30)
%   white  photograph  data_white          (27 + 31)
%   yellow photograph  data_yellow         (27 + 31)
%
% Everything runs through loadNoteSet, i.e. the Chapter 6 pipeline: the eight
% colour channels and NIR divided by Clear, then SNV per reading. For each
% combination it reports
%   1. class means of the within-note scatter, raw and repeat-matched, the
%      fake/genuine ratio, Cohen's d and a rank-sum test;
%   2. how far the two class distributions overlap;
%   3. the per-channel within-note standard deviation profile, by class;
%   4. note-level leave-one-banknote-out accuracy from 9 channel means,
%      9 channels + scatter, and the scatter alone (linear and RBF).
% It then compares the two routes on the same region:
%   5. rank-sum test between the routes on each class;
%   6. Spearman correlation between the per-channel sigma profiles of the two
%      routes, which asks whether the instability sits in the same channels.
%
% The two routes were recorded on DIFFERENT physical banknotes (report
% Section 6.1), so no note-by-note pairing between routes is possible and
% none is attempted here.
%
% Output: Result/result_scatter_routes/

clc; close all;
rng(0);
set(groot, "defaultAxesFontSize", 12);

root   = fileparts(fileparts(mfilename('fullpath')));
outdir = fullfile(root, 'Result', 'result_scatter_routes');
if ~exist(outdir, 'dir'); mkdir(outdir); end
logFile = fullfile(outdir, 'scatter_routes_log.txt');
if exist(logFile, 'file'); delete(logFile); end
diary(logFile); diary on;

nDraw = 400;
CB = [0 0.4470 0.7410];
CO = [0.8500 0.3250 0.0980];
LAB = {'F1 415','F2 445','F3 480','F4 515','F5 555','F6 590','F7 630','F8 680','NIR'};

combos = {
  'white_direct',  'data_white_direct',  'Real', 'Fake', 'Unprinted white area, direct'
  'yellow_direct', 'data_yellow_direct', 'Real', 'Fake', 'Uniform yellow patch, direct'
  'white_photo',   'data_white',         'real', 'fake', 'Unprinted white area, photograph'
  'yellow_photo',  'data_yellow',        'real', 'fake', 'Uniform yellow patch, photograph'
};

R = struct();
rows = cell(0,10);
clfRows = cell(0,8);

for c = 1:size(combos,1)
    tag = combos{c,1}; dirn = combos{c,2};
    lab = combos{c,5};

    S1 = loadNoteSet(fullfile(root, dirn, combos{c,3}));
    S0 = loadNoteSet(fullfile(root, dirn, combos{c,4}));
    X  = [vertcat(S1.mean);    vertcat(S0.mean)];
    y  = [ones(numel(S1),1);   zeros(numel(S0),1)];
    sc = [vertcat(S1.scatter); vertcat(S0.scatter)];
    rp = [vertcat(S1.repeats); vertcat(S0.repeats)];
    Sall = [S1(:); S0(:)];

    fprintf('\n================ %s ================\n', lab);
    fprintf('genuine %d, counterfeit %d, %d to %d readings per note\n', ...
            numel(S1), numel(S0), min(rp), max(rp));

    % ---- 1. repeat-matched scatter and class statistics -----------------
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
    mg  = mean(sc(y==1));  mf  = mean(sc(y==0));
    mgM = mean(scM(y==1)); mfM = mean(scM(y==0));
    dd  = abs(cohend(sc(y==0), sc(y==1)));
    pv  = ranksum(sc(y==1), sc(y==0));
    fprintf('repeat-matched at n = %d (%d draws)\n', nMatch, nDraw);
    fprintf('raw       genuine %.4f, counterfeit %.4f, ratio %.2f, |d| = %.2f, p = %.3g\n', ...
            mg, mf, mf/mg, dd, pv);
    fprintf('rep-match genuine %.4f, counterfeit %.4f, ratio %.2f\n', mgM, mfM, mfM/mgM);

    % ---- 2. overlap -----------------------------------------------------
    ovl = sum(sc(y==1) > min(sc(y==0))) + sum(sc(y==0) < max(sc(y==1)));
    fprintf('overlap: highest genuine %.4f, lowest counterfeit %.4f, %d of %d notes inside the other class range\n', ...
            max(sc(y==1)), min(sc(y==0)), ovl, numel(sc));
    fprintf('counterfeit scatter spans %.4f to %.4f\n', min(sc(y==0)), max(sc(y==0)));

    % ---- 3. per-channel sigma profile ----------------------------------
    sig = zeros(numel(Sall), 9);
    for i = 1:numel(Sall); sig(i,:) = std(Sall(i).X, 0, 1, 'omitnan'); end
    profG = mean(sig(y==1,:), 1);
    profF = mean(sig(y==0,:), 1);
    fprintf('per-channel within-note sigma, genuine / counterfeit:\n');
    for k = 1:9
        fprintf('  %-8s %.4f  %.4f\n', LAB{k}, profG(k), profF(k));
    end

    % ---- 4. classifiers -------------------------------------------------
    fprintf('note-level leave-one-banknote-out:\n');
    setName = {'9 channel means', '9 channels + scatter', 'scatter only'};
    setData = {X, [X sc], sc};
    for k = 1:3
        F = setData{k};
        pl = looPred(@(Xt,Yt) fitcsvm(Xt,Yt,'KernelFunction','linear'), F, y);
        pr = looPred(@(Xt,Yt) fitcsvm(Xt,Yt,'KernelFunction','rbf','BoxConstraint',1), F, y);
        al = mean(pl==y); ar = mean(pr==y);
        fprintf('  %-22s %6.1f%% linear, %6.1f%% rbf, FP %d, FN %d\n', ...
                setName{k}, 100*al, 100*ar, sum(pl==1&y==0), sum(pl==0&y==1));
        clfRows(end+1,:) = {lab, setName{k}, size(F,2), 100*al, 100*ar, ...
                            sum(pl==1&y==0), sum(pl==0&y==1), ...
                            100*max(mean(y),1-mean(y))}; %#ok<AGROW>
    end
    fprintf('  majority-class rate %.1f%%\n', 100*max(mean(y),1-mean(y)));

    rows(end+1,:) = {lab, numel(S1), numel(S0), mg, mf, mf/mg, dd, pv, ovl, numel(sc)}; %#ok<AGROW>
    R.(tag) = struct('sc',sc,'y',y,'lab',lab,'profG',profG,'profF',profF, ...
                     'ratio',mf/mg,'d',dd,'p',pv);
end

% ---- 5 and 6. compare the two routes on each region --------------------
fprintf('\n================ direct against photograph ================\n');
pairs = {'white_direct','white_photo','Unprinted white area'; ...
         'yellow_direct','yellow_photo','Uniform yellow patch'};
cmpRows = cell(0,7);
for q = 1:2
    A = R.(pairs{q,1}); B = R.(pairs{q,2});
    fprintf('\n--- %s ---\n', pairs{q,3});
    fprintf('ratio  direct %.2f, photograph %.2f\n', A.ratio, B.ratio);
    fprintf('|d|    direct %.2f, photograph %.2f\n', A.d, B.d);
    pG = ranksum(A.sc(A.y==1), B.sc(B.y==1));
    pF = ranksum(A.sc(A.y==0), B.sc(B.y==0));
    fprintf('genuine notes scatter %.4f direct against %.4f photograph, rank-sum p = %.3g\n', ...
            mean(A.sc(A.y==1)), mean(B.sc(B.y==1)), pG);
    fprintf('counterfeits          %.4f direct against %.4f photograph, rank-sum p = %.3g\n', ...
            mean(A.sc(A.y==0)), mean(B.sc(B.y==0)), pF);
    rG = corr(A.profG(:), B.profG(:), 'type', 'Spearman');
    rF = corr(A.profF(:), B.profF(:), 'type', 'Spearman');
    rGp = corr(A.profG(:), B.profG(:));
    rFp = corr(A.profF(:), B.profF(:));
    fprintf('per-channel sigma profile, direct against photograph:\n');
    fprintf('  genuine     Spearman rho = %+.2f, Pearson r = %+.2f\n', rG, rGp);
    fprintf('  counterfeit Spearman rho = %+.2f, Pearson r = %+.2f\n', rF, rFp);
    cmpRows(end+1,:) = {pairs{q,3}, A.ratio, B.ratio, A.d, B.d, rG, rF}; %#ok<AGROW>
end

% ---- figures -----------------------------------------------------------
f = figure('Visible','off','Position',[100 100 760 380]);
tg = {'white_photo','yellow_photo'};
for q = 1:2
    subplot(1,2,q); hold on; grid on; box on;
    s = R.(tg{q}).sc; yy = R.(tg{q}).y;
    scatter(1+0.14*(rand(sum(yy==1),1)-0.5), s(yy==1), 42, CB, 'filled', 'MarkerFaceAlpha', 0.75);
    scatter(2+0.14*(rand(sum(yy==0),1)-0.5), s(yy==0), 42, CO, 'filled', 'MarkerFaceAlpha', 0.75);
    plot([0.75 1.25], [1 1]*mean(s(yy==1)), 'k-', 'LineWidth', 1.6);
    plot([1.75 2.25], [1 1]*mean(s(yy==0)), 'k-', 'LineWidth', 1.6);
    set(gca,'XTick',[1 2],'XTickLabel',{'Genuine','Counterfeit'},'FontSize',9);
    xlim([0.5 2.5]); ylabel('within-note scatter');
    title(R.(tg{q}).lab, 'FontSize', 10);
end
savePad(f, fullfile(outdir,'fig_scatter_photo.png')); close(f);

% The same four combinations in one 2x2 panel, rows = route, columns = region,
% so that Chapter 7 can report both routes in a single section.  One shared log
% y limit: the direct counterfeit spread covers three orders of magnitude, which
% a linear axis shared between the routes would flatten out of sight.
f = figure('Visible','off','Position',[100 100 820 560]);
cmb = {'white_direct','yellow_direct'; 'white_photo','yellow_photo'};
rowLab = {'Direct measurement','Photographic route'};
allSc = [R.white_direct.sc(:); R.yellow_direct.sc(:); ...
         R.white_photo.sc(:);  R.yellow_photo.sc(:)];
lo = 0.7*min(allSc(allSc > 0)); hi = 1.5*max(allSc);
for r = 1:2
    for c = 1:2
        subplot(2,2,(r-1)*2+c); hold on; grid on; box on;
        K = R.(cmb{r,c}); s = K.sc; yy = K.y;
        scatter(1+0.14*(rand(sum(yy==1),1)-0.5), s(yy==1), 34, CB, 'filled', 'MarkerFaceAlpha', 0.75);
        scatter(2+0.14*(rand(sum(yy==0),1)-0.5), s(yy==0), 34, CO, 'filled', 'MarkerFaceAlpha', 0.75);
        plot([0.75 1.25], [1 1]*mean(s(yy==1)), 'k-', 'LineWidth', 1.6);
        plot([1.75 2.25], [1 1]*mean(s(yy==0)), 'k-', 'LineWidth', 1.6);
        set(gca,'XTick',[1 2],'XTickLabel',{'Genuine','Counterfeit'}, ...
                'YScale','log','FontSize',9);
        xlim([0.5 2.5]); ylim([lo hi]);
        if c == 1; ylabel({rowLab{r}; 'within-note scatter'}); end
        if r == 1; title(pairs{c,3}, 'FontSize', 10); end
    end
end
savePad(f, fullfile(outdir,'fig_scatter_class_routes.png')); close(f);

% Kept short: at \linewidth this figure has to share a page with the text that
% calls it, and a taller aspect pushes it onto the next page on its own.
f = figure('Visible','off','Position',[100 100 950 300]);
for q = 1:2
    A = R.(pairs{q,1}); B = R.(pairs{q,2});
    subplot(1,2,q); hold on; grid on; box on;
    h = bar([A.profG(:) A.profF(:) B.profG(:) B.profF(:)], 1.0, 'EdgeColor','none');
    h(1).FaceColor = CB;               h(2).FaceColor = CO;
    h(3).FaceColor = min(CB+0.42,1);   h(4).FaceColor = min(CO+0.42,1);
    set(gca,'XTick',1:9,'XTickLabel',LAB,'XTickLabelRotation',45,'FontSize',8);
    ylabel('within-note \sigma'); xlim([0.4 9.6]);
    % headroom so the legend at the top clears the tallest bar
    ylim([0 1.38*max([A.profG(:); A.profF(:); B.profG(:); B.profF(:)])]);
    title(pairs{q,3}, 'FontSize', 10);
    if q == 1
        legend({'genuine, direct','counterfeit, direct', ...
                'genuine, photo','counterfeit, photo'}, 'FontSize', 7, ...
               'Location','north', 'NumColumns', 2);
    end
end
savePad(f, fullfile(outdir,'fig_scatter_channels_routes.png')); close(f);

% The same profiles split one figure per route, so that Chapter 7 can put the
% direct group in its own section and the photographic group in its own.  Both
% figures share one y limit, taken over all four combinations, so the two
% remain comparable across the page break.
yTop = 1.30 * max([R.white_direct.profG(:); R.white_direct.profF(:); ...
                   R.white_photo.profG(:);  R.white_photo.profF(:); ...
                   R.yellow_direct.profG(:);R.yellow_direct.profF(:); ...
                   R.yellow_photo.profG(:); R.yellow_photo.profF(:)]);
routeFigs = {1, 'fig_scatter_channels_direct.png'; ...
             2, 'fig_scatter_channels_photo.png'};   % column of pairs to use
for r = 1:2
    col = routeFigs{r,1};
    f = figure('Visible','off','Position',[100 100 900 380]);
    for q = 1:2
        C = R.(pairs{q,col});
        subplot(1,2,q); hold on; grid on; box on;
        hb = bar([C.profG(:) C.profF(:)], 0.9, 'EdgeColor','none');
        if col == 1
            hb(1).FaceColor = CB;             hb(2).FaceColor = CO;
        else
            hb(1).FaceColor = min(CB+0.42,1); hb(2).FaceColor = min(CO+0.42,1);
        end
        set(gca,'XTick',1:9,'XTickLabel',LAB,'XTickLabelRotation',45,'FontSize',8);
        ylabel('within-note \sigma'); xlim([0.4 9.6]); ylim([0 yTop]);
        title(pairs{q,3}, 'FontSize', 10);
        if q == 1
            legend({'genuine','counterfeit'}, 'FontSize', 8, ...
                   'Location','north', 'NumColumns', 2);
        end
    end
    savePad(f, fullfile(outdir, routeFigs{r,2})); close(f);
end

writetable(cell2table(rows, 'VariableNames', ...
  {'Combination','nGenuine','nCounterfeit','ScatterGenuine','ScatterCounterfeit', ...
   'Ratio','CohenD','RanksumP','NotesOverlapping','NotesTotal'}), ...
  fullfile(outdir,'scatter_routes_summary.csv'));
writetable(cell2table(clfRows, 'VariableNames', ...
  {'Combination','FeatureSet','nFeatures','LinearSVM','RbfSVM','FP','FN','MajorityRate'}), ...
  fullfile(outdir,'scatter_routes_classifiers.csv'));
writetable(cell2table(cmpRows, 'VariableNames', ...
  {'Region','RatioDirect','RatioPhoto','dDirect','dPhoto','RhoProfileGenuine','RhoProfileCounterfeit'}), ...
  fullfile(outdir,'scatter_routes_comparison.csv'));

% per-note scatter values, so the spread of a class can be inspected and not
% only its mean: a noise floor lifts the bottom of a distribution without
% moving the top, which the class mean alone does not show.
pnRows = cell(0,4);
pnKeys = {'white_direct','yellow_direct','white_photo','yellow_photo'};
for k = 1:numel(pnKeys)
    K = R.(pnKeys{k});
    for i = 1:numel(K.sc)
        pnRows(end+1,:) = {pnKeys{k}, i, K.y(i), K.sc(i)}; %#ok<AGROW>
    end
end
writetable(cell2table(pnRows, 'VariableNames', ...
  {'Combination','Index','IsGenuine','Scatter'}), ...
  fullfile(outdir,'scatter_routes_per_note.csv'));

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
