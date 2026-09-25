% 根据当前 Baseline_Results.mat 中的 Original-3 LS-ANS 结果重新绘图
load('Baseline_Results.mat', 'cluster_data_list', 'all_solutions', 'all_quantities', 'p_base', 'c_base', 'Q_base');

k = 3; % Original-3
data = cluster_data_list{k};
sol = all_solutions{k}.LS_ANS;
qty_struct = all_quantities{k}.LS_ANS;
label = 'Original-3';
p = p_base; c = c_base; Q = Q_base;

JWD = data.JWD; n_s = data.n_stations; n_v = data.n_vehicles; qidian = data.qidian;

routes = cell(n_v, 1); visited = [];
if n_v == 1
    routes{1} = sol;
    if ~isempty(sol), visited = unique(sol); end
else
    z = find(sol == 0); start = 1;
    for v = 1:n_v
        if v <= length(z)
            routes{v} = sol(start:z(v)-1); start = z(v) + 1;
        else
            routes{v} = sol(start:end);
        end
        if ~isempty(routes{v}), visited = union(visited, routes{v}); end
    end
end
visited = union(visited, qidian(:)');

station_qty = zeros(n_s, 1);
if isstruct(qty_struct)
    fnames = fieldnames(qty_struct);
    for f = 1:length(fnames)
        det = qty_struct.(fnames{f});
        if isfield(det, 'stations') && isfield(det, 'quantities')
            for i = 1:length(det.stations)
                s = det.stations(i);
                if s <= n_s, station_qty(s) = station_qty(s) + det.quantities(i); end
            end
        end
    end
end

lat0 = mean(JWD(:,2)); dx = max(JWD(:,1)) - min(JWD(:,1)); dy = max(JWD(:,2)) - min(JWD(:,2));
aspect = max(min((dx * cosd(lat0)) / max(dy, eps), 3.0), 0.3);
fig_h = max(14, sqrt(n_s) * 2.4);
fig_w = max(min(fig_h * aspect * 1.15 + 2.0*(n_v>1), 22.0), 12.0);

fig = figure('Color', 'w', 'Visible', 'off');
set(fig, 'Units', 'inches', 'Position', [1, 1, fig_w, fig_h]);
set(fig, 'PaperUnits', 'inches', 'PaperPosition', [0, 0, fig_w, fig_h]);
hold on;

c_vis = [0.35 0.60 0.78]; c_unvis = [0.78 0.76 0.74]; c_dep = [0.12 0.12 0.14];
c_pick = [0.90 0.25 0.25]; c_drop = [0.15 0.70 0.40]; c_txt = [0.15 0.15 0.18];
c_grid = [0.88 0.88 0.88];
pal = [0.72 0.32 0.32; 0.28 0.52 0.72; 0.42 0.68 0.32; 0.78 0.58 0.22; 0.58 0.38 0.72];

for i = 1:n_s
    if ismember(i, visited) && ~ismember(i, qidian)
        scatter(JWD(i,1), JWD(i,2), 240, c_vis, 'filled', 'MarkerEdgeColor', c_dep, 'LineWidth', 1.0);
    elseif ~ismember(i, visited)
        scatter(JWD(i,1), JWD(i,2), 150, c_unvis, 'filled', 'MarkerEdgeColor', [0.60 0.60 0.58], 'LineWidth', 0.7);
    end
end

for v = 1:n_v
    r = routes{v}; if isempty(r), continue; end
    col = pal(mod(v-1, size(pal,1)) + 1, :);
    path = [qidian(v); r(:); qidian(v)];
    for i = 1:length(path)-1
        plot(JWD([path(i), path(i+1)], 1), JWD([path(i), path(i+1)], 2), '-', 'Color', col, 'LineWidth', 2.2);
    end
end

for v = 1:n_v
    scatter(JWD(qidian(v),1), JWD(qidian(v),2), 550, c_dep, 'p', 'filled', 'MarkerEdgeColor', c_dep, 'LineWidth', 2.0);
end

if n_s <= 15, off_id = dy*0.050; off_q = dy*0.060; fs_id = 14; fs_q = 13;
elseif n_s <= 35, off_id = dy*0.040; off_q = dy*0.048; fs_id = 12; fs_q = 11;
elseif n_s <= 60, off_id = dy*0.030; off_q = dy*0.038; fs_id = 10; fs_q = 9;
else, off_id = dy*0.022; off_q = dy*0.030; fs_id = 9; fs_q = 8; end

for i = 1:n_s
    if ismember(i, qidian) || ismember(i, visited)
        text(JWD(i,1), JWD(i,2) + off_id, sprintf('%d', i), 'FontSize', fs_id, ...
            'FontWeight', 'bold', 'Color', c_txt, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
        qv = station_qty(i);
        if abs(qv) > 0.01
            if qv > 0, qs = sprintf('+%.2f', qv); qc = c_drop; else, qs = sprintf('%.2f', qv); qc = c_pick; end
            text(JWD(i,1), JWD(i,2) - off_q, qs, 'FontSize', fs_q, ...
                'FontWeight', 'bold', 'Color', qc, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
        end
    end
end

xlabel('Longitude', 'FontSize', 14, 'FontName', 'Arial', 'Color', c_txt, 'Interpreter', 'latex');
ylabel('Latitude', 'FontSize', 14, 'FontName', 'Arial', 'Color', c_txt, 'Interpreter', 'latex');
title(sprintf('%s: LS-ANS Route (current results, $p$=%.0f, $\\kappa$=%.1f, $Q$=%d)', label, p, c, Q), ...
    'FontSize', 17, 'FontName', 'Arial', 'Color', c_txt, 'Interpreter', 'latex');

daspect([1/cosd(lat0), 1, 1]); grid on; box off;
ax = gca; ax.GridColor = c_grid; ax.GridAlpha = 0.5; ax.LineWidth = 0.5;
ax.FontName = 'Arial'; ax.FontSize = 11; ax.XColor = c_txt; ax.YColor = c_txt;
axis tight;
margin = max(dx, dy) * 0.28;
xlim([min(JWD(:,1))-margin, max(JWD(:,1))+margin]);
ylim([min(JWD(:,2))-margin, max(JWD(:,2))+margin]);

if n_v > 1
    lgd = legend(arrayfun(@(v) sprintf('Vehicle %d', v), 1:n_v, 'UniformOutput', false), ...
        'Location', 'eastoutside', 'FontSize', 10, 'Box', 'off');
    lgd.Color = [1 1 1];
end

print(fig, 'Route_Visualization_Original_3_LS_ANS_Current.png', '-dpng', '-r400');
close(fig);

fprintf('Saved Route_Visualization_Original_3_LS_ANS_Current.png\n');
fprintf('Route order: '); disp([qidian(1), sol, qidian(1)]);
fprintf('Sum of quantities: %.6f\n', sum(station_qty));
