function rgb_vs_multispectral()
% RGB_VS_MULTISPECTRAL  What the extra spectral channels buy over plain RGB,
% measured rather than argued (Discussion, "What the Capture Chain Measures").
%
% Every spectrum in Chapter 6 was read from a photograph displayed on a screen,
% so the note's reflectance passed through a three-channel camera before the
% AS7341 ever saw it.  The section claims that the eleven readings are therefore
% eleven samples of a three-dimensional space.  This script tests that claim on
% the recorded data, using the cropped photographs that are stored next to the
% CSV files and were the object the sensor actually measured.
%
% Four comparisons per region:
%   1. note-level accuracy from nine channels, from synthesised RGB, from the
%      RGB of the paired photograph, and from the best single channel;
%   2. how much of each channel a linear model of the image RGB explains (R^2);
%   3. whether the residual, i.e. what the channels know beyond the image RGB,
%      still separates the classes;
%   4. cumulative variance of the nine channels, screen route against the
%      directly measured white-area set of data_white_direct.
%
% Region 1 (data_20) is the primary case: the crop is exactly the sampled area
% and the nine-channel accuracy is 96.3%, so the comparison is not at ceiling.
% The data_white and data_yellow crops are the same image, containing both the
% yellow patch and the white margin, so a fixed box selects the sampled part
% and fig_rgb_boxes.png shows where it falls.

root   = fileparts(fileparts(mfilename('fullpath')));
outdir = fullfile(root, 'Result', 'result_rgb_vs_ms');
if ~exist(outdir, 'dir'); mkdir(outdir); end
logFile = fullfile(outdir, 'rgb_vs_ms_log.txt');
if exist(logFile, 'file'); delete(logFile); end
diary(logFile); diary on;

LAB = {'F1 415','F2 445','F3 480','F4 515','F5 555','F6 590','F7 630','F8 680','NIR'};

% region name, folder, image sub-box [x0 x1 y0 y1] as fractions of the crop
REG = { ...
  'digit stroke',  'data_20',     [0 1 0 1]; ...
  'yellow patch',  'data_yellow', [0.35 0.95 0.25 0.85]; ...
  'white area',    'data_white',  [0.00 0.13 0.15 0.90]};

acc = nan(size(REG,1), 8);
r2all = nan(size(REG,1), 9);

