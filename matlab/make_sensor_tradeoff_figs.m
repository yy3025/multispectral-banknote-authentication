clc; clearvars; close all;

% Regenerates the two "channels vs cost" / "channels vs power" panels of the
% sensor trade-off figure (report Fig 14) from the numbers in Table 1, so that
% they match the styling and the on-paper font size of every other figure in
% the report. The originals are external bitmaps whose internal text prints at
% about 3 pt.
%
% Outputs go to Result\result_sensor_tradeoff\ ONLY. To adopt them, copy
%   fig_channels_cost.png  -> Report\picture\a0000-img013.png
%   fig_channels_power.png -> Report\picture\22.png
% (and the same into Report_zh\picture) -- no LaTeX edit needed, the file
% names stay the same.

set(groot, "defaultAxesFontSize", 12);

outFolder = "D:\project\Result\result_sensor_tradeoff";
if ~exist(outFolder, "dir"), mkdir(outFolder); end

% --- Table 1 of the report ------------------------------------------------
sensor   = ["APDS-9250"; "OPT4048"; "AS7262"; "AS7341"; "AS7343"; "C12880MA"];
channels = [4;     4;     6;    11;    14;   288];
costGBP  = [2;     8;    21;    35;    55;   250];
powerMW  = [0.364; 0.096; 16.5; 0.378; 0.378; 100];

% The AS7341 is the device selected for the project: highlight it.
isPick   = sensor == "AS7341";
colOther = [0.00 0.45 0.74];
colPick  = [0.85 0.33 0.10];

% Label offsets (multiplicative, so they work on log axes). Labels sit to the
% right of their marker, except where two sensors share a value: the AS7341 and
% AS7343 have identical active power, so the AS7341 label is pushed below.
costOff  = repmat([1.12 1.00], 6, 1);
powerOff = repmat([1.12 1.00], 6, 1);
powerOff(4, :) = [1.12 0.55];   % AS7341: below its marker
powerOff(1, :) = [1.12 0.72];   % APDS-9250: clear of the AS7341/AS7343 row

plotPanel(channels, costGBP, sensor, isPick, colOther, colPick, costOff, ...
    "Approximate unit cost (GBP)", [2 5 10 20 50 100 250], ...
    "Spectral channels versus unit cost", ...
    fullfile(outFolder, "fig_channels_cost.png"));

plotPanel(channels, powerMW, sensor, isPick, colOther, colPick, powerOff, ...
    "Typical active power (mW)", [0.1 0.3 1 3 10 30 100], ...
    "Spectral channels versus active power", ...
    fullfile(outFolder, "fig_channels_power.png"));

fprintf("Sensor trade-off panels written to:\n%s\n", outFolder);

function plotPanel(x, y, names, isPick, colOther, colPick, off, yLab, yTk, ttl, outFile)
    % Narrow on purpose: these two panels are placed side by side at about
    % 0.46\linewidth each, so a smaller pixel width gives a larger font on
    % the printed page (see the note in banknotes.m).
    fig = figure("Position", [80 80 500 400]);
    hold on;
    scatter(x(~isPick), y(~isPick), 90, colOther, "filled");
    scatter(x( isPick), y( isPick), 150, colPick, "filled", "d");
    for i = 1:numel(x)
        text(x(i) * off(i, 1), y(i) * off(i, 2), " " + names(i), ...
            "FontSize", 11, "VerticalAlignment", "middle");
    end
    set(gca, "XScale", "log", "YScale", "log");
    xlim([3 700]);
    ylim([min(y) * 0.45, max(y) * 3.2]);
    xticks([4 10 20 50 100 300]);
    xticklabels(["4" "10" "20" "50" "100" "300"]);
    yticks(yTk);
    yticklabels(compose("%g", yTk));
    xlabel("Number of spectral channels");
    ylabel(yLab);
    title(ttl);
    grid on; box on;
    hold off;
    try
        exportgraphics(fig, outFile, "Resolution", 200);
    catch
        print(fig, char(erase(string(outFile), ".png")), "-dpng", "-r200");
    end
    close(fig);
end
