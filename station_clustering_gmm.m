% GMM spatial clustering and statistical preprocessing for high-risk stations
% Pipeline: May-Aug data merge → continuous inventory simulation → 85% risk threshold
%           → elbow method + silhouette for K → GMM clustering → demand stats
% Output: Cluster_Results.mat (Cluster_Info: labels, centers, per-cluster statistics)
clc; clear; close all;

load May.mat
load Jun.mat
load Jul.mat
load Aug.mat
load stations

% 1. 合并四个月事件数据
Station_start = [Station_start_May; Station_start_Jun; Station_start_Jul; Station_start_Aug];
Station_end = [Station_end_May; Station_end_Jun; Station_end_Jul; Station_end_Aug];
Time_start = [Time_start_May; Time_start_Jun; Time_start_Jul; Time_start_Aug];
Time_end = [Time_end_May; Time_end_Jun; Time_end_Jul; Time_end_Aug];

clear *_May *_Jun *_Jul *_Aug

N = length(Station_start);

% 2. 构建时序事件流（借车=-1，还车=+1）
event_time = [Time_start; Time_end];
event_station = [Station_start; Station_end];
event_delta = [-ones(N,1); ones(N,1)];

[event_time_sorted, idx] = sort(event_time);
event_station_sorted = event_station(idx);
event_delta_sorted = event_delta(idx);

% 3. 连续库存仿真（容量30，初始库存15）
capacity = 30;
initial_stock = 15;

station_ids = stations{:,1};
num_stations = length(station_ids);

id_map = containers.Map(station_ids, 1:num_stations);

stock = ones(num_stations,1) * initial_stock;
active_day_set = cell(num_stations,1);   % 记录各站点有活跃事件的天数
risk_day_set = cell(num_stations,1);     % 记录发生缺货或溢出的天数

for i = 1:length(event_time_sorted)
    sid = event_station_sorted(i);
    if ~isKey(id_map, sid)
        continue;
    end
    s_index = id_map(sid);
    current_day = dateshift(event_time_sorted(i), 'start', 'day');
    active_day_set{s_index} = unique([active_day_set{s_index}; current_day]);
    new_stock = stock(s_index) + event_delta_sorted(i);
    if new_stock < 0
        risk_day_set{s_index} = unique([risk_day_set{s_index}; current_day]);
        new_stock = 0;
    end
    if new_stock > capacity
        risk_day_set{s_index} = unique([risk_day_set{s_index}; current_day]);
        new_stock = capacity;
    end
    stock(s_index) = new_stock;
end

% 4. 计算风险概率（风险天数/活跃天数）
risk_probability = zeros(num_stations,1);
for s = 1:num_stations
    active_days = length(active_day_set{s});
    risk_days = length(risk_day_set{s});
    if active_days > 0
        risk_probability(s) = risk_days / active_days;
    end
end

% 5. 85%阈值筛选高风险站点
threshold = 0.85;
highrisk_flag = risk_probability >= threshold;

% 6. 各站点总借还量统计
borrow_count = zeros(num_stations,1);
return_count = zeros(num_stations,1);
for i = 1:N
    sid = Station_start(i);
    if isKey(id_map, sid)
        borrow_count(id_map(sid)) = borrow_count(id_map(sid)) + 1;
    end
    sid = Station_end(i);
    if isKey(id_map, sid)
        return_count(id_map(sid)) = return_count(id_map(sid)) + 1;
    end
end
total_demand = borrow_count + return_count;

% 7. 坐标清洗（剔除异常地理坐标）
lat = stations.latitude;
lon = stations.longitude;

valid_idx = (lat > 40) & (lat < 50) & (lon < -70) & (lon > -80);

lat = lat(valid_idx);
lon = lon(valid_idx);
highrisk_flag = highrisk_flag(valid_idx);
total_demand = total_demand(valid_idx);

highrisk_lat = lat(highrisk_flag);
highrisk_lon = lon(highrisk_flag);
highrisk_demand = total_demand(highrisk_flag);

num_highrisk = sum(highrisk_flag);

% 8. 地理坐标转笛卡尔坐标（Haversine，单位km）
R = 6371;
lat0 = mean(highrisk_lat);
lon0 = mean(highrisk_lon);