for r = 1:size(REG,1)
    name = REG{r,1}; folder = fullfile(root, REG{r,2}); bx = REG{r,3};
    fprintf('\n================ %s  (%s) ================\n', name, REG{r,2});

    [X9, y, notes, Xraw] = channelMeans(folder);
    Xrep = reportMeans(folder);                % SNV per reading, then note mean
    [RGBlin, RGBgam, ok] = imageMeans(folder, notes, bx);

    X9 = X9(ok,:); y = y(ok); RGBlin = RGBlin(ok,:); RGBgam = RGBgam(ok,:);
    Xrep = Xrep(ok,:); Xraw = Xraw(ok,:);
    fprintf('notes paired with a photograph: %d genuine, %d counterfeit\n', ...
            sum(y==1), sum(y==0));

    % ---- 1. accuracy from each feature set ------------------------------
    chrom = RGBlin ./ sum(RGBlin, 2);          % remove overall exposure
    [~, kbest] = max(abs(arrayfun(@(k) cohend(X9(y==1,k), X9(y==0,k)), 1:9)));
    F = { Xrep, X9, rgbBands(X9), X9(:,[2 5 7]), chrom, X9(:,kbest), ...
          RGBlin, Xraw(:,1:9) };
    nm = {'9 channels + SNV (report)', '9 channels, Clear ratio', ...
          '3 broad bands from the channels', '3 narrow channels F2/F5/F7', ...
          'RGB of the photograph', sprintf('best single channel (%s)', LAB{kbest}), ...
          'RGB of the photograph, level kept', '9 channels, level kept'};
    fprintf('\n--- 1. note-level leave-one-note-out linear SVM ---\n');
    for i = 1:numel(F)
        [a, nerr] = looAcc(F{i}, y);
        acc(r,i) = a;
        fprintf('%-32s %6.1f%%   (%d of %d notes wrong)\n', nm{i}, 100*a, nerr, numel(y));
    end

    fprintf('mean corrected Clear: genuine %7.4f, counterfeit %7.4f\n', ...
            mean(Xraw(y==1,10)), mean(Xraw(y==0,10)));
    fprintf('mean image luminance: genuine %6.3f, counterfeit %6.3f\n', ...
            mean(sum(RGBlin(y==1,:),2)), mean(sum(RGBlin(y==0,:),2)));

    % ---- 2. how much of each channel the image RGB explains --------------
    P = [chrom(:,1:2) ones(size(chrom,1),1)];   % r+g+b = 1, so two suffice
    B = P \ X9;  Xhat = P * B;  Res = X9 - Xhat;
    r2 = 1 - var(Res,0,1) ./ var(X9,0,1);
    r2all(r,:) = r2;
    fprintf('\n--- 2. R^2 of each channel predicted from the image RGB ---\n');
    fprintf('%s\n', strjoin(compose('%-8s', string(LAB)), ''));
    fprintf('%s\n', strjoin(compose('%-8.3f', r2), ''));
    fprintf('median R^2 %.3f, minimum %.3f (%s)\n', median(r2), min(r2), LAB{r2==min(r2)});

    % ---- 3. does the residual still separate the classes? ----------------
    dres = arrayfun(@(k) cohend(Res(y==1,k), Res(y==0,k)), 1:9);
    [ares, nres] = looAcc(Res, y);
    fprintf('\n--- 3. residual after removing the RGB-predictable part ---\n');
    fprintf('largest residual effect size |d| = %.2f (%s)\n', max(abs(dres)), LAB{abs(dres)==max(abs(dres))});
    fprintf('accuracy on the residual alone   %.1f%%  (%d of %d notes wrong)\n', ...
            100*ares, nres, numel(y));

    % ---- 4. dimensionality ----------------------------------------------
    [~,~,lat] = pca(zscore(X9));
    cv = 100*cumsum(lat)/sum(lat);
    fprintf('\n--- 4. cumulative variance of the nine channels ---\n');
    fprintf('PC1 %.2f%%  PC1-2 %.2f%%  PC1-3 %.2f%%  residual beyond PC3 %.2f%%\n', ...
            cv(1), cv(2), cv(3), 100-cv(3));

    if r == 1
        saveBoxFigure(folder, notes, bx, outdir, REG);   % overlay check
        keepChrom = chrom; keepX9 = X9; keepY = y; keepRes = Res; keepGam = RGBgam;
    end
end

% ---- 5. gamma-encoded RGB as a robustness check on region 1 -------------
fprintf('\n================ robustness, region 1 ================\n');
g = keepGam ./ sum(keepGam, 2);
[a1,~] = looAcc(g, keepY);
fprintf('RGB of the photograph, gamma encoded as stored: %.1f%%\n', 100*a1);
[a2,~] = looAcc([keepChrom keepX9(:,9)], keepY);
fprintf('image RGB plus the NIR channel:                 %.1f%%\n', 100*a2);

% ---- 6. screen route against the direct measurement ---------------------
fprintf('\n================ screen against direct, white area ================\n');
Xs = channelMeans(fullfile(root,'data_white'));
Xd = directWhite(fullfile(root,'data_white_direct'));
for s = 1:2
    if s==1; X = Xs; t = 'screen'; else; X = Xd; t = 'direct'; end
    [~,~,lat] = pca(zscore(X(:,1:8)));
    cv = 100*cumsum(lat)/sum(lat);
    fprintf('%-7s: PC1-3 %.2f%%, residual beyond PC3 %.2f%%\n', t, cv(3), 100-cv(3));
end

% ===================== figures ==========================================
CB = [0 0.4470 0.7410]; CO = [0.8500 0.3250 0.0980];

