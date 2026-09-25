% 后处理：迭代移除取放量绝对值<=threshold的冗余站点，重新求解SOCP
% Input: sol -- 原始路径解; data -- 含JWD,xi,mean_demand,std_demand,qidian,n_stations,n_vehicles的结构体
%        p, c, C -- 成本与容量参数; threshold -- 取放量阈值（默认0.01）
% Output: sol_new -- 过滤后路径; qty_new -- 过滤后取放量结构体; cost_new -- 重新计算的总成本
function [sol_new, qty_new, cost_new] = postprocess_zero_qty(sol, data, p, c, C, threshold)
    if nargin < 6 || isempty(threshold)
        threshold = 0.01;
    end
    if isempty(sol)
        sol_new = []; qty_new = struct(); cost_new = 0;
        return;
    end

    n_vehicles = data.n_vehicles;
    qidian = data.qidian;
    xi = data.xi;
    n_stations = data.n_stations;

    D = zeros(n_stations);
    JWD = data.JWD;
    for i = 1:n_stations
        D(i,:) = 111 * sqrt((JWD(i,1)-JWD(:,1)').^2 + (JWD(i,2)-JWD(:,2)').^2);
    end

    sol_new = sol;
    for iter = 1:5
        routes = parse_routes(sol_new, n_vehicles);
        changed = false;
        new_routes = cell(n_vehicles, 1);
        for v = 1:n_vehicles
            r = routes{v};
            if isempty(r)
                new_routes{v} = r;
                continue;
            end
            r_depot = [qidian(v), r, qidian(v)];
            try
                [x, ~] = socpcost(r_depot, xi, data.mean_demand, data.std_demand, p, C);
            catch
                new_routes{v} = r;
                continue;
            end
            keep = abs(x(2:end-1)) > threshold;
            if any(~keep), changed = true; end
            new_routes{v} = r(keep);
        end
        sol_new = join_routes(new_routes, n_vehicles);
        if ~changed, break; end
    end

    qty_new = struct();
    routes = parse_routes(sol_new, n_vehicles);
    for v = 1:n_vehicles
        r = routes{v};
        if isempty(r), continue; end
        r_depot = [qidian(v), r, qidian(v)];
        try
            [x, ~] = socpcost(r_depot, xi, data.mean_demand, data.std_demand, p, C);
            qty_new.(sprintf('vehicle%d', v)).stations = r_depot;
            qty_new.(sprintf('vehicle%d', v)).quantities = x(1:length(r_depot));
        catch
            qty_new.(sprintf('vehicle%d', v)).stations = r_depot;
            qty_new.(sprintf('vehicle%d', v)).quantities = zeros(length(r_depot), 1);
        end
    end
    cost_new = calculate_cost(sol_new, xi, data.mean_demand, data.std_demand, D, qidian, p, c, C);
end

function routes = parse_routes(sol, n_vehicles)
    routes = cell(n_vehicles, 1);
    if n_vehicles == 1
        routes{1} = sol;
        return;
    end
    idx = find(sol == 0);
    start = 1;
    for v = 1:n_vehicles
        if v <= length(idx)
            routes{v} = sol(start:idx(v)-1);
            start = idx(v) + 1;
        else
            routes{v} = sol(start:end);
        end
    end
end

function sol = join_routes(routes, n_vehicles)
    sol = [];
    for v = 1:n_vehicles
        if v == n_vehicles
            sol = [sol, routes{v}];
        else
            sol = [sol, routes{v}, 0];
        end
    end
end