x = R * cosd(lat0) * deg2rad(highrisk_lon - lon0);
y = R * deg2rad(highrisk_lat - lat0);

XY = [x, y];

% 9. 最优K确定（肘部法+轮廓系数）
K_range = 2:10;
WCSS = zeros(length(K_range),1);
sil_scores = zeros(length(K_range),1);

for i = 1:length(K_range)
    K = K_range(i);
    [idx_temp, C_temp] = kmeans(XY, K, 'Replicates', 10, 'MaxIter', 1000);
    wcss_sum = 0;
    for k = 1:K
        cluster_points = XY(idx_temp == k, :);
        if ~isempty(cluster_points)
            wcss_sum = wcss_sum + sum(sum((cluster_points - C_temp(k,:)).^2));
        end
    end
    WCSS(i) = wcss_sum;
    sil_scores(i) = compute_silhouette_score(XY, idx_temp);
end

[~, best_idx] = max(sil_scores);
optimal_K = K_range(best_idx);

fprintf('Optimal clusters: %d\n', optimal_K);

% 10. GMM聚类
% 拟合高斯混合模型（全协方差，正则化0.001）
gmm = fitgmdist(XY, optimal_K, ...
    'Replicates', 10, ...
    'RegularizationValue', 0.001, ...
    'CovarianceType', 'full', ...
    'Options', statset('MaxIter', 500));

cluster_probs = posterior(gmm, XY);
[~, cluster_idx] = max(cluster_probs, [], 2);

% 11. 加权聚类中心（需求加权）
hub_x = zeros(optimal_K,1);
hub_y = zeros(optimal_K,1);
hub_lat = zeros(optimal_K,1);
hub_lon = zeros(optimal_K,1);

for k = 1:optimal_K
    members = (cluster_idx == k);
    member_count = sum(members);
    if member_count > 0
        w = highrisk_demand(members);
        total_weight = sum(w);
        if total_weight > 0
            hub_x(k) = sum(x(members) .* w) / total_weight;
            hub_y(k) = sum(y(members) .* w) / total_weight;
            hub_lat(k) = sum(highrisk_lat(members) .* w) / total_weight;
            hub_lon(k) = sum(highrisk_lon(members) .* w) / total_weight;
        else
            hub_x(k) = mean(x(members));
            hub_y(k) = mean(y(members));
            hub_lat(k) = mean(highrisk_lat(members));
            hub_lon(k) = mean(highrisk_lon(members));
        end
    end
end

for k = 1:optimal_K
    members = sum(cluster_idx == k);
    demand = sum(highrisk_demand(cluster_idx == k));
    fprintf('Cluster %d: %d stations, total demand: %d\n', k, members, demand);
end

% 12. 可视化
% 图1：GMM聚类结果
colors = lines(max(K_range));
figure('Position', [100 100 900 700], 'Color', 'w');
hold on;
scatter(lon(~highrisk_flag), lat(~highrisk_flag), 15, [0.85 0.85 0.85], 'filled', ...
    'MarkerEdgeColor', 'none', 'DisplayName', 'Stable stations (<85%)');
for k = 1:optimal_K
    cluster_points = (cluster_idx == k);
    scatter(highrisk_lon(cluster_points), highrisk_lat(cluster_points), 50, colors(k,:), 'filled', ...
        'MarkerEdgeColor', 'k', 'LineWidth', 0.5, ...
        'DisplayName', sprintf('Cluster %d', k));
end
scatter(hub_lon, hub_lat, 250, 'k', 'p', 'filled', ...
    'MarkerEdgeColor', 'none', ...
    'DisplayName', 'Dispatch hubs');
xlabel('Longitude (deg)', 'FontSize', 12, 'FontName', 'Arial');
ylabel('Latitude (deg)', 'FontSize', 12, 'FontName', 'Arial');
title(sprintf('Spatial Clustering of High-Risk Bike Stations (GMM, K=%d)', optimal_K), ...
    'FontSize', 13, 'FontName', 'Arial', 'FontWeight', 'bold');
xlim([-73.75 -73.55]);
ylim([45.45 45.60]);
grid on;
box on;
set(gca, 'LineWidth', 1, 'FontSize', 11, 'FontName', 'Arial');
legend('Location', 'eastoutside', 'FontSize', 10);
saveas(gcf, 'GMM_Clustering_Result.png');

