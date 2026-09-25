% Gurobi Prize-Collecting TSP 求解器（单车）
% 使用 Gurobi MIP 求解带节点选择的路径规划，然后用 SOCP 精确评估总成本
% Input:  JWD -- 坐标矩阵; xi -- 初始库存
%         mean_demand, std_demand -- 需求分布参数
%         qidian -- 车场索引（仅支持单车）
%         p, c, C -- 成本参数
%         options -- 可选参数（verbose）
% Output: solution -- 最优路径（不含车场）
%         cost -- 精确总成本（内联 Gurobi SOCP 评估）
%         time_elapsed -- Gurobi 求解时间（不含 exact cost 评估）
function [solution, cost, time_elapsed] = gurobi_pctsp_solver( ...
    JWD, xi, mean_demand, std_demand, qidian, p, c, C, options)

    if nargin < 10 || isempty(options)
        options = struct();
    end
    verbose = get_opt(options, 'verbose', false);

    n_c = size(JWD, 1);
    n_v = length(qidian);
    if n_v > 1
        error('gurobi_pctsp_solver: 当前仅支持单车问题。');
    end
    depot = qidian(1);

    % 距离矩阵
    D = zeros(n_c);
    for i = 1:n_c
        for j = 1:n_c
            D(i,j) = 111 * sqrt((JWD(i,1)-JWD(j,1))^2 + (JWD(i,2)-JWD(j,2))^2);
        end
    end

    % 非车场站点
    stations = setdiff(1:n_c, depot);
    n = length(stations);

    % 未访问惩罚 = NS 期望缺货成本
    penalty = zeros(n, 1);
    for i = 1:n
        s = stations(i);
        penalty(i) = (mean_demand(s) - xi(s)) / 2 + ...
                     0.5 * sqrt(std_demand(s)^2 + (xi(s) - mean_demand(s))^2);
    end
    penalty = penalty * p;

    % 节点编号：0 = depot, 1..n = stations
    N = n + 1;

    % 变量索引函数
    idx_x = @(i, j) i * N + j + 1;          % x_{ij}, i,j in 0..n
    idx_y = @(i) (N * N) + i;                % y_i,   i in 1..n
    idx_u = @(i) (N * N) + n + i;            % u_i,   i in 1..n

    n_vars = N * N + n + n;
    model.obj = zeros(n_vars, 1);
    model.lb  = zeros(n_vars, 1);
    model.ub  = ones(n_vars, 1);
    model.vtype = repmat('B', n_vars, 1);
    model.modelsense = 'min';

    % 目标函数：运输成本 + 未访问惩罚
    % 由于 minimize(transport + sum penalty*(1-y)) = minimize(transport - sum penalty*y) + const
    for i = 0:n
        for j = 0:n
            if i == 0 && j == 0
                model.obj(idx_x(i, j)) = 0;
            elseif i == 0
                model.obj(idx_x(i, j)) = c * D(depot, stations(j));
            elseif j == 0
                model.obj(idx_x(i, j)) = c * D(stations(i), depot);
            else
                model.obj(idx_x(i, j)) = c * D(stations(i), stations(j));
            end
        end
    end
    for i = 1:n
        model.obj(idx_y(i)) = -penalty(i);
    end

    % u 为连续变量 [0, n]
    for i = 1:n
        model.vtype(idx_u(i)) = 'C';
        model.lb(idx_u(i)) = 0;
        model.ub(idx_u(i)) = n;
    end

    % 禁止站点自环
    for i = 1:n
        model.ub(idx_x(i, i)) = 0;
    end

    % 构建约束矩阵
    A = [];
    rhs = [];
    sense = [];

    % (1) 离开车场一次
    row = zeros(1, n_vars);
    for j = 0:n
        row(idx_x(0, j)) = 1;
    end
    A = [A; row]; rhs = [rhs; 1]; sense = [sense; '='];

    % (2) 返回车场一次
    row = zeros(1, n_vars);
    for i = 0:n
        row(idx_x(i, 0)) = 1;
    end
    A = [A; row]; rhs = [rhs; 1]; sense = [sense; '='];

    % (3) 离开站点 i 的次数 = y_i
    for i = 1:n
        row = zeros(1, n_vars);
        for j = 0:n
            row(idx_x(i, j)) = 1;
        end
        row(idx_y(i)) = -1;
        A = [A; row]; rhs = [rhs; 0]; sense = [sense; '='];
    end

    % (4) 进入站点 i 的次数 = y_i
    for j = 1:n
        row = zeros(1, n_vars);
        for i = 0:n
            row(idx_x(i, j)) = 1;
        end
        row(idx_y(j)) = -1;
        A = [A; row]; rhs = [rhs; 0]; sense = [sense; '='];
    end

    % (5) x_{ij} <= y_i
    for i = 1:n
        for j = 0:n
            if i == j, continue; end
            row = zeros(1, n_vars);
            row(idx_x(i, j)) = 1;
            row(idx_y(i)) = -1;
            A = [A; row]; rhs = [rhs; 0]; sense = [sense; '<'];
        end
    end

    % (6) x_{ij} <= y_j
    for j = 1:n
        for i = 0:n
            if i == j, continue; end
            row = zeros(1, n_vars);
            row(idx_x(i, j)) = 1;
            row(idx_y(j)) = -1;
            A = [A; row]; rhs = [rhs; 0]; sense = [sense; '<'];
        end
    end

    % (7) MTZ 子回路消除
    for i = 1:n
        for j = 1:n
            if i == j, continue; end
            row = zeros(1, n_vars);
            row(idx_u(i)) = 1;
            row(idx_u(j)) = -1;
            row(idx_x(i, j)) = n + 1;
            A = [A; row]; rhs = [rhs; n]; sense = [sense; '<'];
        end
    end

    % (8) y_i <= u_i
    for i = 1:n
        row = zeros(1, n_vars);
        row(idx_y(i)) = 1;
        row(idx_u(i)) = -1;
        A = [A; row]; rhs = [rhs; 0]; sense = [sense; '<'];
    end

    % (9) u_i <= n * y_i
    for i = 1:n
        row = zeros(1, n_vars);
        row(idx_u(i)) = 1;
        row(idx_y(i)) = -n;
        A = [A; row]; rhs = [rhs; 0]; sense = [sense; '<'];
    end

    model.A = sparse(A);
    model.rhs = rhs;
    model.sense = sense;

    if verbose
        params.outputflag = 1;
    else
        params.outputflag = 0;
    end

    t0 = tic;
    try
        result = gurobi(model, params);
        time_elapsed = toc(t0);
    catch ME
        warning('Gurobi 求解失败: %s', ME.message);
        solution = [];
        cost = Inf;
        time_elapsed = toc(t0);
        return;
    end

    if strcmp(result.status, 'OPTIMAL') || strcmp(result.status, 'SUBOPTIMAL')
        x_sol = result.x;

        % 提取路径
        if x_sol(idx_x(0, 0)) > 0.5
            solution = [];
        else
            route = [];
            current = 0;
            visited = false(1, n);
            while true
                next = -1;
                for j = 0:n
                    if j == current, continue; end
                    if x_sol(idx_x(current, j)) > 0.5
                        next = j;
                        break;
                    end
                end
                if next <= 0
                    break;
                end
                route = [route, stations(next)];
                if visited(next)
                    warning('Gurobi 解出现子回路，返回部分路径。');
                    break;
                end
                visited(next) = true;
                current = next;
            end
            solution = route;
        end

        cost = evaluate_cost_gurobi(solution, xi, mean_demand, std_demand, D, depot, p, c, C);
        if verbose
            fprintf('Gurobi PCTSP: route=[%s], exact_cost=%.2f, time=%.4f s\n', ...
                num2str(solution), cost, time_elapsed);
        end
    else
        warning('Gurobi 未找到最优解。状态: %s', result.status);
        solution = [];
        cost = Inf;
    end
