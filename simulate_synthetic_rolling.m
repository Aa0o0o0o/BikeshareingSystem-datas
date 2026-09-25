% 合成数据滚动仿真：截断正态日净需求评估固定调度方案
% Input: cluster_data -- 含JWD,xi,mean_demand,std_demand,qidian,n_stations,n_vehicles的结构体
%        solution -- 固定路径解（NS为空）; params -- 含p,c,C,capacity的参数结构体
%        daily_demands -- [n_stations×n_days] 日净需求矩阵
%        fixed_quantities -- 预计算取放量结构体（可选，与rolling_horizon_simulation格式一致）
% Output: avg_total_cost -- 日均总成本; transport_cost -- 一次性运输成本
%         avg_shortage_cost -- 日均缺货成本; daily_shortage_costs -- [n_days×1]
%         daily_end_inventory -- [n_stations×n_days]
function [avg_total_cost, transport_cost, avg_shortage_cost, daily_shortage_costs, daily_end_inventory] = ...
    simulate_synthetic_rolling(cluster_data, solution, params, daily_demands, fixed_quantities)

    if ~isfield(params, 'capacity') || isempty(params.capacity)
        params.capacity = 30;
    end
    if nargin < 5
        fixed_quantities = [];
    end

    n_s = cluster_data.n_stations;
    xi = double(cluster_data.xi);
    qidian = cluster_data.qidian;
    n_v = cluster_data.n_vehicles;
    p = params.p; c = params.c; C = params.C; cap = params.capacity;
    n_days = size(daily_demands, 2);

    transport_cost = 0;
    station_qty = zeros(n_s, 1);

    if ~isempty(solution)
        JWD = cluster_data.JWD;
        D = zeros(n_s);
        for i = 1:n_s
            for j = 1:n_s
                D(i,j) = 111 * sqrt((JWD(i,1)-JWD(j,1))^2 + (JWD(i,2)-JWD(j,2))^2);
            end
        end
        dis = calculate_distance(solution, D, qidian);
        transport_cost = sum(dis * c);

        if ~isempty(fixed_quantities) && isstruct(fixed_quantities) && ~isempty(fieldnames(fixed_quantities))
            for v = 1:n_v
                fn = sprintf('vehicle%d', v);
                if isfield(fixed_quantities, fn)
                    det = fixed_quantities.(fn);
                    if isfield(det, 'stations') && isfield(det, 'quantities')
                        for i = 1:length(det.stations)
                            s = det.stations(i);
                            if s >= 1 && s <= n_s
                                station_qty(s) = station_qty(s) + det.quantities(i);
                            end
                        end
                    end
                end
            end
        else
            routes = cell(n_v, 1);
            if n_v == 1
                routes{1} = solution;
            else
                z = find(solution == 0);
                start = 1;
                for v = 1:n_v
                    if v <= length(z)
                        routes{v} = solution(start:z(v)-1);
                        start = z(v) + 1;
                    else
                        routes{v} = solution(start:end);
                    end
                end
            end
            for v = 1:n_v
                r = routes{v};
                if isempty(r), continue; end
                r_depot = [qidian(v), r, qidian(v)];
                try
                    [x, ~] = socpcost(r_depot, xi, cluster_data.mean_demand, cluster_data.std_demand, p, C);
                    for i = 1:length(r_depot)
                        station_qty(r_depot(i)) = station_qty(r_depot(i)) + x(i);
                    end
                catch ME
                    fprintf('Warning: SOCP failed: %s\n', ME.message);
                end
            end
        end
    end

    daily_shortage_costs = zeros(n_days, 1);
    daily_end_inventory = zeros(n_s, n_days);
    total_short = 0;

    for d = 1:n_days
        if ~isempty(solution)
            inv = xi + station_qty;
            inv = max(0, min(inv, cap));
        else
            inv = xi;
        end
        day_short = 0;
        for s = 1:n_s
            net = daily_demands(s, d);
            inv(s) = inv(s) + net;
            if inv(s) < 0
                day_short = day_short + (-inv(s)) * p;
                inv(s) = 0;
            elseif inv(s) > cap
                day_short = day_short + (inv(s) - cap) * p;
                inv(s) = cap;
            end
        end
        daily_shortage_costs(d) = day_short;
        total_short = total_short + day_short;
        daily_end_inventory(:, d) = inv;
    end

    avg_shortage_cost = total_short / n_days;
    avg_total_cost = transport_cost + avg_shortage_cost;
end
