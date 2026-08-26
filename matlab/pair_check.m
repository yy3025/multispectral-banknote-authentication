function pair_check()
% PAIR_CHECK  Is direct note N the same physical banknote as photographed N?
%
% The user states that the 20 directly measured genuine notes are 20 of the
% 27 that were photographed. That makes a paired analysis possible, but only
% if the file numbering identifies which is which. This script tests the
% obvious hypothesis, direct realN == photo real (N), against the null that
% the pairing is arbitrary.
%
% Three tests, each with a permutation null over 10000 random pairings:
%   A. the hand-graded condition of note N (graded on the PHOTOGRAPHED set,
%      note_condition.csv) against the DIRECT within-note scatter of note N.
%      An independent label attached to the photo names; if the numbering is
%      right it should predict direct surface roughness.
%   B. direct scatter of note N against photographic scatter of note N.
%   C. direct mean spectrum of note N against photographic mean spectrum of
%      note N, as the mean over notes of the 9-channel correlation.
%
% Output: Result/result_pair_check/

clc; close all; rng(0);
root = fileparts(fileparts(mfilename('fullpath')));
outdir = fullfile(root, 'Result', 'result_pair_check');
if ~exist(outdir,'dir'); mkdir(outdir); end
logFile = fullfile(outdir,'pair_check_log.txt');
if exist(logFile,'file'); delete(logFile); end
diary(logFile); diary on;

nPerm = 10000;
regions = {'white','data_white_direct','data_white','white'
           'yellow','data_yellow_direct','data_yellow','yellow'};

grades = readtable(fullfile(root,'note_condition.csv'), 'VariableNamingRule','preserve');
grades.Note   = string(grades.Note);
grades.Region = string(grades.Region);

for r = 1:2
    tag = regions{r,1};
    fprintf('\n================ %s ================\n', regions{r,1});

    D = loadNoteSet(fullfile(root, regions{r,2}, 'Real'));
    P = loadNoteSet(fullfile(root, regions{r,3}, 'real'));
    nD = numel(D); nP = numel(P);
    fprintf('direct %d genuine notes, photographed %d\n', nD, nP);

    % index of each note from its file name
    idxD = noteIndex(string({D.name}));
    idxP = noteIndex(string({P.name}));
    fprintf('direct indices  %s\n', mat2str(sort(idxD)'));
    fprintf('photo  indices  %s\n', mat2str(sort(idxP)'));

    scD = vertcat(D.scatter);
    scP = vertcat(P.scatter);
    mD  = vertcat(D.mean);
    mP  = vertcat(P.mean);

    % map photo notes onto the direct indices
    [tf, loc] = ismember(idxD, idxP);
    if ~all(tf)
        fprintf('WARNING: %d direct indices have no photographic counterpart\n', sum(~tf));
    end
    keep = tf;
    scDk = scD(keep); scPk = scP(loc(keep));
    mDk  = mD(keep,:); mPk = mP(loc(keep),:);
    idxK = idxD(keep);
    n = numel(idxK);
    fprintf('%d notes paired by index\n', n);

    % ---- A. graded condition against DIRECT scatter ---------------------
    g = nan(n,1);
    for i = 1:n
        m = grades.Region == regions{r,4} & grades.Note == "Real"+string(idxK(i));
        if any(m); g(i) = grades.Condition(find(m,1)); end
    end
    ok = ~isnan(g);
    fprintf('\n--- A. hand grade (photo set) against DIRECT scatter, n = %d ---\n', sum(ok));
    if sum(ok) > 4
        rhoA = corr(g(ok), scDk(ok), 'type','Spearman');
        null = zeros(nPerm,1);
        gi = g(ok); si = scDk(ok);
        for k = 1:nPerm; null(k) = corr(gi(randperm(numel(gi))), si, 'type','Spearman'); end
        pA = mean(abs(null) >= abs(rhoA));
        fprintf('Spearman rho = %+.3f, permutation p = %.4f\n', rhoA, pA);
        fprintf('for reference, grade against PHOTO scatter on the same notes: rho = %+.3f\n', ...
                corr(g(ok), scPk(ok), 'type','Spearman'));
    end

    % ---- B. direct scatter against photographic scatter ------------------
    rhoB = corr(scDk, scPk, 'type','Spearman');
    null = zeros(nPerm,1);
    for k = 1:nPerm; null(k) = corr(scDk(randperm(n)), scPk, 'type','Spearman'); end
    fprintf('\n--- B. direct scatter against photo scatter ---\n');
    fprintf('Spearman rho = %+.3f, permutation p = %.4f\n', rhoB, mean(abs(null)>=abs(rhoB)));

    % ---- C. mean spectra --------------------------------------------------
    cs = zeros(n,1);
    for i = 1:n; cs(i) = corr(mDk(i,:)', mPk(i,:)'); end
    matched = mean(cs);
    null = zeros(nPerm,1);
    for k = 1:nPerm
        pm = randperm(n); v = zeros(n,1);
        for i = 1:n; v(i) = corr(mDk(i,:)', mPk(pm(i),:)'); end
        null(k) = mean(v);
    end
    fprintf('\n--- C. mean spectrum, direct against photo, same note ---\n');
    fprintf('mean per-note correlation, matched %+.3f, random pairing %+.3f (sd %.3f), p = %.4f\n', ...
            matched, mean(null), std(null), mean(abs(null - mean(null)) >= abs(matched - mean(null))));

    T = table(idxK(:), scDk, scPk, g, 'VariableNames', ...
              {'NoteIndex','ScatterDirect','ScatterPhoto','Grade'});
    writetable(T, fullfile(outdir, ['pair_' tag '.csv']));
end

fprintf('\nwritten to %s\n', outdir);
diary off;
end

function idx = noteIndex(names)
idx = nan(numel(names),1);
for i = 1:numel(names)
    tok = regexp(names(i), '\d+', 'match');
    if ~isempty(tok); idx(i) = str2double(tok{end}); end
end
end
