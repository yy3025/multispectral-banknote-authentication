function scatter_figs()
% SCATTER_FIGS  Redraw the condition figures for the two UNIFORM regions only.
%
% condition_analysis.m draws three panels, one per region, including the
% digit-20 stroke. The digit stroke now lives in an appendix, so the body
% needs the same figures with the two uniform regions alone. This reads the
% per-note table condition_analysis.m already wrote rather than recomputing,
% so the numbers are identical to those in Result/result_condition/.
%
% Output: Result/result_scatter_direct/fig_condition_margin_uniform.png

root = fileparts(fileparts(mfilename('fullpath')));
src  = fullfile(root, 'Result', 'result_condition', 'condition_per_note.csv');
out  = fullfile(root, 'Result', 'result_scatter_direct');
if ~exist(out, 'dir'); mkdir(out); end

T = readtable(src, 'VariableNamingRule', 'preserve');
T.Region = string(T.Region);
T.Class  = string(T.Class);

CB = [0 0.4470 0.7410];
CO = [0.8500 0.3250 0.0980];
regs = {'yellow', 'Uniform yellow patch'; 'white', 'Unprinted white area'};

f = figure('Visible', 'off', 'Position', [60 60 800 400]);
tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
for r = 1:2
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    m0 = T.Region == regs{r,1};
    g  = m0 & T.Class == "Real";
    p  = m0 & T.Class ~= "Real";
    scatter(ax, T.ScatterMatched(g), T.Margin(g), 46, CB, 'filled', 'MarkerFaceAlpha', 0.75);
    scatter(ax, T.ScatterMatched(p), T.Margin(p), 46, CO, 'filled', 'MarkerFaceAlpha', 0.75);
    rho = corr(T.ScatterMatched(m0), T.Margin(m0), 'type', 'Spearman');
    title(ax, {regs{r,2}, sprintf('pooled \\rho = %.2f', rho)}, 'FontSize', 10);
    xlabel(ax, 'Repeat-matched within-note scatter', 'FontSize', 9);
    if r == 1
        ylabel(ax, 'Margin towards true class', 'FontSize', 9);
        legend(ax, {'Genuine', 'Counterfeit'}, 'Location', 'southwest', 'FontSize', 8);
    end
    hold(ax, 'off');
end
p = fullfile(out, 'fig_condition_margin_uniform.png');
exportgraphics(f, p, 'Resolution', 220);
I = imread(p); [h, w, c] = size(I); m = 24;
J = uint8(255 * ones(h + 2*m, w + 2*m, c, 'uint8'));
J(m+1:m+h, m+1:m+w, :) = I;
imwrite(J, p);
close(f);
fprintf('written %s\n', p);
end