% 图2：带凸包边界
figure('Position', [100 100 900 700], 'Color', 'w');
hold on;
scatter(lon(~highrisk_flag), lat(~highrisk_flag), 15, [0.85 0.85 0.85], 'filled', ...
    'MarkerEdgeColor', 'none');
for k = 1:optimal_K
    cluster_points = (cluster_idx == k);
    scatter(highrisk_lon(cluster_points), highrisk_lat(cluster_points), 50, colors(k,:), 'filled', ...
        'MarkerEdgeColor', 'k', 'LineWidth', 0.5);
    if sum(cluster_points) >= 3
        cluster_coords = [highrisk_lon(cluster_points), highrisk_lat(cluster_points)];
        K_hull = convhull(cluster_coords);
        plot(cluster_coords(K_hull,1), cluster_coords(K_hull,2), 'Color', colors(k,:), ...
            'LineWidth', 2, 'LineStyle', '--');
    end
end
scatter(hub_lon, hub_lat, 250, 'k', 'p', 'filled', ...
    'MarkerEdgeColor', 'none');
xlabel('Longitude (deg)', 'FontSize', 12, 'FontName', 'Arial');
ylabel('Latitude (deg)', 'FontSize', 12, 'FontName', 'Arial');
title('Clustering with Convex Hull Boundaries', ...
    'FontSize', 13, 'FontName', 'Arial', 'FontWeight', 'bold');
xlim([-73.75 -73.55]);
ylim([45.45 45.60]);
grid on;
box on;
set(gca, 'LineWidth', 1, 'FontSize', 11, 'FontName', 'Arial');
saveas(gcf, 'GMM_Clustering_with_Hulls.png');

% 图3：聚类评估（肘部法+轮廓系数）
figure('Position', [100 100 1200 400], 'Color', 'w');
subplot(1, 2, 1);
plot(K_range, WCSS, 'o-', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0.2 0.4 0.8]);
hold on;
plot(optimal_K, WCSS(best_idx), 'ro', 'MarkerSize', 12, 'LineWidth', 2);
xlabel('Number of Clusters (K)', 'FontSize', 11, 'FontName', 'Arial');
ylabel('Within-Cluster Sum of Squares', 'FontSize', 11, 'FontName', 'Arial');
title('Elbow Method for Optimal K', 'FontSize', 12, 'FontName', 'Arial', 'FontWeight', 'bold');
grid on;
box on;
set(gca, 'LineWidth', 1, 'FontSize', 10, 'FontName', 'Arial');

subplot(1, 2, 2);
plot(K_range, sil_scores, 's-', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0.8 0.4 0.2]);
hold on;
plot(optimal_K, sil_scores(best_idx), 'ro', 'MarkerSize', 12, 'LineWidth', 2);
xlabel('Number of Clusters (K)', 'FontSize', 11, 'FontName', 'Arial');
ylabel('Mean Silhouette Score', 'FontSize', 11, 'FontName', 'Arial');
title('Silhouette Analysis for Optimal K', 'FontSize', 12, 'FontName', 'Arial', 'FontWeight', 'bold');
grid on;
box on;
set(gca, 'LineWidth', 1, 'FontSize', 10, 'FontName', 'Arial');
text(optimal_K, sil_scores(best_idx)+0.02, sprintf('K=%d\nScore=%.3f', ...
    optimal_K, sil_scores(best_idx)), ...
    'HorizontalAlignment', 'center', 'FontSize', 9, 'FontName', 'Arial');
saveas(gcf, 'Clustering_Evaluation.png');

% 13. 各站点需求统计
station_ids_highrisk = station_ids(valid_idx);
station_ids_highrisk = station_ids_highrisk(highrisk_flag);

n_highrisk = sum(highrisk_flag);
demand_mean = zeros(n_highrisk, 1);
demand_std = zeros(n_highrisk, 1);
initial_bikes = zeros(n_highrisk, 1);

rng(42);

