clc; clearvars; close all;

%% =========================
% Can the toy notes be aged ARTIFICIALLY, and does it defeat the classifier?
% (professor's feedback-6 question: scrumpling, water, solvents, sunlight)
%
% The security question is directional. Ageing a prop note is only a threat if
% it moves the note TOWARDS the genuine class. If it moves it further away, or
% sideways, the treatment makes the counterfeit easier to detect, not harder.
% This script measures the direction and the size of that movement, and whether
% any treated note crosses the decision boundary.
%
% EXPECTED DATA LAYOUT (one CSV per banknote, same format as everything else):
%
%   D:\project\data_aged\<region>\<stage>\CSV\<Treatment><n>.csv
%
%     <region>     yellow | white                 (read from photographs)
%                  direct_yellow | direct_white   (note held at the sensor)
%                  r20                            (supported, not used)
%     <stage>      before | after
%     <Treatment>  Scrumple | Water | Solvent | Sun   (any names; the leading
%                  letters of the file name are taken as the treatment label)
%
% Use SPARE prop notes that are NOT part of data_20/data_yellow/data_white, so
% the main dataset stays intact and the baseline classifier has never seen them.
% Record "before" and "after" for the SAME notes: the design is paired, which is
% what makes three notes per treatment informative at all.
%
% Reported per treatment:
%   1. does the deployed classifier still reject the note after ageing?
%   2. how far, and in which direction, did the decision score move?
%   3. did the note move towards or away from the genuine class centroid?
%   4. did the within-note scatter change (DIAGNOSTIC ONLY -- not the Chapter 7
%      cue and not reportable here; see the note at the plotting call)
%   5. which channels moved
% =========================

set(groot, "defaultAxesFontSize", 12);
rng(0);

agedRoot  = "D:\project\data_aged";
outFolder = "D:\project\Result\result_ageing";

% Recordings may be named either by treatment ("Sun1.csv") or by plain number
% ("1.csv"). For numbered files, map each range of numbers to its treatment.
% Set numericMap = {} to fall back to the leading letters of the file name.
numericMap = { 1:4,   "Sun"
               5:8,   "Water"
               9:12,  "Scrumple"
               13:16, "Control" };

% Region key -> baseline dataset the reference classifier is trained on, and
% the panel label. The two routes are kept as separate regions because each
% must be judged by the classifier of its OWN route: a note photographed on a
% screen and a note held in front of the sensor do not live in the same feature
% space, so scoring direct recordings against the photographic model would
% measure the route change, not the ageing.
% Order matters: it is the panel order of every figure. The two routes of one
% region sit next to each other so that each figure reads region by region.
regions = {
    "white",         "D:\project\data_white",         "Unprinted white area (photograph)"
    "direct_white",  "D:\project\data_white_direct",  "Unprinted white area (direct)"
    "yellow",        "D:\project\data_yellow",        "Uniform yellow patch (photograph)"
    "direct_yellow", "D:\project\data_yellow_direct", "Uniform yellow patch (direct)"
    "r20",           "D:\project\data_20",            "Digit-20 stroke (purple ink)"
};

channelLabels = ["F1 415nm", "F2 445nm", "F3 480nm", "F4 515nm", "F5 555nm", ...
                 "F6 590nm", "F7 630nm", "F8 680nm", "NIR"];
classList = ["Real", "Fake"];

if ~isfolder(agedRoot)
    printProtocol(agedRoot);
    return;
end
if ~exist(outFolder, "dir"), mkdir(outFolder); end

paired  = table();
deltaCh = table();
genuineRadius     = containers.Map("KeyType", "char", "ValueType", "double");
genuineRadiusMean = containers.Map("KeyType", "char", "ValueType", "double");
baseCache = struct("region", {}, "X", {}, "Y", {}, "Xafter", {}, "names", {});

for r = 1:size(regions, 1)
    regKey  = string(regions{r, 1});
    baseDir = string(regions{r, 2});
    regLab  = string(regions{r, 3});
    regDir  = fullfile(agedRoot, regKey);
    if ~isfolder(regDir), continue; end

    Sbefore = loadNoteSet(fullfile(regDir, "before"));
    Safter  = loadNoteSet(fullfile(regDir, "after"));
    if isempty(Sbefore) || isempty(Safter)
        fprintf("Region %s: need both a before/ and an after/ folder -- skipped.\n", regKey);
        continue;
    end

    % ---- baseline model: trained on the untreated dataset ----------------
    Sreal = loadNoteSet(fullfile(baseDir, "real"));
    Sfake = loadNoteSet(fullfile(baseDir, "fake"));
    if isempty(Sreal) || isempty(Sfake)
        warning("Baseline data not found for region %s at %s -- skipped.", regKey, baseDir);
        continue;
    end
    Xtr = [vertcat(Sreal.mean); vertcat(Sfake.mean)];
    Ytr = [repmat("Real", numel(Sreal), 1); repmat("Fake", numel(Sfake), 1)];
    Ntr = [string({Sreal.name})'; string({Sfake.name})'];

    % How far from the centre of the genuine class a genuine note is allowed to
    % sit. Computed leave-one-genuine-out so that no note helps to define the
    % centre it is measured against; the radius is therefore slightly larger
    % than an in-sample one, which makes the test in Section C conservative.
    Xreal = vertcat(Sreal.mean);
    nGen  = size(Xreal, 1);
    dGen  = zeros(nGen, 1);
    for q = 1:nGen
        dGen(q) = norm(Xreal(q, :) - mean(Xreal(setdiff(1:nGen, q), :), 1));
    end
    genuineRadius(char(regKey))     = max(dGen);   %#ok<SAGROW>
    genuineRadiusMean(char(regKey)) = mean(dGen);  %#ok<SAGROW>

    agedNames = string({Sbefore.name})';
    clash     = intersect(agedNames, Ntr);
    if ~isempty(clash)
        warning(['Aged note name(s) %s also exist in the baseline dataset for ' ...
                 'region %s. They are excluded from training, but consider ' ...
                 'renaming the aged files so the two sets stay clearly separate.'], ...
                strjoin(clash, ", "), regKey);
    end
    keep   = ~ismember(Ntr, agedNames);
    % Standardize matches the deployed model in banknotes.m -- without it this
    % would be testing a different classifier from the one the report deploys.
    mdlLin = fitcsvm(Xtr(keep, :), Ytr(keep), "KernelFunction", "linear", ...
                     "Standardize", true, "ClassNames", classList);
    % Section D re-tests the same notes Section A does: an "after" recording
    % whose "before" was never captured has no paired result, so counting it
    % here would report a different N from the rest of the script.
    afterAll  = string({Safter.name})';
    hasBefore = ismember(afterAll, string({Sbefore.name})');
    if any(~hasBefore)
        warning(['Region %s: note(s) %s were recorded after treatment but not ' ...
                 'before it. They carry no paired result and are dropped from ' ...
                 'every section of this analysis.'], ...
                regKey, strjoin(afterAll(~hasBefore), ", "));
    end
    baseCache(end + 1) = struct("region", regKey, "X", Xtr(keep, :), ...
        "Y", Ytr(keep), "Xafter", vertcat(Safter(hasBefore).mean), ...
        "names", afterAll(hasBefore));  %#ok<SAGROW>
    realCentroid = mean(Xtr(keep & Ytr == "Real", :), 1);
    fakeCentroid = mean(Xtr(keep & Ytr == "Fake", :), 1);

    fprintf("\n########## %s ##########\n", regLab);
    fprintf("Baseline training notes: %d (%d genuine / %d prop)\n", ...
            sum(keep), sum(keep & Ytr == "Real"), sum(keep & Ytr == "Fake"));

    % ---- pair before with after by note name -----------------------------
    afterNames = string({Safter.name})';
    for i = 1:numel(Sbefore)
        j = find(afterNames == Sbefore(i).name, 1);
        if isempty(j)
            warning("No 'after' recording for %s in region %s -- skipped.", ...
                    Sbefore(i).name, regKey);
            continue;
        end

        mB = Sbefore(i).mean;
        mA = Safter(j).mean;
        [pB, sB] = predict(mdlLin, mB);
        [pA, sA] = predict(mdlLin, mA);

        % score towards Fake: positive = correctly on the counterfeit side
        scoreB = sB(2);
        scoreA = sA(2);

        paired = [paired; table(regKey, regLab, Sbefore(i).name, ...
            treatmentOf(Sbefore(i).name, numericMap), ...
            Sbefore(i).repeats, Safter(j).repeats, ...
            string(pB), string(pA), scoreB, scoreA, scoreA - scoreB, ...
            norm(mA - mB), ...
            norm(mB - realCentroid), norm(mA - realCentroid), ...
            norm(mB - fakeCentroid), norm(mA - fakeCentroid), ...
            Sbefore(i).scatter, Safter(j).scatter, ...
            'VariableNames', {'Region', 'RegionLabel', 'Note', 'Treatment', ...
                              'RepeatsBefore', 'RepeatsAfter', ...
                              'PredBefore', 'PredAfter', ...
                              'ScoreBefore', 'ScoreAfter', 'ScoreChange', ...
                              'SpectralShift', ...
                              'DistToRealBefore', 'DistToRealAfter', ...
                              'DistToFakeBefore', 'DistToFakeAfter', ...
                              'ScatterBefore', 'ScatterAfter'})];  %#ok<AGROW>

        deltaCh = [deltaCh; [table(regKey, Sbefore(i).name, treatmentOf(Sbefore(i).name, numericMap), ...
                        'VariableNames', {'Region', 'Note', 'Treatment'}), ...
                   array2table(mA - mB, 'VariableNames', cellstr("d_" + channelLabels))]];  %#ok<AGROW>
    end
end

if isempty(paired)
    fprintf("\nNo paired before/after data found under %s\n", agedRoot);
    printProtocol(agedRoot);
    return;
end

% A region whose paired notes include no untreated control is dropped rather
% than reported. Section 0's drift floor is the only thing separating a
% treatment effect from session-to-session drift, so without it none of the
% numbers below can be interpreted; and because the controls are the last
% notes recorded, their absence is also what a half-finished recording
% session looks like from here.
for rr = unique(paired.Region, "stable")'
    m = paired.Region == rr;
    if ~any(paired.Treatment(m) == "Control")
        fprintf(['Region %s: %d paired note(s), none of them an untreated ' ...
                 'control -- skipped. Record Control notes in both sessions ' ...
                 '(or finish the session) before this region can be read.\n'], ...
                rr, sum(m));
        paired(m, :)  = [];
        deltaCh(deltaCh.Region == rr, :) = [];
        baseCache([baseCache.region] == rr) = [];
    end
end
if isempty(paired)
    fprintf("\nNo region left with a usable before/after pair.\n");
    return;
end

paired.MovedTowardsReal = paired.DistToRealAfter < paired.DistToRealBefore;
paired.StillRejected    = paired.PredAfter == "Fake";
isCtl = paired.Treatment == "Control";

%% ---- 0. session-drift control -------------------------------------------
% "before" and "after" are necessarily separate recording sessions, because the
% treatments take hours to days. Untreated control notes recorded in BOTH
% sessions are what separates a real treatment effect from session drift, which
% has already been shown to move this project's spectra on its own.
fprintf("\n===== 0. Session-drift check (untreated control notes) =====\n");
if ~any(isCtl)
    warning(['No control notes found. Name a few untreated notes Control1, ' ...
             'Control2, ... and record them in BOTH sessions alongside the ' ...
             'treated ones: without them no treatment effect below can be ' ...
             'separated from session-to-session drift.']);
else
    % Per region, never pooled: the drift floor is a property of one region's
    % recording session, and pooling can hide a region whose controls moved.
    for rr = unique(paired.Region, "stable")'
        m   = paired.Region == rr;
        cS  = mean(paired.SpectralShift(m &  isCtl));
        tS  = mean(paired.SpectralShift(m & ~isCtl));
        cSc = mean(paired.ScoreChange(m & isCtl));
        fprintf("[%s] controls n=%d: shift %.4f, mean score change %+.4f  <- drift floor\n", ...
                rr, sum(m & isCtl), cS, cSc);
        fprintf("[%s] treated  n=%d: shift %.4f  (%.1fx the drift floor)\n", ...
                rr, sum(m & ~isCtl), tS, tS / max(cS, eps));
        if tS < 2 * cS
            warning(['[%s] Treated notes moved less than twice as far as the ' ...
                     'untreated controls (%.4f vs %.4f). Session drift is ' ...
                     'comparable to the treatment effect in this region, so its ' ...
                     'results cannot be attributed to the treatments.'], rr, tS, cS);
        end
    end
end

%% ---- A. headline (treated notes only) ------------------------------------
trt = paired(~isCtl, :);
fprintf("\n===== A. Does ageing defeat the classifier? =====\n");
fprintf("Treated notes analysed         : %d\n", height(trt));
fprintf("Still classified as counterfeit: %d of %d\n", ...
        sum(trt.StillRejected), height(trt));
if any(~trt.StillRejected)
    fprintf("ACCEPTED AS GENUINE AFTER AGEING:\n");
    disp(trt(~trt.StillRejected, {'Region', 'Note', 'Treatment', ...
                                  'ScoreBefore', 'ScoreAfter'}));
end
fprintf("Moved towards the genuine class: %d of %d\n", ...
        sum(trt.MovedTowardsReal), height(trt));

% A note that the baseline model already got wrong BEFORE treatment was not
% defeated by the treatment, and must not be counted as if it were.
wrongBefore = trt.PredBefore == "Real";
flipped     = trt.PredBefore == "Fake" & trt.PredAfter == "Real";
fprintf("Already accepted BEFORE treatment (baseline error, not an ageing effect): %d\n", ...
        sum(wrongBefore));
fprintf("FLIPPED from rejected to accepted by the treatment: %d\n", sum(flipped));
if any(flipped)
    disp(trt(flipped, {'Region', 'Note', 'Treatment', 'ScoreBefore', 'ScoreAfter'}));
end

% Tested per region, never pooled: the two regions move in opposite directions,
% so a pooled test would average a real effect against its own reverse.
for rr = unique(trt.Region, "stable")'
    m = trt.Region == rr;
    if sum(m) >= 6
        fprintf("[%s] paired Wilcoxon, decision score before vs after : p = %.4g\n", ...
                rr, signrank(trt.ScoreBefore(m), trt.ScoreAfter(m)));
        fprintf("[%s] paired Wilcoxon, within-note scatter            : p = %.4g\n", ...
                rr, signrank(trt.ScatterBefore(m), trt.ScatterAfter(m)));
    end
end

%% ---- per-treatment summary ----------------------------------------------
summary = table();
[g, rg, tr] = findgroups(paired.Region, paired.Treatment);
for i = 1:max(g)
    m   = g == i;
    sub = paired(m, :);
    summary = [summary; table(rg(i), string(sub.RegionLabel(1)), tr(i), height(sub), ...
        sum(sub.StillRejected), ...
        mean(sub.ScoreBefore), mean(sub.ScoreAfter), mean(sub.ScoreChange), ...
        mean(sub.SpectralShift), ...
        mean(sub.DistToRealAfter - sub.DistToRealBefore), ...
        mean(sub.ScatterBefore), mean(sub.ScatterAfter), ...
        'VariableNames', {'Region', 'RegionLabel', 'Treatment', 'N', ...
                          'StillRejected', 'MeanScoreBefore', 'MeanScoreAfter', ...
                          'MeanScoreChange', 'MeanSpectralShift', ...
                          'MeanChangeDistToReal', ...
                          'MeanScatterBefore', 'MeanScatterAfter'})];  %#ok<AGROW>
end
summary = sortrows(summary, {'Region', 'Treatment'});

%% ---- C. crossing the boundary versus becoming genuine ---------------------
% A two-class boundary answers "which side is this note on", which is not the
% same question as "is this note genuine". A treated note can cross the
% boundary by moving into the empty space between the classes without ever
% resembling a genuine note. This section separates the two: it compares each
% treated note's distance from the genuine class centre against the largest
% distance any genuine note reaches (leave-one-genuine-out), and asks whether
% the notes the SVM accepts also fall inside that radius.
fprintf("\n===== C. Did the aged notes become genuine, or only cross the boundary? =====\n");
radiusTab = table();
for rr = unique(paired.Region, "stable")'
    m   = paired.Region == rr;
    thr = genuineRadius(char(rr));
    sub = paired(m & ~isCtl, :);

    accepted = ~sub.StillRejected;
    inside   = sub.DistToRealAfter <= thr;

    fprintf("[%s] genuine notes reach %.3f from their class centre (mean %.3f)\n", ...
            rr, thr, genuineRadiusMean(char(rr)));
    fprintf("[%s] treated notes: %.3f before -> %.3f after (closest after: %.3f = %.1fx the radius)\n", ...
            rr, mean(sub.DistToRealBefore), mean(sub.DistToRealAfter), ...
            min(sub.DistToRealAfter), min(sub.DistToRealAfter) / thr);
    fprintf("[%s] accepted by the SVM: %d of %d;  of those, inside the genuine radius: %d\n", ...
            rr, sum(accepted), height(sub), sum(accepted & inside));

    radiusTab = [radiusTab; table(rr, thr, genuineRadiusMean(char(rr)), ...
        mean(sub.DistToRealBefore), mean(sub.DistToRealAfter), ...
        min(sub.DistToRealAfter), min(sub.DistToRealAfter) / thr, ...
        sum(accepted), sum(accepted & inside), ...
        'VariableNames', {'Region', 'GenuineRadius', 'GenuineRadiusMean', ...
                          'MeanDistBefore', 'MeanDistAfter', 'ClosestAfter', ...
                          'ClosestAsRadiusMultiple', 'AcceptedBySVM', ...
                          'AcceptedAndInsideRadius'})];  %#ok<AGROW>
end
fprintf(['\nNote: the radius is calibrated on the genuine notes themselves, so it\n' ...
         'rejects none of them by construction. What is measurable is the gap\n' ...
         'between it and the closest treated note.\n']);

%% ---- D. would dropping the attacked channels fix it? ----------------------
% The obvious repair for a fragile feature is to stop using it. This checks
% whether that works, by retraining the same linear SVM on reduced channel
% subsets and re-testing the treated notes. Baseline leave-one-out accuracy is
% reported alongside, because a subset that rejects everything is not a fix.
featureSets = { "all 9 channels",              1:9
                "without F2 (445 nm)",         [1 3:9]
                "without F1-F3 (blue/violet)", 4:9
                "F6-F8 + NIR (long wave)",     6:9
                "NIR only",                    9 };
subsetTab = table();
fprintf("\n===== D. Does dropping the attacked channels restore rejection? =====\n");
for c = 1:numel(baseCache)
    B = baseCache(c);
    treatedRows = ~startsWith(B.names, "Control") & ...
                  arrayfun(@(nm) treatmentOf(nm, numericMap) ~= "Control", B.names);
    fprintf("\n[%s]  (%d treated notes)\n", B.region, sum(treatedRows));
    fprintf("  %-28s %10s  %10s\n", "feature set", "baseline LOO", "rejected");
    for s = 1:size(featureSets, 1)
        cols = featureSets{s, 2};
        mdl  = fitcsvm(B.X(:, cols), B.Y, "KernelFunction", "linear", ...
                       "Standardize", true, "ClassNames", classList);
        acc  = 1 - kfoldLoss(crossval(mdl, "Leaveout", "on"));
        pa   = predict(mdl, B.Xafter(treatedRows, cols));
        fprintf("  %-28s %9.1f%%  %6d/%d\n", featureSets{s,1}, 100*acc, ...
                sum(pa == "Fake"), numel(pa));
        subsetTab = [subsetTab; table(B.region, string(featureSets{s,1}), ...
            numel(cols), 100*acc, sum(pa == "Fake"), numel(pa), ...
            'VariableNames', {'Region', 'FeatureSet', 'NFeatures', ...
                              'BaselineLOOPct', 'RejectedAfter', 'NTreated'})];  %#ok<AGROW>
    end
end

%% ---- E. the same notes, both routes ---------------------------------------
% The aged notes carry the same numbering on both routes: photographic note 3
% and direct note 3 are the same piece of paper, treated once. The two routes
% can therefore be compared note by note rather than as two group averages,
% which is what makes "the attack works on photographs but not on the note
% itself" a statement about the measurement route and not about which notes
% happened to end up in which group.
%
% The decision scores of the two routes are not on a common scale -- they come
% from two different SVMs -- so the movement towards the genuine class is also
% expressed in units of each route's own genuine radius, which is.
routePairs = { "white",  "Unprinted white area"
               "yellow", "Uniform yellow patch" };
routeTab = table();
fprintf("\n===== E. The same notes, measured both ways =====\n");
for q = 1:size(routePairs, 1)
    area   = string(routePairs{q, 1});
    photoK = area;
    dirK   = "direct_" + area;
    if ~all(ismember([photoK, dirK], paired.Region))
        fprintf("[%s] needs both the photographic and the direct recordings.\n", area);
        continue;
    end
    Pp = paired(paired.Region == photoK, :);
    Pd = paired(paired.Region == dirK, :);
    [common, ip, id] = intersect(Pp.Note, Pd.Note, "stable");
    rp = genuineRadius(char(photoK));
    rd = genuineRadius(char(dirK));

    sub = table(repmat(area, numel(common), 1), common, Pp.Treatment(ip), ...
        Pp.ScoreChange(ip), Pd.ScoreChange(id), ...
        (Pp.DistToRealAfter(ip) - Pp.DistToRealBefore(ip)) / rp, ...
        (Pd.DistToRealAfter(id) - Pd.DistToRealBefore(id)) / rd, ...
        Pp.PredBefore(ip) == "Fake" & Pp.PredAfter(ip) == "Real", ...
        Pd.PredBefore(id) == "Fake" & Pd.PredAfter(id) == "Real", ...
        Pp.ScatterAfter(ip) - Pp.ScatterBefore(ip), ...
        Pd.ScatterAfter(id) - Pd.ScatterBefore(id), ...
        'VariableNames', {'Area', 'Note', 'Treatment', ...
                          'ScoreChangePhoto', 'ScoreChangeDirect', ...
                          'DistChangePhotoRadii', 'DistChangeDirectRadii', ...
                          'FlippedPhoto', 'FlippedDirect', ...
                          'ScatterChangePhoto', 'ScatterChangeDirect'});
    routeTab = [routeTab; sub];  %#ok<AGROW>

    T = sub(sub.Treatment ~= "Control", :);
    fprintf("\n[%s]  %d treated, %d control notes on both routes\n", ...
            string(routePairs{q, 2}), height(T), height(sub) - height(T));
    if height(T) >= 4
        [rho1, p1] = corr(T.ScoreChangePhoto, T.ScoreChangeDirect, "type", "Spearman");
        [rho2, p2] = corr(T.DistChangePhotoRadii, T.DistChangeDirectRadii, ...
                          "type", "Spearman");
        fprintf("  change in decision score, photo vs direct : rho = %+.2f (p = %.3g)\n", ...
                rho1, p1);
        fprintf("  movement towards the genuine class        : rho = %+.2f (p = %.3g)\n", ...
                rho2, p2);
        fprintf("  moved the same way on both routes         : %d of %d\n", ...
                sum(sign(T.ScoreChangePhoto) == sign(T.ScoreChangeDirect)), height(T));
    end
    fprintf("  flipped on the photographs: %d;  the same notes read directly: %d\n", ...
            sum(T.FlippedPhoto), sum(T.FlippedPhoto & T.FlippedDirect));
    fprintf("  mean move towards the genuine class, in each route's own radii:\n");
    fprintf("    photograph %+.2f   direct %+.2f\n", ...
            mean(T.DistChangePhotoRadii), mean(T.DistChangeDirectRadii));
end
if ~isempty(routeTab)
    disp(routeTab);
end

fprintf("\n===== B. Effect of each treatment =====\n");
fprintf("(MeanChangeDistToReal < 0 means the treatment moved the prop note\n");
fprintf(" TOWARDS the genuine class; > 0 means further away.)\n\n");
disp(summary);

%% ---- outputs -------------------------------------------------------------
writetable(paired,    fullfile(outFolder, "ageing_paired.csv"));
writetable(summary,   fullfile(outFolder, "ageing_summary.csv"));
writetable(deltaCh,   fullfile(outFolder, "ageing_channel_shift.csv"));
writetable(radiusTab, fullfile(outFolder, "ageing_genuine_radius.csv"));
writetable(subsetTab, fullfile(outFolder, "ageing_feature_subsets.csv"));
if ~isempty(routeTab)
    writetable(routeTab, fullfile(outFolder, "ageing_route_pairs.csv"));
end

wb = fullfile(outFolder, "ageing_analysis.xlsx");
if isfile(wb), delete(wb); end
writetable(summary,   wb, "Sheet", "Summary");
writetable(paired,    wb, "Sheet", "Paired");
writetable(deltaCh,   wb, "Sheet", "ChannelShift");
writetable(radiusTab, wb, "Sheet", "GenuineRadius");
writetable(subsetTab, wb, "Sheet", "FeatureSubsets");
if ~isempty(routeTab)
    writetable(routeTab, wb, "Sheet", "RoutePairs");
    plotRoutePair(routeTab, fullfile(outFolder, "fig_aged_routes.png"));
end

plotScoreShift(paired, fullfile(outFolder, "fig_aged_score.png"));
% DO NOT REPORT THE SCATTER OF THESE NOTES (user, 2026-08-22). The ageing
% recordings take fewer readings per note than the main campaign and do not
% step the sampled position across the region the way sec:placement requires,
% so this spread is not the within-note scatter of Chapter 7 and cannot be
% compared with it or with sec:condition-effect. The figure and the columns
% are kept as a diagnostic of the recording session only.
plotPairedMeasure(paired, "ScatterBefore", "ScatterAfter", ...
    "Within-note scatter", "Print-texture cue before and after ageing", ...
    fullfile(outFolder, "fig_aged_scatter.png"));
plotChannelShift(deltaCh, channelLabels, fullfile(outFolder, "fig_aged_channels.png"));

fprintf("\nAgeing analysis saved to:\n%s\n", outFolder);


%% ======================= local functions ================================

function t = treatmentOf(noteName, numericMap)
% Treatment label from the file name: the leading letters when the name has
% them ("Sun1" -> "Sun"), otherwise a lookup of the number in numericMap.
    nm  = string(noteName);
    tok = regexp(nm, '^[A-Za-z_]+', 'match', 'once');
    if strlength(tok) > 0
        t = string(tok);
        return;
    end
    n = str2double(regexp(nm, '\d+', 'match', 'once'));
    t = "Unknown";
    if ~isnan(n) && ~isempty(numericMap)
        for r = 1:size(numericMap, 1)
            if ismember(n, numericMap{r, 1})
                t = string(numericMap{r, 2});
                return;
            end
        end
    end
end


function plotScoreShift(paired, outPath)
% The key figure: where each treated note sat before and after ageing,
% relative to the decision boundary at zero. One panel per region, side by
% side, so the figure stays wide and short enough to print legibly at
% \linewidth instead of filling a whole page.
    % Panels follow the order the regions were analysed in, not alphabetical
    % order, so that this figure and fig_aged_channels place the same region
    % in the same position.
    regions = unique(paired.Region, "stable");
    P       = sortrows(paired, {'Treatment', 'Note'});
    nRegion = numel(regions);
    rowsMax = max(arrayfun(@(r) sum(P.Region == r), regions));

    treatments = unique(P.Treatment, "stable");
    cmap = lines(max(numel(treatments), 3));

    % shared x-range so the two panels are directly comparable
    lo  = min([P.ScoreBefore; P.ScoreAfter; 0]);
    hi  = max([P.ScoreBefore; P.ScoreAfter; 0]);
    pad = 0.08 * max(hi - lo, eps);

    % Beyond three regions a single row is too wide to print at \linewidth
    % without shrinking the axes into a strip, so the panels wrap.
    nCol = min(nRegion, 3);
    if nRegion == 4, nCol = 2; end
    nRow = ceil(nRegion / nCol);
    fig = figure("Color", "w", ...
                 "Position", [80 80 max(1000, 380 * nCol), ...
                              nRow * max(380, 90 + 24 * rowsMax)]);
    tl  = tiledlayout(fig, nRow, nCol, "TileSpacing", "compact", "Padding", "compact");

    for r = 1:nRegion
        Q  = P(P.Region == regions(r), :);
        n  = height(Q);
        ax = nexttile(tl); hold(ax, "on"); grid(ax, "on");
        xline(ax, 0, "k--", "LineWidth", 1.4, "HandleVisibility", "off");

        for i = 1:n
            ci = find(treatments == Q.Treatment(i), 1);
            plot(ax, [Q.ScoreBefore(i) Q.ScoreAfter(i)], [i i], "-", ...
                 "Color", [cmap(ci, :) 0.65], "LineWidth", 1.8, ...
                 "HandleVisibility", "off");
            plot(ax, Q.ScoreBefore(i), i, "o", "MarkerSize", 7, ...
                 "MarkerEdgeColor", cmap(ci, :), "MarkerFaceColor", "w", ...
                 "LineWidth", 1.4, "HandleVisibility", "off");
            plot(ax, Q.ScoreAfter(i), i, "o", "MarkerSize", 7, ...
                 "MarkerEdgeColor", cmap(ci, :), "MarkerFaceColor", cmap(ci, :), ...
                 "HandleVisibility", "off");
        end
        if r == nRegion                   % legend proxies once only
            for k = 1:numel(treatments)
                plot(ax, NaN, NaN, "o-", "Color", cmap(k, :), ...
                     "MarkerFaceColor", cmap(k, :), "LineWidth", 1.8, ...
                     "DisplayName", treatments(k));
            end
            legend(ax, "Location", "southeast");
        end

        yticks(ax, 1:n);
        yticklabels(ax, "note " + Q.Note);
        ylim(ax, [0.5, n + 0.5]);
        xlim(ax, [lo - pad, hi + pad]);
        title(ax, string(Q.RegionLabel(1)));
        ax.Toolbar.Visible = "off";
    end

    xlabel(tl, "SVM score towards the counterfeit class  (0 = decision boundary)", ...
           "FontSize", 12);
    title(tl, "Effect of artificial ageing: hollow = before, filled = after", ...
          "FontSize", 13, "FontWeight", "bold");
    exportgraphics(fig, outPath, "Resolution", 200);
    close(fig);
end


function plotPairedMeasure(paired, varBefore, varAfter, ylab, ttl, outPath)
    P = sortrows(paired, {'Region', 'Treatment', 'Note'});
    n = height(P);
    if n == 0, return; end

    fig = figure("Color", "w", "Position", [80 80 700 460]);
    ax  = axes(fig); hold(ax, "on"); grid(ax, "on");
    for i = 1:n
        plot(ax, [1 2], [P.(varBefore)(i) P.(varAfter)(i)], "-o", ...
             "Color", [0.5 0.5 0.5 0.7], "MarkerFaceColor", "w", ...
             "MarkerSize", 6, "HandleVisibility", "off");
    end
    plot(ax, [1 2], [mean(P.(varBefore)) mean(P.(varAfter))], "-s", ...
         "Color", [0.85 0.33 0.10], "LineWidth", 2.4, "MarkerSize", 10, ...
         "MarkerFaceColor", [0.85 0.33 0.10], "DisplayName", "mean");
    xlim(ax, [0.7 2.3]);
    xticks(ax, [1 2]); xticklabels(ax, ["before ageing", "after ageing"]);
    ylabel(ax, ylab); title(ax, ttl);
    legend(ax, "Location", "northwest");
    ax.Toolbar.Visible = "off";
    exportgraphics(fig, outPath, "Resolution", 200);
    close(fig);
end


function plotChannelShift(deltaCh, channelLabels, outPath)
% One panel per region. Pooling the regions would average two different
% physical effects together and hide the channel each treatment actually
% attacks, which is the whole point of the figure.
    if isempty(deltaCh), return; end
    treatments = unique(deltaCh.Treatment, "stable");
    regions    = unique(deltaCh.Region, "stable");
    nRegion    = numel(regions);

    D = nan(numel(treatments), numel(channelLabels), nRegion);
    for r = 1:nRegion
        for k = 1:numel(treatments)
            m = deltaCh.Region == regions(r) & deltaCh.Treatment == treatments(k);
            if any(m)
                D(k, :, r) = mean(table2array(deltaCh(m, 4:end)), 1, "omitnan");
            end
        end
    end

    lo  = min([D(:); 0]); hi = max([D(:); 0]);
    pad = 0.10 * max(hi - lo, eps);

    nCol = min(nRegion, 3);
    if nRegion == 4, nCol = 2; end
    nRow = ceil(nRegion / nCol);
    fig = figure("Color", "w", ...
                 "Position", [80 80 max(1000, 430 * nCol) 420 * nRow]);
    tl  = tiledlayout(fig, nRow, nCol, "TileSpacing", "compact", "Padding", "compact");

    for r = 1:nRegion
        ax = nexttile(tl);
        b  = bar(ax, D(:, :, r)', "grouped");
        for k = 1:numel(b), b(k).DisplayName = treatments(k); end
        grid(ax, "on");
        xticks(ax, 1:numel(channelLabels));
        xticklabels(ax, channelLabels);
        xtickangle(ax, 45);
        ylim(ax, [lo - pad, hi + pad]);
        title(ax, regionLabelOf(deltaCh, regions(r)));
        if mod(r - 1, nCol) == 0
            ylabel(ax, "Mean change in SNV feature (after - before)");
        end
        if r == nCol
            legend(ax, "Location", "northoutside", "Orientation", "horizontal");
        end
        ax.Toolbar.Visible = "off";
    end
    title(tl, "Which channels artificial ageing moves", ...
          "FontSize", 13, "FontWeight", "bold");
    exportgraphics(fig, outPath, "Resolution", 200);
    close(fig);
end


function plotRoutePair(routeTab, outPath)
% Each marker is one banknote, plotted by what the SAME note did on the two
% measurement routes. A note in the lower-left quadrant moved towards the
% genuine class both ways; a note on the vertical zero line moved on the
% photographs and nowhere on the note itself.
    treatments = unique(routeTab.Treatment, "stable");
    cmap = lines(max(numel(treatments), 3));

    panels = { "ScoreChangePhoto", "ScoreChangeDirect", ...
               "Change in SVM score towards the counterfeit class", ...
               "Decision score"
               "DistChangePhotoRadii", "DistChangeDirectRadii", ...
               "Change in distance to the genuine class (genuine radii)", ...
               "Distance to the genuine class" };

    areas  = unique(routeTab.Area, "stable");
    nArea  = numel(areas);
    fig = figure("Color", "w", "Position", [80 80 980 max(460, 430 * nArea)]);
    tl  = tiledlayout(fig, nArea, 2, "TileSpacing", "compact", "Padding", "compact");

    for a = 1:nArea
    R = routeTab(routeTab.Area == areas(a), :);
    for p = 1:size(panels, 1)
        xv = R.(panels{p, 1});
        yv = R.(panels{p, 2});
        ax = nexttile(tl); hold(ax, "on"); grid(ax, "on");

        lo = min([xv; yv]); hi = max([xv; yv]);
        pad = 0.12 * max(hi - lo, eps);
        lim = [lo - pad, hi + pad];
        plot(ax, lim, lim, "-", "Color", [0.75 0.75 0.75], "HandleVisibility", "off");
        xline(ax, 0, "k--", "HandleVisibility", "off");
        yline(ax, 0, "k--", "HandleVisibility", "off");

        for i = 1:height(R)
            ci = find(treatments == R.Treatment(i), 1);
            plot(ax, xv(i), yv(i), "o", "MarkerSize", 8, ...
                 "MarkerEdgeColor", cmap(ci, :), "MarkerFaceColor", cmap(ci, :), ...
                 "HandleVisibility", "off");
            text(ax, xv(i), yv(i), "  " + R.Note(i), "FontSize", 9, ...
                 "Color", [0.25 0.25 0.25]);
        end
        if p == 2 && a == 1
            for k = 1:numel(treatments)
                plot(ax, NaN, NaN, "o", "Color", cmap(k, :), ...
                     "MarkerFaceColor", cmap(k, :), "DisplayName", treatments(k));
            end
            legend(ax, "Location", "northwest");
        end
        axis(ax, "square");
        xlim(ax, lim); ylim(ax, lim);
        xlabel(ax, "photograph");
        ylabel(ax, "direct");
        title(ax, areaLabelOf(areas(a)) + ": " + panels{p, 4});
        subtitle(ax, panels{p, 3}, "FontSize", 9);
        ax.Toolbar.Visible = "off";
    end
    end

    title(tl, "The same aged notes, measured both ways", ...
          "FontSize", 13, "FontWeight", "bold");
    exportgraphics(fig, outPath, "Resolution", 200);
    close(fig);
end


function lab = areaLabelOf(area)
% The region name without a route: Section E's panels hold both routes.
    switch string(area)
        case "white",  lab = "Unprinted white area";
        case "yellow", lab = "Uniform yellow patch";
        otherwise,     lab = string(area);
    end
end


function lab = regionLabelOf(deltaCh, regKey)
    switch string(regKey)
        case "yellow",        lab = "Uniform yellow patch (photograph)";
        case "white",         lab = "Unprinted white area (photograph)";
        case "direct_yellow", lab = "Uniform yellow patch (direct)";
        case "direct_white",  lab = "Unprinted white area (direct)";
        case "r20",           lab = "Digit-20 stroke (purple ink)";
        otherwise,            lab = string(regKey);
    end
end


function printProtocol(agedRoot)
    fprintf("\nNo ageing data yet. Expected layout:\n\n");
    fprintf("  %s\\<region>\\<stage>\\CSV\\<Treatment><n>.csv\n\n", agedRoot);
    fprintf("  <region>     yellow | white | direct_yellow | direct_white\n");
    fprintf("  <stage>      before | after\n");
    fprintf("  <Treatment>  Sun | Scrumple | Water | Solvent | Control\n\n");
    fprintf("Use SPARE prop notes that are not in data_yellow/data_white, and record\n");
    fprintf("before/after for the SAME notes. Include several UNTREATED notes named\n");
    fprintf("Control1, Control2, ... measured in both sessions -- they are the only\n");
    fprintf("way to tell a treatment effect from session drift. See EXPERIMENT_PROTOCOL.md.\n");
end