f = figure('Visible','off','Position',[100 100 760 420]);
b = bar(100*acc, 'grouped'); grid on; box on;
set(gca,'XTickLabel',REG(:,1),'FontSize',9); ylim([50 104]);
ylabel('note-level accuracy (%)');
legend({'9 ch + SNV','9 ch','3 broad bands','3 narrow ch','photo RGB', ...
        'best 1 ch','photo RGB, level kept','9 ch, level kept'}, ...
       'Location','southoutside','Orientation','horizontal','NumColumns',3);
title('Spectral channels against RGB, same notes and same validation','FontSize',10);
exportgraphics(f, fullfile(outdir,'fig_rgb_vs_channels.png'), 'Resolution', 220);
close(f);

f = figure('Visible','off','Position',[100 100 700 400]);
plot(1:9, r2all', '-o', 'LineWidth', 1.3); grid on; box on;
set(gca,'XTick',1:9,'XTickLabel',LAB,'XTickLabelRotation',45,'FontSize',9);
ylim([0 1.02]); ylabel('R^2 explained by the image RGB');
legend(REG(:,1), 'Location','southeast');
title('Each channel predicted from the three colours of the photograph','FontSize',10);
exportgraphics(f, fullfile(outdir,'fig_channel_r2.png'), 'Resolution', 220);
close(f);

fprintf('\nwritten to %s\n', outdir);
diary off;
end

% ======================================================================
function [X, y, notes, Xraw] = channelMeans(folder)
% Note-mean Clear-ratio spectra, genuine first, in the same order as the names.
    S1 = loadRatio(fullfile(folder,'real'));  if isempty(S1); S1 = loadRatio(fullfile(folder,'Real')); end
    S0 = loadRatio(fullfile(folder,'fake'));  if isempty(S0); S0 = loadRatio(fullfile(folder,'Fake')); end
    X  = [vertcat(S1.mean); vertcat(S0.mean)];
    Xraw = [vertcat(S1.raw); vertcat(S0.raw)];
    y  = [ones(numel(S1),1); zeros(numel(S0),1)];
    notes = [string({S1.name})'; string({S0.name})'];
end

function S = loadRatio(folder)
    S = struct('name',{},'mean',{},'raw',{});
    if ~isfolder(folder); return; end
    files = dir(fullfile(folder,'**','*.csv'));
    for i = 1:numel(files)
        [M, R] = readAS(fullfile(files(i).folder, files(i).name));
        if isempty(M); continue; end
        S(end+1).name = erase(files(i).name, '.csv');  %#ok<AGROW>
        S(end).mean   = mean(M, 1, 'omitnan');
        S(end).raw    = mean(R, 1, 'omitnan');
    end
    [~, o] = sort(str2double(regexp(string({S.name}), '\d+$', 'match', 'once')));
    S = S(o);
end

function [X, R] = readAS(fp)
    cols = ["Corr F1 (415nm)","Corr F2 (445nm)","Corr F3 (480nm)","Corr F4 (515nm)", ...
            "Corr F5 (555nm)","Corr F6 (590nm)","Corr F7 (630nm)","Corr F8 (680nm)", ...
            "Corr Clear","Corr NIR"];
    opts = detectImportOptions(fp,'Delimiter',';');
    opts.VariableNamingRule = 'preserve';
    T = readtable(fp, opts);
    if ~all(ismember(cols, string(T.Properties.VariableNames))); X = []; R = []; return; end
    M = double(table2array(T(:, cols)));
    M = M(~all(isnan(M),2) & M(:,9) > 0, :);
    if isempty(M); X = []; R = []; return; end
    X = [M(:,1:8) ./ M(:,9), M(:,10) ./ M(:,9)];
    R = [M(:,1:8), M(:,10), M(:,9)];            % raw counts, Clear last
end

function X = reportMeans(folder)
% Exactly the Chapter 6 pipeline: SNV per reading, then the note mean.
    S1 = loadNoteSet(fullfile(folder,'real'));
    if isempty(S1); S1 = loadNoteSet(fullfile(folder,'Real')); end
    S0 = loadNoteSet(fullfile(folder,'fake'));
    if isempty(S0); S0 = loadNoteSet(fullfile(folder,'Fake')); end
    X = [vertcat(S1.mean); vertcat(S0.mean)];
end

function X = directWhite(folder)
    S1 = loadRatio(fullfile(folder,'Real')); S0 = loadRatio(fullfile(folder,'Fake'));
    X  = [vertcat(S1.mean); vertcat(S0.mean)];
end

% ----------------------------------------------------------------------
function [Lin, Gam, ok] = imageMeans(folder, notes, bx)
% Mean colour of the paired photograph inside the sub-box, linear and as stored.
    n = numel(notes); Lin = nan(n,3); Gam = nan(n,3); ok = false(n,1);
    for i = 1:n
        cls = 'real'; if startsWith(lower(notes(i)), 'fake'); cls = 'fake'; end
        k = regexp(notes(i), '\d+$', 'match', 'once');
        fp = fullfile(folder, cls, sprintf('%s (%s).JPG', cls, k));
        if ~isfile(fp)
            d = dir(fullfile(folder, cls, sprintf('*(%s).*', k)));
            if isempty(d); warning('no photograph for %s', notes(i)); continue; end
            fp = fullfile(d(1).folder, d(1).name);
        end
        I = im2double(imread(fp));
        [h, w, ~] = size(I);
        xs = max(1,round(bx(1)*w)) : max(2,round(bx(2)*w));
        ys = max(1,round(bx(3)*h)) : max(2,round(bx(4)*h));
        P  = reshape(I(ys, xs, :), [], 3);
        Gam(i,:) = mean(P, 1);
        Lin(i,:) = mean(srgb2lin(P), 1);
        ok(i) = true;
    end
end

function L = srgb2lin(C)
    L = C; m = C <= 0.04045;
    L(m)  = C(m) / 12.92;
    L(~m) = ((C(~m) + 0.055) / 1.055) .^ 2.4;
end

function saveBoxFigure(folder, notes, bx, outdir, REG)
% One genuine crop per region with the sampled box drawn on it.
    f = figure('Visible','off','Position',[100 100 900 340]);
    root = fileparts(folder);
    for r = 1:size(REG,1)
        fp = fullfile(root, REG{r,2}, 'real', 'real (1).JPG');
        if ~isfile(fp); continue; end
        I = imread(fp); [h,w,~] = size(I); b = REG{r,3};
        subplot(1,3,r); imshow(I); hold on;
        rectangle('Position', [b(1)*w b(3)*h (b(2)-b(1))*w (b(4)-b(3))*h], ...
                  'EdgeColor', [0.85 0.33 0.10], 'LineWidth', 2);
        title(REG{r,1}, 'FontSize', 9);
    end
    exportgraphics(f, fullfile(outdir,'fig_rgb_boxes.png'), 'Resolution', 160);
    close(f);
end

% ----------------------------------------------------------------------
function B = rgbBands(X)
    B = [sum(X(:,1:3),2), sum(X(:,4:5),2), sum(X(:,6:8),2)];
end

function Xout = snvRows(Xin)
    m = mean(Xin,2,'omitnan'); s = std(Xin,0,2,'omitnan'); s(s==0) = eps;
    Xout = (Xin - m) ./ s;
end

function [a, nerr] = looAcc(F, y)
    n = numel(y); ok = 0;
    for i = 1:n
        tr = true(n,1); tr(i) = false;
        mu = mean(F(tr,:),1); sg = std(F(tr,:),0,1); sg(sg==0) = 1;
        m = fitcsvm((F(tr,:)-mu)./sg, y(tr), 'KernelFunction','linear');
        ok = ok + (predict(m, (F(i,:)-mu)./sg) == y(i));
    end
    a = ok/n; nerr = n - ok;
end

function d = cohend(a, b)
    na = numel(a); nb = numel(b);
    sp = sqrt(((na-1)*var(a) + (nb-1)*var(b)) / (na+nb-2));
    d  = (mean(a) - mean(b)) / sp;
end
