clc; clearvars; close all;
% Portrait placeholders for the yellow/white region-zoom photos.
% The user overwrites these with the real red-box zoom photos (same names).
outdirs = ["D:\project\Report\picture", "D:\project\Report_zh\picture"];
names = ["Real_white_zoom.png","Fake_white_zoom.png","Real_yellow_zoom.png","Fake_yellow_zoom.png"];
bg    = {[0.92 0.92 0.89],[0.92 0.92 0.89],[0.83 0.70 0.33],[0.83 0.70 0.33]};
lab   = ["Genuine white (replace)","Prop white (replace)","Genuine yellow (replace)","Prop yellow (replace)"];
for i = 1:4
    fig = figure("Position", [100 100 320 700], "Color", bg{i});
    ax = axes("Position", [0 0 1 1], "Color", bg{i}); axis(ax, [0 1 0 1]); axis off; hold on;
    rectangle("Position", [0.04 0.03 0.92 0.94], "EdgeColor", [0.90 0.15 0.15], "LineWidth", 4);
    text(0.5, 0.5, lab(i), "HorizontalAlignment", "center", "Rotation", 90, ...
        "FontSize", 13, "Color", [0.25 0.25 0.25]);
    for d = 1:numel(outdirs)
        exportgraphics(fig, fullfile(outdirs(d), names(i)), "Resolution", 120, "BackgroundColor", bg{i});
    end
    close(fig);
end
fprintf("4 zoom placeholders written to both picture folders.\n");
