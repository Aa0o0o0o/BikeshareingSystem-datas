% 滚动时域仿真：用真实事件数据评估固定调度方案（每日重置库存）
% Input: cluster_data -- 含JWD,xi,station_ids,qidian,n_stations,n_vehicles的结构体
%        solution -- 固定路径解（NS为空）; params -- 含p,c,capacity的参数结构体
%        sep_events -- 真实事件数据; fixed_quantities -- 预计算取放量结构体（可选）
% Output: avg_total_cost -- 日均总成本; transport_cost -- 一次性运输成本
%         avg_shortage_cost -- 日均缺货成本; daily_shortage_costs -- [n_days×1]
%         daily_end_inventory -- [n_stations×n_days]
function [avg_total_cost, transport_cost, avg_shortage_cost, daily_shortage_costs, daily_end_inventory] = ...
    rolling_horizon_simulation(cluster_data, solution, params, sep_events, fixed_quantities)

    if ~isfield(params, 'capacity') || isempty(params.capacity)
        params.capacity = 30;
    end
    if nargin < 5
        fixed_quantities = [];
    end

    n_s = cluster_data.n_stations;
    xi = cluster_data.xi;
    n_v = cluster_data.n_vehicles;
    p = params.p;
    c = params.c;
    cap = params.capacity;

    transport_cost = 0;
    if ~isempty(solution)
        JWD = cluster_data.JWD;
        D = zeros(n_s);
        for i = 1:n_s
            for j = 1:n_s
                D(i,j) = 111 * sqrt((JWD(i,1)-JWD(j,1))^2 + (JWD(i,2)-JWD(j,2))^2);
            end
        end
        dis = calculate_distance(solution, D, cluster_data.qidian);
        transport_cost = sum(dis * c);
    end

    days = dateshift(sep_events.Time_start, 'start', 'day');
    unique_days = unique(days);
    n_days = length(unique_days);
    if n_days == 0
        avg_total_cost = 0; avg_shortage_cost = 0;
        daily_shortage_costs = []; daily_end_inventory = [];
        return;
    end

    daily_fixed_qty = zeros(n_s, 1);
    if ~isempty(fixed_quantities) && isstruct(fixed_quantities) && ~isempty(fieldnames(fixed_quantities))
        for v = 1:n_v
            fn = sprintf('vehicle%d', v);
            if isfield(fixed_quantities, fn)
                det = fixed_quantities.(fn);
                if isfield(det, 'stations') && isfield(det, 'quantities')
                    for i = 1:length(det.stations)
                        s = det.stations(i);
                        if s >= 1 && s <= n_s
                            daily_fixed_qty(s) = daily_fixed_qty(s) + det.quantities(i);
                        end
                    end
                end
            end
        end
    end

    sids = cluster_data.station_ids;
    start_mask = ismember(sep_events.Station_start, sids);
    end_mask = ismember(sep_events.Station_end, sids);

    daily_shortage_costs = zeros(n_days, 1);
    daily_end_inventory = zeros(n_s, n_days);
    total_short = 0;

    for d = 1:n_days
        day_mask = (days == unique_days(d));
        if ~isempty(solution)
            inv = xi + daily_fixed_qty;
            inv = max(0, min(inv, cap));
        else
            inv = xi;
        end

        day_starts = sep_events.Station_start(day_mask & start_mask);
        day_ends = sep_events.Station_end(day_mask & end_mask);
        day_short = 0;
        for s = 1:n_s
            sid = sids(s);
            net = sum(day_ends == sid) - sum(day_starts == sid);
            inv(s) = inv(s) + net;
            if inv(s) < 0
                day_short = day_short + (-inv(s)) * p;
                inv(s) = 0;
            elseif inv(s) > cap
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
