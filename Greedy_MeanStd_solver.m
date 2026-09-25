% 贪婪-均值标准差启发式：仅服务偏离均值超过n倍标准差的站点
% Input: JWD -- 坐标矩阵; xi -- 初始库存; mean_demand, std_demand -- 需求分布参数
%        qidian -- 车场索引; p, c, C -- 成本参数; n -- 阈值倍数; options -- 可选参数
% Output: solution -- 串联路径; cost -- 总成本; route_details -- 路径详情
function [solution, cost, route_details] = Greedy_MeanStd_solver(...
    JWD, xi, mean_demand, std_demand, qidian, p, c, C, n, options)

    if nargin < 10 || isempty(options)
        options = struct();
    end
    verbose = get_opt(options, 'verbose', false);

    n_c = size(JWD, 1);
    n_v = length(qidian);

    D = zeros(n_c);
    for i = 1:n_c
        D(i,:) = 111 * sqrt((JWD(i,1)-JWD(:,1)').^2 + (JWD(i,2)-JWD(:,2)').^2);
    end

    clients = setdiff(1:n_c, qidian);
    lb = mean_demand(clients) - n * std_demand(clients);
    ub = mean_demand(clients) + n * std_demand(clients);
    need = clients((xi(clients) <= lb) | (xi(clients) >= ub))';

    if isempty(need)
        solution = [];
        cost = calculate_cost(solution, xi, mean_demand, std_demand, D, qidian, p, c, C);
        route_details = cell(n_v, 1);
        return;
    end

    route = cell(n_v, 1);
    pos = qidian;
    while ~isempty(need)
        mini = Inf; best_car = 1; best_idx = 1;
        for i = 1:length(need)
            for j = 1:n_v
                d = D(pos(j), need(i));
                if d < mini
                    mini = d; best_car = j; best_idx = i;
                end
            end
        end
        route{best_car} = [route{best_car}, need(best_idx)];
        pos(best_car) = need(best_idx);
        need(best_idx) = [];
    end

    solution = [];
    for car = 1:n_v
        if car == n_v
            solution = [solution, route{car}];
        else
            solution = [solution, route{car}, 0];
        end
    end

    cost = calculate_cost(solution, xi, mean_demand, std_demand, D, qidian, p, c, C);
    route_details = struct('route', route, 'qidian', qidian);

    if verbose
        fprintf('Greedy-MeanStd (n=%.1f): Cost=%.2f, Visited=%d\n', ...
            n, cost, length(solution) - sum(solution==0));
    end
end

function val = get_opt(options, field, default)
    if isfield(options, field), val = options.(field); else, val = default; end
end
