function S = loadNoteSet(folder)
% LOADNOTESET  Read every AS7341 CSV under `folder` (recursively) as one note.
%
% Shared by alignment_analysis.m and ageing_analysis.m so that the new
% experiments use exactly the same feature pipeline as banknotes.m:
% Corr F1-F8 and Corr NIR divided by Corr Clear, then SNV per spectrum.
%
% Returns a struct array with one element per CSV file:
%   S.name      file name without extension (= the banknote name)
%   S.file      full path
%   S.X         nRepeat x 9 SNV-normalized feature matrix
%   S.mean      1 x 9 note-mean spectrum
%   S.scatter   within-note scatter: sqrt(mean over channels of var over repeats)
%   S.repeats   number of valid rows
%
% Returns an empty struct array if the folder does not exist or holds no CSV.

    S = struct("name", {}, "file", {}, "X", {}, "mean", {}, ...
               "scatter", {}, "repeats", {});

    if ~isfolder(folder)
        return;
    end

    files = dir(fullfile(folder, "**", "*.csv"));
    if isempty(files)
        return;
    end

    names = string({files.name})';

    % Keep the photographic yellow/white campaigns to the same 20 + 30 notes
    % the direct campaign covered; no effect on any other dataset.
    keep  = pairedSubset(erase(names, ".csv"), folder);
    files = files(keep);
    names = names(keep);
    if isempty(files)
        return;
    end

    order = naturalOrder(erase(names, ".csv"));
    files = files(order);

    for i = 1:numel(files)
        fp = fullfile(files(i).folder, files(i).name);
        X  = readNormalized(fp);
        if isempty(X)
            warning("loadNoteSet: no valid rows in %s -- skipped.", fp);
            continue;
        end
        X = snvRows(X);

        S(end + 1).name = erase(string(files(i).name), ".csv");  %#ok<AGROW>
        S(end).file     = string(fp);
        S(end).X        = X;
        S(end).mean     = mean(X, 1, "omitnan");
        S(end).repeats  = size(X, 1);
        if size(X, 1) > 1
            S(end).scatter = sqrt(mean(var(X, 0, 1, "omitnan"), "omitnan"));
        else
            S(end).scatter = NaN;
        end
    end
end


function X = readNormalized(filePath)
% Same columns and same validity rule as banknotes.m/readAS7341Normalized.
    corrCols = [
        "Corr F1 (415nm)"
        "Corr F2 (445nm)"
        "Corr F3 (480nm)"
        "Corr F4 (515nm)"
        "Corr F5 (555nm)"
        "Corr F6 (590nm)"
        "Corr F7 (630nm)"
        "Corr F8 (680nm)"
        "Corr Clear"
        "Corr NIR"
    ];

    opts = detectImportOptions(filePath, "Delimiter", ";");
    opts.VariableNamingRule = "preserve";
    T = readtable(filePath, opts);

    have    = string(T.Properties.VariableNames);
    missing = setdiff(corrCols, have);
    if ~isempty(missing)
        error("loadNoteSet: %s is missing column(s): %s", ...
              filePath, strjoin(missing, ", "));
    end

    raw = table2array(T(:, corrCols));
    if isnumeric(raw)
        M = double(raw);
    else
        M = str2double(strrep(string(raw), ",", "."));
    end

    valid = ~all(isnan(M), 2) & M(:, 9) > 0;   % col 9 = Corr Clear
    M     = M(valid, :);
    if isempty(M)
        X = [];
        return;
    end

    F     = M(:, 1:8);
    Clear = M(:, 9);
    NIR   = M(:, 10);
    Clear(Clear == 0) = eps;
    X = [F ./ Clear, NIR ./ Clear];
end


function Xout = snvRows(Xin)
    m = mean(Xin, 2, "omitnan");
    s = std(Xin, 0, 2, "omitnan");
    s(s == 0) = eps;
    Xout = (Xin - m) ./ s;
end


function order = naturalOrder(names)
    names = names(:);
    num   = nan(numel(names), 1);
    for i = 1:numel(names)
        tok = regexp(names(i), '\d+', 'match');
        if ~isempty(tok), num(i) = str2double(tok(end)); end
    end
    [~, order] = sortrows([num, (1:numel(names))']);
end
