function direct_vs_rgb(region)
% DIRECT_VS_RGB  Nine-channel versus RGB comparison on a directly measured
% region, and a comparison against the screen-captured data of Chapter 6.
%
%   direct_vs_rgb            % unprinted white area (default)
%   direct_vs_rgb('yellow')  % uniform yellow patch
%
% Direct set : data_<region>_direct/{Real,Fake}/*.csv (note in front of sensor)
% Screen set : data_<region>/{real,fake}/CSV/*.csv    (diffuser on the display)
%
% Features are Clear-normalised channel ratios, so a change of analogue gain
% cancels to first order.  SNV is deliberately NOT applied: standardising a
% three-component vector removes two of its three degrees of freedom and would
% cripple the RGB emulations the comparison is about.  Readings whose Clear
% channel is at or above 65000 counts (full scale 65535) are discarded.

if nargin < 1; region = 'white'; end
switch lower(region)
    case 'white';  dirDirect = 'data_white_direct';  dirScreen = 'data_white';
                   outName = 'result_direct_rgb';    regLab = 'Unprinted white area';
                   regNote = 'diffuser on the note';
    case 'yellow'; dirDirect = 'data_yellow_direct'; dirScreen = 'data_yellow';
                   outName = 'result_direct_yellow'; regLab = 'Uniform yellow patch';
                   regNote = 'uniform yellow patch';
    otherwise; error('unknown region %s', region);
end

root   = fileparts(fileparts(mfilename('fullpath')));
outdir = fullfile(root, 'Result', outName);
if ~exist(outdir, 'dir'); mkdir(outdir); end
logFile = fullfile(outdir, 'direct_vs_rgb_log.txt');
if exist(logFile, 'file'); delete(logFile); end
diary(logFile); diary on;

CH  = {'F1 (415nm)','F2 (445nm)','F3 (480nm)','F4 (515nm)','F5 (555nm)', ...
       'F6 (590nm)','F7 (630nm)','F8 (680nm)','NIR'};
LAB = {'F1 415nm','F2 445nm','F3 480nm','F4 515nm','F5 555nm', ...
       'F6 590nm','F7 630nm','F8 680nm','NIR'};
CB = [0 0.4470 0.7410];        % house blue  (Real)
CO = [0.8500 0.3250 0.0980];   % house orange (Fake)

fprintf('==== direct set ====\n');
[Xd, yd, gaind, sdd, nmd] = loadSet(fullfile(root,dirDirect,'Real'), ...
                                   fullfile(root,dirDirect,'Fake'), CH);
fprintf('==== screen set ====\n');
[Xs, ys] = loadSet(fullfile(root,dirScreen,'real','CSV'), ...
                   fullfile(root,dirScreen,'fake','CSV'), CH);

% --- 1. gain confound ----------------------------------------------------
fprintf('\n--- 1. gain confound ---\n');
fprintf('mean analogue gain: genuine %.0fx, counterfeit %.0fx\n', ...
        mean(gaind(yd==1)), mean(gaind(yd==0)));
gainShift(fullfile(root,dirDirect,'Real'), CH);
gainShift(fullfile(root,dirDirect,'Fake'), CH);

% --- 2. per-channel effect size ------------------------------------------
fprintf('\n--- 2. per-channel Cohen d on per-note means ---\n');
fprintf('%-12s %10s %10s\n', 'channel', 'direct', 'screen');
for k = 1:8
    fprintf('%-12s %10.2f %10.2f\n', CH{k}, ...
        cohend(Xd(yd==1,k), Xd(yd==0,k)), cohend(Xs(ys==1,k), Xs(ys==0,k)));
end

% --- 3. eight channels versus RGB emulations -----------------------------
fprintf('\n--- 3. classification, leave-one-note-out linear SVM ---\n');
dch = arrayfun(@(k) abs(cohend(Xd(yd==1,k), Xd(yd==0,k))), 1:8);
[~, kb] = max(dch);                       % best single channel of the direct set
names = {'8 channels F1-F8', 'RGB-A broad bands', 'RGB-B picked channels', ...
         sprintf('1 channel %s', LAB{kb})};
Fd = {Xd(:,1:8), rgbBands(Xd), Xd(:,[2 5 7]), Xd(:,kb)};
Fs = {Xs(:,1:8), rgbBands(Xs), Xs(:,[2 5 7]), Xs(:,kb)};
accd = zeros(1,4);
fprintf('%-24s %14s %14s\n', 'features', 'direct acc.', 'screen acc.');
for i = 1:4
    accd(i) = looAcc(Fd{i}, yd);
    fprintf('%-24s %13.1f%% %13.1f%%\n', names{i}, 100*accd(i), 100*looAcc(Fs{i}, ys));
end

fprintf('\n--- 3b. single-reading accuracy, note-level leave-one-out ---\n');
[Rd, Rid, Ryd] = loadReadings(fullfile(root,dirDirect,'Real'), ...
                              fullfile(root,dirDirect,'Fake'), CH);
Gd = {Rd(:,1:8), rgbBands(Rd), Rd(:,[2 5 7]), Rd(:,kb)};
fprintf('%-24s %14s\n', 'features', 'direct acc.');
for i = 1:4
    fprintf('%-24s %13.1f%%\n', names{i}, 100*looReadings(Gd{i}, Ryd, Rid));
end

% --- 4. within-note scatter ---------------------------------------------
fprintf('\n--- 4. within-note scatter, mean s.d. over the eight channels ---\n');
fprintf('direct: genuine %.4f, counterfeit %.4f, ratio %.2f\n', ...
        mean(sdd(yd==1)), mean(sdd(yd==0)), mean(sdd(yd==0))/mean(sdd(yd==1)));

% --- 5. confusion matrix and per-note margin -----------------------------
[pred, marg] = looDetail(Xd(:,1:8), yd);
C = zeros(2,2);
for i = 1:numel(yd); C(2-yd(i), 2-pred(i)) = C(2-yd(i), 2-pred(i)) + 1; end
fprintf('\n--- 5. confusion matrix, 8 channels, leave-one-note-out ---\n');
fprintf('              pred genuine  pred counterfeit\n');
fprintf('true genuine     %6d           %6d\n', C(1,1), C(1,2));
fprintf('true counterfeit %6d           %6d\n', C(2,1), C(2,2));
fprintf('margin to true class: genuine %.2f--%.2f, counterfeit %.2f--%.2f\n', ...
        min(marg(yd==1)), max(marg(yd==1)), min(marg(yd==0)), max(marg(yd==0)));

% ===================== figures, house style ============================

% (a) class-mean spectra of the direct set, with error bars
f = figure('Visible','off','Position',[100 100 620 400]);
hold on; grid on; box on;
e1 = errorbar(1:9, mean(Xd(yd==1,:),1), std(Xd(yd==1,:),0,1), '-o', ...
              'Color', CB, 'MarkerFaceColor', CB, 'LineWidth', 1.3, 'CapSize', 4);
e2 = errorbar(1:9, mean(Xd(yd==0,:),1), std(Xd(yd==0,:),0,1), '-o', ...
              'Color', CO, 'MarkerFaceColor', CO, 'LineWidth', 1.3, 'CapSize', 4);
set(gca,'XTick',1:9,'XTickLabel',LAB,'XTickLabelRotation',45,'FontSize',9);
xlim([0.6 9.4]); xlabel('AS7341 Channel'); ylabel('channel / Clear');
title({'Class Mean Spectral Comparison - Clear-ratio', ...
       ['Direct measurement, ' regNote]}, 'FontSize', 10);
legend([e1 e2], {'Real mean +/- std','Fake mean +/- std'}, 'Location','northwest');
savePad(f, fullfile(outdir,'fig_direct_class_mean.png'));
close(f);

% (b) confusion matrix
f = figure('Visible','off','Position',[100 100 520 430]);
drawConfusion(C, {'Real','Fake'}, ...
   {'Real vs current fakes, direct measurement (20 notes)', ...
    sprintf('Binary note-level LOO (Linear SVM), accuracy = %.2f%%', 100*accd(1))});
savePad(f, fullfile(outdir,'fig_direct_confusion.png'));
close(f);

% (c) per-note margin
[ms, ord] = sort(marg, 'ascend');   % least confident at the top, as elsewhere
f = figure('Visible','off','Position',[100 100 620 460]);
hold on; box on;
for i = 1:numel(ord)
    if yd(ord(i)) == 1; col = CB; else; col = CO; end
    barh(i, ms(i), 0.72, 'FaceColor', col, 'EdgeColor', 'none');
end
xl = [min(-0.15, 1.1*min(ms)) 1.15*max(ms)];
plot([0 0], [0.4 numel(ord)+0.6], 'k--', 'LineWidth', 0.8);
set(gca,'YTick',1:numel(ord),'YTickLabel',nmd(ord),'YDir','reverse', ...
        'FontSize',8,'XGrid','on');
ylim([0.4 numel(ord)+0.6]); xlim(xl);
xlabel('margin towards true class');
title({[regLab ', direct measurement: per-note margin'], ...
       'blue = Real, orange = Fake (top = least confident)'}, 'FontSize', 10);
savePad(f, fullfile(outdir,'fig_direct_margin.png'));
close(f);

% (d) direct against screen, class means side by side
f = figure('Visible','off','Position',[100 100 1000 400]);
for s = 1:2
    subplot(1,2,s); hold on; grid on; box on;
    if s == 1; X = Xd; y = yd; ttl = 'Direct measurement'; else; X = Xs; y = ys; ttl = 'Screen measurement'; end
    errorbar(1:9, mean(X(y==1,:),1), std(X(y==1,:),0,1), '-o', ...
             'Color', CB, 'MarkerFaceColor', CB, 'LineWidth', 1.3, 'CapSize', 4);
    errorbar(1:9, mean(X(y==0,:),1), std(X(y==0,:),0,1), '-o', ...
             'Color', CO, 'MarkerFaceColor', CO, 'LineWidth', 1.3, 'CapSize', 4);
    set(gca,'XTick',1:9,'XTickLabel',LAB,'XTickLabelRotation',45,'FontSize',9);
    xlim([0.6 9.4]); xlabel('AS7341 Channel'); ylabel('channel / Clear');
    title(ttl, 'FontSize', 10);
    if s == 1; legend({'Real mean +/- std','Fake mean +/- std'}, 'Location','northwest'); end
end
savePad(f, fullfile(outdir,'fig_direct_vs_screen_spectra.png'));
close(f);

fprintf('\nwritten to %s\n', outdir);
diary off;
end

% ------------------------------------------------------------------------
function drawConfusion(C, labs, ttl)
n = size(C,1); tot = sum(C(:));
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
if tot < 0; end
end

% ------------------------------------------------------------------------
function [X, y, gain, sdev, nm] = loadSet(realDir, fakeDir, CH)
[Xr, gr, sr, nr] = loadDir(realDir, CH);
[Xf, gf, sf, nf] = loadDir(fakeDir, CH);
X = [Xr; Xf];
y = [ones(size(Xr,1),1); zeros(size(Xf,1),1)];
gain = [gr; gf]; sdev = [sr; sf]; nm = [nr, nf];
fprintf('genuine notes %d, counterfeit notes %d\n', size(Xr,1), size(Xf,1));
end

% ------------------------------------------------------------------------
function [X, gain, sdev, nm] = loadDir(d, CH)
f = dir(fullfile(d, '*.csv'));
X = []; gain = []; sdev = []; nm = {};
for i = 1:numel(f)
    T = readtable(fullfile(d, f(i).name), 'Delimiter', ';', 'VariableNamingRule', 'preserve');
    cl = T.('Clear');
    keep = cl > 0 & cl < 65000;
    if ~any(keep); continue; end
    R = zeros(sum(keep), numel(CH));
    for k = 1:numel(CH); R(:,k) = T.(CH{k})(keep) ./ cl(keep); end
    X(end+1,:)    = mean(R, 1);          %#ok<AGROW>
    sdev(end+1,1) = mean(std(R(:,1:8), 0, 1)); %#ok<AGROW>
    g = T.('Gain [x]'); gain(end+1,1) = mean(g(keep)); %#ok<AGROW>
    [~, base] = fileparts(f(i).name);
    nm{end+1} = [upper(base(1)) base(2:end)]; %#ok<AGROW>
end
end

% ------------------------------------------------------------------------
function [R, noteId, y] = loadReadings(realDir, fakeDir, CH)
R = []; noteId = []; y = []; nid = 0;
for c = 1:2
    if c == 1; d = realDir; lab = 1; else; d = fakeDir; lab = 0; end
    f = dir(fullfile(d, '*.csv'));
    for i = 1:numel(f)
        T = readtable(fullfile(d, f(i).name), 'Delimiter', ';', 'VariableNamingRule', 'preserve');
        cl = T.('Clear'); keep = cl > 0 & cl < 65000;
        if ~any(keep); continue; end
        nid = nid + 1;
        M = zeros(sum(keep), numel(CH));
        for k = 1:numel(CH); M(:,k) = T.(CH{k})(keep) ./ cl(keep); end
        R = [R; M];                                   %#ok<AGROW>
        noteId = [noteId; repmat(nid, sum(keep), 1)]; %#ok<AGROW>
        y = [y; repmat(lab, sum(keep), 1)];           %#ok<AGROW>
    end
end
end

% ------------------------------------------------------------------------
function B = rgbBands(X)
B = [sum(X(:,1:3),2), sum(X(:,4:5),2), sum(X(:,6:8),2)];
end

% ------------------------------------------------------------------------
function savePad(f, p)
% exportgraphics crops flush to the content, which reads as text jammed
% against the frame once the figure is placed in the report.  Add a white
% border at export instead of padding the rasters afterwards.
exportgraphics(f, p, 'Resolution', 220);
I = imread(p); [h, w, c] = size(I); m = 24;
J = uint8(255 * ones(h + 2*m, w + 2*m, c, 'uint8'));
J(m+1:m+h, m+1:m+w, :) = I;
imwrite(J, p);
end

% ------------------------------------------------------------------------
function a = looAcc(F, y)
n = numel(y); ok = 0;
for i = 1:n
    tr = true(n,1); tr(i) = false;
    mu = mean(F(tr,:),1); sg = std(F(tr,:),0,1); sg(sg==0) = 1;
    m = fitcsvm((F(tr,:)-mu)./sg, y(tr), 'KernelFunction','linear');
    ok = ok + (predict(m, (F(i,:)-mu)./sg) == y(i));
end
a = ok/n;
end

% ------------------------------------------------------------------------
function a = looReadings(F, y, noteId)
notes = unique(noteId); ok = 0; tot = 0;
for i = 1:numel(notes)
    te = noteId == notes(i); tr = ~te;
    mu = mean(F(tr,:),1); sg = std(F(tr,:),0,1); sg(sg==0) = 1;
    m = fitcsvm((F(tr,:)-mu)./sg, y(tr), 'KernelFunction','linear');
    p = predict(m, (F(te,:)-mu)./sg);
    ok = ok + sum(p == y(te)); tot = tot + sum(te);
end
a = ok/tot;
end

% ------------------------------------------------------------------------
function [pred, marg] = looDetail(F, y)
n = numel(y); pred = zeros(n,1); marg = zeros(n,1);
for i = 1:n
    tr = true(n,1); tr(i) = false;
    mu = mean(F(tr,:),1); sg = std(F(tr,:),0,1); sg(sg==0) = 1;
    m = fitcsvm((F(tr,:)-mu)./sg, y(tr), 'KernelFunction','linear');
    [p, s] = predict(m, (F(i,:)-mu)./sg);
    pred(i) = p; marg(i) = (2*y(i)-1) * s(2);
end
end

% ------------------------------------------------------------------------
function d = cohend(a, b)
na = numel(a); nb = numel(b);
sp = sqrt(((na-1)*var(a) + (nb-1)*var(b)) / (na+nb-2));
d = (mean(a) - mean(b)) / sp;
end

% ------------------------------------------------------------------------
function gainShift(d, CH)
f = dir(fullfile(d, '*.csv'));
for i = 1:numel(f)
    T = readtable(fullfile(d, f(i).name), 'Delimiter', ';', 'VariableNamingRule', 'preserve');
    cl = T.('Clear'); g = T.('Gain [x]');
    keep = cl > 0 & cl < 65000; cl = cl(keep); g = g(keep);
    gu = unique(g); if numel(gu) < 2; continue; end
    cnt = arrayfun(@(v) sum(g == v), gu);
    [cnt, ord] = sort(cnt, 'descend'); gu = gu(ord);
    if cnt(1) < 5 || cnt(2) < 5; continue; end
    m = zeros(2, 8);
    for k = 1:8
        v = T.(CH{k})(keep) ./ cl;
        m(1,k) = mean(v(g == gu(1))); m(2,k) = mean(v(g == gu(2)));
    end
    rel = max(abs(m(2,:) - m(1,:)) ./ m(1,:));
    fprintf('  %-12s %4.0fx vs %4.0fx : largest channel shift %.1f%%\n', ...
            f(i).name, gu(1), gu(2), 100*rel);
end
end
