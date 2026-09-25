% 大邻域搜索自适应邻域选择（LS-ANS）求解器
% Input: JWD -- 坐标矩阵; xi -- 初始库存; mean_demand, std_demand -- 需求分布参数
%        qidian -- 车场索引; p, c, C -- 成本参数; T -- 工作时间
%        options -- 算法参数结构体
% Output: best_solution -- 最优路径; best_cost -- 最优成本; time_elapsed -- 运行时间
function [best_solution, best_cost, time_elapsed] = LS_ANS_solver(...
    JWD, xi, mean_demand, std_demand, qidian, p, c, C, T, options)

    if nargin < 10 || isempty(options)
        options = struct();
    end

    num_iter = get_opt(options, 'num_iterations', 300);
    ls_iter = get_opt(options, 'localsearch_iterations', 10);
    no_improve_max = get_opt(options, 'no_improve_max', 50);
    min_task = get_opt(options, 'min_task', 1);
    maxDist = get_opt(options, 'maxDistance', 40 * T);
    verbose = get_opt(options, 'verbose', false);

    n_c = size(JWD, 1);
    n_v = length(qidian);

    D = zeros(n_c);
    for i = 1:n_c
        for j = 1:n_c
            D(i,j) = 111 * sqrt((JWD(i,1)-JWD(j,1))^2 + (JWD(i,2)-JWD(j,2))^2);
        end
    end

    score = abs(xi - mean_demand) ./ std_demand;

    tic;
    if isfield(options, 'initial_solution') && ~isempty(options.initial_solution)
        cur_sol = options.initial_solution;
    else
        cur_sol = initial_sol(xi, mean_demand, std_demand, D, qidian, n_c);
    end
    cur_cost = calculate_cost(cur_sol, xi, mean_demand, std_demand, D, qidian, p, c, C);

    best_solution = cur_sol;
    best_cost = cur_cost;
    no_improve = 0;

    for iter = 1:num_iter
        des = destroy(cur_sol, randi(2), n_v, score, min_task);
        rep = repair(des, n_c, randi(2), qidian, maxDist, D, score);
        [imp_cost, imp_sol] = local_search(rep, randi(3), xi, mean_demand, std_demand, ...
                                           D, qidian, p, c, maxDist, min_task, C, ls_iter);
        if imp_cost < cur_cost
            cur_sol = imp_sol; cur_cost = imp_cost;
            if cur_cost < best_cost
                best_solution = cur_sol; best_cost = cur_cost;
            end
            no_improve = 0;
        else
            no_improve = no_improve + 1;
        end
        if no_improve >= no_improve_max
            if verbose
                fprintf('Early stop at iteration %d\n', iter);
            end
            break;
        end
    end

    time_elapsed = toc;
    if verbose
        fprintf('LS-ANS: Best cost = %.2f, Time = %.2f s\n', best_cost, time_elapsed);
    end
end

function val = get_opt(options, field, default)
    if isfield(options, field), val = options.(field); else, val = default; end
end
