% 暴力枚举精确求解器（仅支持单车小规模问题）
% Input: JWD -- 坐标矩阵; xi -- 初始库存; mean_demand, std_demand -- 需求分布参数
%        qidian -- 车场索引; p, c, C -- 成本参数; options -- 可选参数
% Output: best_solution -- 最优路径; best_cost -- 最优成本
%         time_elapsed -- 运行时间; nodes_explored -- 评估解数
function [best_solution, best_cost, time_elapsed, nodes_explored] = Exact_solver_brute(...
    JWD, xi, mean_demand, std_demand, qidian, p, c, C, options)

    if nargin < 9 || isempty(options)
        options = struct();
    end
    verbose = get_opt(options, 'verbose', true);

    tic;
    start_time = tic;
    n = size(JWD, 1);
    if length(qidian) > 1
        error('Only single vehicle supported');
    end

    D = zeros(n);
    for i = 1:n
        for j = 1:n
            D(i,j) = 111 * sqrt((JWD(i,1)-JWD(j,1))^2 + (JWD(i,2)-JWD(j,2))^2);
        end
    end

    start = qidian(1);
    cand = setdiff(1:n, start);
    m = length(cand);

    total = 0;
    for k = 0:m
        total = total + nchoosek(m,k) * factorial(k);
    end
    if verbose
        fprintf('Brute Force: %d nodes, %.0f possibilities\n', n, total);
    end

    best_cost = inf; best_solution = []; nodes_explored = 0;
    report = max(1, floor(total / 4)); last = 0;

    for k = 0:m
        if k == 0
            route = [];
            cc = calculate_cost(route, xi, mean_demand, std_demand, D, qidian, p, c, C);
            nodes_explored = nodes_explored + 1;
            if cc < best_cost
                best_cost = cc; best_solution = route;
            end
            if nodes_explored - last >= report
                fprintf('  Progress: %.1f%%\n', 100*nodes_explored/total);
                last = nodes_explored;
            end
        else
            combs = nchoosek(1:m, k);
            for ci = 1:size(combs,1)
                nodes = cand(combs(ci,:));
                pm = perms(1:k);
                for pi = 1:size(pm,1)
                    route = nodes(pm(pi,:));
                    cc = calculate_cost(route, xi, mean_demand, std_demand, D, qidian, p, c, C);
                    nodes_explored = nodes_explored + 1;
                    if cc < best_cost
                        best_cost = cc; best_solution = route;
                    end
                    if nodes_explored - last >= report
                        fprintf('  Progress: %.1f%%, best: %.4f\n', 100*nodes_explored/total, best_cost);
                        last = nodes_explored;
                    end
                end
            end
            if verbose
                fprintf('  [k=%d] Completed, best: %.4f\n', k, best_cost);
            end
        end
    end

    time_elapsed = toc(start_time);
    if verbose
        fprintf('Optimal: %s, cost=%.4f, evaluated %d in %.2f s\n', ...
            mat2str(best_solution), best_cost, nodes_explored, time_elapsed);
    end
end

function val = get_opt(options, field, default)
    if isfield(options, field)
        val = options.(field);
    else
        val = default;
    end
end