end

function cost = evaluate_cost_gurobi(solution, xi, mean_demand, std_demand, D, depot, p, c, C)
    % 单车精确成本：Gurobi SOCP + 运输成本 + 未访问惩罚
    n_c = size(D, 1);
    if isempty(solution)
        r = [depot, depot];
    else
        r = [depot, solution, depot];
    end
    K = length(r);
    nvars = 6 * K;

    f3 = mean_demand(r); f3 = f3(:)';
    sigma = std_demand(r); sigma = sigma(:)';
    f4 = sigma.^2 + f3.^2;
    obj = [zeros(K,1); ones(K,1); f3'; f4'; zeros(2*K,1)];

    lb = [-reshape(xi(r), 1, []), -inf(1,2*K), zeros(1,K), -inf(1,2*K)];
    ub = [reshape((30 - xi(r)), 1, []), inf(1, 5*K)];

    n_lin = 4 * K - 1;
    A = sparse(n_lin, nvars);
    rhs = zeros(n_lin, 1);
    sense = repmat('<', n_lin, 1);

    for i = 1:K-1
        A(i, 1:i) = 1;
        rhs(i) = 0;
    end
    for i = 1:K-1
        A(K-1+i, 1:i) = -1;
        rhs(K-1+i) = C;
    end
    for i = 1:K
        A(2*K-2+i, K+i) = -1;
        A(2*K-2+i, 4*K+i) = 1;
        rhs(2*K-2+i) = 0;
    end
    A(3*K-1, 1:K) = 1;
    rhs(3*K-1) = 0;
    sense(3*K-1) = '=';
    for i = 1:K
        A(3*K-1+i, 3*K+i) = 1;
        A(3*K-1+i, 4*K+i) = 1;
        rhs(3*K-1+i) = 0;
        sense(3*K-1+i) = '>';
    end

    model_q.quadcon = struct('Qc', {}, 'q', {}, 'rhs', {}, 'sense', {});
    for i = 1:K
        Qc = sparse(nvars, nvars);
        Qc(2*K+i, 2*K+i) = 1;
        Qc(3*K+i, 4*K+i) = -2;
        Qc(4*K+i, 3*K+i) = -2;
        model_q.quadcon(i).Qc = Qc;
        model_q.quadcon(i).q = sparse(nvars, 1);
        model_q.quadcon(i).rhs = 0;
        model_q.quadcon(i).sense = '<';
    end

    model_q.modelsense = 'min';
    model_q.obj = double(obj);
    model_q.lb = double(lb');
    model_q.ub = double(ub');
    model_q.A = A;
    model_q.rhs = rhs;
    model_q.sense = sense;

    params_q.outputflag = 0;
    try
        res_q = gurobi(model_q, params_q);
    catch
        res_q = struct('status', 'ERROR');
    end

    if isfield(res_q, 'x') && ~isempty(res_q.x)
        scost = res_q.objval;
    else
        scost = Inf;
    end

    % 运输成本
    tcost = 0;
    if K > 2
        for i = 1:K-1
            tcost = tcost + c * D(r(i), r(i+1));
        end
    end

    % 未访问惩罚
    pcost = 0;
    unvisited = setdiff(1:n_c, [r(:)', depot]);
    for i = 1:length(unvisited)
        s = unvisited(i);
        fai = (mean_demand(s) - xi(s))/2 + 0.5*sqrt(std_demand(s)^2 + (xi(s) - mean_demand(s))^2);
        pcost = pcost + fai * p;
    end

    cost = scost + tcost + pcost;
end

function val = get_opt(options, field, default)
    if isfield(options, field), val = options.(field);
    else, val = default; end
end