for s = 1:n_highrisk
    station_id = station_ids_highrisk(s);
    start_mask = (Station_start == station_id);
    end_mask = (Station_end == station_id);
    n_borrows = sum(start_mask);
    n_returns = sum(end_mask);
    total_net_demand = n_returns - n_borrows;
    active_days = active_day_set{find(station_ids == station_id)};
    n_days = length(active_days);
    if n_days > 0
        demand_mean(s) = total_net_demand / n_days;
        total_events = n_borrows + n_returns;
        demand_std(s) = sqrt(total_events / n_days);
    else
        demand_mean(s) = 0;
        demand_std(s) = 1;
    end
    initial_bikes(s) = randi([0, 30]);
end

% 14. 各簇统计量汇总
Cluster_Stats = struct();
for k = 1:optimal_K
    members = (cluster_idx == k);
    Cluster_Stats(k).cluster_id = k;
    Cluster_Stats(k).n_stations = sum(members);
    Cluster_Stats(k).station_indices = find(members);
    Cluster_Stats(k).lat = highrisk_lat(members);
    Cluster_Stats(k).lon = highrisk_lon(members);
    Cluster_Stats(k).demand_mean = demand_mean(members);
    Cluster_Stats(k).demand_std = demand_std(members);
    Cluster_Stats(k).initial_bikes = initial_bikes(members);
    Cluster_Stats(k).hub_lat = hub_lat(k);
    Cluster_Stats(k).hub_lon = hub_lon(k);
    Cluster_Stats(k).hub_x = hub_x(k);
    Cluster_Stats(k).hub_y = hub_y(k);
    Cluster_Stats(k).n_vehicles = max(1, round(Cluster_Stats(k).n_stations / 12));
    fprintf('Cluster %d: %d stations, %d vehicles, hub at (%.4f, %.4f)\n', ...
        k, Cluster_Stats(k).n_stations, Cluster_Stats(k).n_vehicles, hub_lat(k), hub_lon(k));
end

% 15. 保存聚类结果
Cluster_Info.cluster_idx = cluster_idx;
Cluster_Info.cluster_centers_lat = hub_lat;
Cluster_Info.cluster_centers_lon = hub_lon;
Cluster_Info.cluster_centers_x = hub_x;
Cluster_Info.cluster_centers_y = hub_y;
Cluster_Info.station_lat = highrisk_lat;
Cluster_Info.station_lon = highrisk_lon;
Cluster_Info.station_demand = highrisk_demand;
Cluster_Info.optimal_K = optimal_K;
Cluster_Info.WCSS = WCSS;
Cluster_Info.silhouette_scores = sil_scores;
Cluster_Info.K_range = K_range;
Cluster_Info.demand_mean = demand_mean;
Cluster_Info.demand_std = demand_std;
Cluster_Info.initial_bikes = initial_bikes;
Cluster_Info.Cluster_Stats = Cluster_Stats;
Cluster_Info.station_ids = station_ids_highrisk;

save('Cluster_Results.mat', 'Cluster_Info');
fprintf('Cluster results saved to Cluster_Results.mat\n');

% 局部函数：手动计算轮廓系数（避免兼容性问题）
function sil_score = compute_silhouette_score(X, labels)
    n = size(X, 1);
    if n == 0
        sil_score = 0;
        return;
    end
    unique_labels = unique(labels);
    k = length(unique_labels);
    if k <= 1
        sil_score = 0;
        return;
    end
    sil_values = zeros(n, 1);
    for i = 1:n
        current_label = labels(i);
        same_cluster = (labels == current_label);
        other_clusters = ~same_cluster;
        same_cluster(i) = false;
        if sum(same_cluster) > 0
            a_i = mean(pdist2(X(i,:), X(same_cluster, :), 'euclidean'));
        else
            a_i = 0;
        end
        b_i = inf;
        for j = 1:k
            if unique_labels(j) ~= current_label
                other_points = (labels == unique_labels(j));
                if sum(other_points) > 0
                    mean_dist = mean(pdist2(X(i,:), X(other_points, :), 'euclidean'));
                    b_i = min(b_i, mean_dist);
                end
            end
        end
        if a_i == 0 && b_i == inf
            sil_values(i) = 0;
        elseif a_i == 0
            sil_values(i) = 1;
        elseif b_i == inf
            sil_values(i) = -1;
        else
            sil_values(i) = (b_i - a_i) / max(a_i, b_i);
        end
    end
    sil_score = mean(sil_values);
end
