% L2分布偏移鲁棒性测试：训练→固定方案→多场景评估
% 训练流程对齐mode2；验证结构对齐mode3；输出delta需求分布统计
% Input: cluster_data -- 含JWD,xi,mean_demand,std_demand,qidian,n_stations,n_vehicles
%        base_params -- 含p,c,C,capacity; delta_values -- 均值偏移率向量
%        n_train,n_test -- 训练/测试天数; n_greedy_values -- 贪婪阈值参数
%        do_training_comparison -- 是否输出训练对比
% Output: results -- [n_delta×1] 结构体数组，含算法成本与demand_stats
function results = run_l2_robustness_test(cluster_data, base_params, delta_values, ...
    n_train, n_test, n_greedy_values, do_training_comparison)

    n_s = cluster_data.n_stations;
    n_v = cluster_data.n_vehicles;
    true_mean = double(cluster_data.mean_demand);
    true_std = double(cluster_data.std_demand);
    xi = double(cluster_data.xi);
    JWD = cluster_data.JWD;
    qidian = cluster_data.qidian;
    p = base_params.p; c = base_params.c; C = base_params.C; cap = base_params.capacity;
    T = 10;
    t0 = tic;

    % 生成训练需求（Delta=0，截断正态）
    rng(111);
    train_d = zeros(n_s, n_train);
    for s = 1:n_s
        mu = true_mean(s); sigma = true_std(s);
        if sigma < 1e-6
            train_d(s, :) = mu;
        else
            a = (-50 - mu) / sigma; b = (80 - mu) / sigma;
            train_d(s, :) = mu + sigma * truncnorm_rnd(a, b, n_train);
        end
    end
    sample_mean = mean(train_d, 2);
    sample_std = std(train_d, 0, 2);

    D = zeros(n_s);
    for i = 1:n_s
        for j = 1:n_s
            D(i,j) = 111 * sqrt((JWD(i,1)-JWD(j,1))^2 + (JWD(i,2)-JWD(j,2))^2);
        end
    end

    % ---- 训练阶段（mode2对齐） ----
    data_est = struct('JWD', JWD, 'xi', xi, 'mean_demand', sample_mean, ...
                      'std_demand', sample_std, 'qidian', qidian, ...
                      'n_stations', n_s, 'n_vehicles', n_v);
    solutions = struct(); costs = struct(); quantities = struct();

    % NS
    solutions.NS = []; costs.NS = compute_analytical_cost([], data_est, D, p, c, C); quantities.NS = struct();

    % Greedy
    best_gc = inf; best_gs = [];
    for i = 1:length(n_greedy_values)
        np = n_greedy_values(i); nk = sprintf('n%.0f', np*10);
        [gs, gc] = Greedy_MeanStd_solver(JWD, xi, sample_mean, sample_std, qidian, p, c, C, np, struct('verbose', false));
        solutions.(['GMS_' nk]) = gs; costs.(['GMS_' nk]) = gc;
        quantities.(['GMS_' nk]) = compute_quantities(gs, data_est, p, C);
        if gc < best_gc, best_gc = gc; best_gs = gs; end
    end

    % LS-ANS
    opts = struct('num_iterations', 300, 'localsearch_iterations', 10, 'no_improve_max', 50, 'verbose', false);
    if ~isempty(best_gs), opts.initial_solution = best_gs; end
    [ls_sol, ls_cost, ~] = LS_ANS_solver(JWD, xi, sample_mean, sample_std, qidian, p, c, C, T, opts);
    [ls_sol_pp, ~, ls_cost_pp] = postprocess_zero_qty(ls_sol, data_est, p, c, C, 0.5);
    if ~isempty(ls_sol_pp)
        solutions.LS_ANS = ls_sol_pp; costs.LS_ANS = ls_cost_pp;
        quantities.LS_ANS = compute_quantities(ls_sol_pp, data_est, p, C);
    else
        solutions.LS_ANS = ls_sol; costs.LS_ANS = ls_cost;
        quantities.LS_ANS = compute_quantities(ls_sol, data_est, p, C);
    end

    % Exact（仅单车≤10站）
    has_exact = false;
    if n_v == 1 && n_s <= 10
        try
            [es, ec, ~, ~] = Exact_solver_brute(JWD, xi, sample_mean, sample_std, qidian, p, c, C, struct('verbose', true));
            has_exact = true; solutions.Exact = es; costs.Exact = ec;
            quantities.Exact = compute_quantities(es, data_est, p, C);
        catch ME
            fprintf('Warning: Exact solver failed: %s\n', ME.message);
        end
    end

    % 训练对比表
    if do_training_comparison
        fid = fopen('training_comparison_9stations.txt', 'w');
        fprintf(fid, 'Training Phase Comparison (Random Cluster-9)\n');
        fprintf(fid, '%-22s %12s\n', 'Algorithm', 'TotalCost');
        fprintf(fid, '%-22s %12.2f\n', 'NS', costs.NS);
        for i = 1:length(n_greedy_values)
            np = n_greedy_values(i); nk = sprintf('n%.0f', np*10);
            fprintf(fid, '%-22s %12.2f\n', sprintf('Greedy-MeanStd(%.1f)', np), costs.(['GMS_' nk]));
        end
        fprintf(fid, '%-22s %12.2f\n', 'LS-ANS', costs.LS_ANS);
        if has_exact, fprintf(fid, '%-22s %12.2f\n', 'Exact (Brute)', costs.Exact); end
        fclose(fid);
    end

    % ---- 验证阶段（mode3结构对齐） ----
    n_d = length(delta_values);

    if has_exact
        alg_fields = {'NS', 'GMS_n1', 'GMS_n5', 'GMS_n15', 'LS_ANS', 'Exact'};
    else
        alg_fields = {'NS', 'GMS_n1', 'GMS_n5', 'GMS_n15', 'LS_ANS'};
    end
    n_alg = length(alg_fields);
    results = repmat(struct(), n_d, 1);
    tt = tic; n_total = n_d;

    for d = 1:n_d
        delta = delta_values(d);

        % 测试需求生成（截断正态）
        test_d = zeros(n_s, n_test);
        for s = 1:n_s
            mu = (1 + delta) * true_mean(s); sigma = true_std(s);
            if sigma < 1e-6
                test_d(s, :) = mu;
            else
                a = (-50 - mu) / sigma; b = (80 - mu) / sigma;
                rng(10000 + d*100 + s);
                test_d(s, :) = mu + sigma * truncnorm_rnd(a, b, n_test);
            end
        end

        % 需求分布统计
        ds = struct('delta', delta, ...
                    'overall_mean', mean(test_d(:)), 'overall_std', std(test_d(:)), ...
                    'per_station_mean', mean(test_d, 2), 'per_station_std', std(test_d, 0, 2), ...
                    'min_demand', min(test_d(:)), 'max_demand', max(test_d(:)), ...
                    'median_demand', median(test_d(:)), 'q25', prctile(test_d(:), 25), ...
                    'q75', prctile(test_d(:), 75), ...
                    'pct_negative', sum(test_d(:)<0)/numel(test_d)*100, ...
                    'pct_exceed_cap', sum(test_d(:)>cap)/numel(test_d)*100);

        % 算法评估（mode3循环结构）
        for a = 1:n_alg
            alg = alg_fields{a}; sol = solutions.(alg);
            fq = [];
            if ~strcmp(alg, 'NS') && isfield(quantities, alg) && ~isempty(fieldnames(quantities.(alg)))
                fq = quantities.(alg);
            end
            [at, tr, ash, dsh, ~] = simulate_synthetic_rolling(cluster_data, sol, base_params, test_d, fq);
            results(d).(alg).avg_total_cost = at;
            results(d).(alg).transport_cost = tr;
            results(d).(alg).avg_shortage_cost = ash;
            results(d).(alg).daily_shortage_costs = dsh;
            if ~isempty(dsh)
                results(d).(alg).worst_day_total_cost = tr + max(dsh);
                sw = sort(dsh, 'descend');
                nw = max(1, ceil(0.05 * length(sw)));
                results(d).(alg).cvar95_total_cost = tr + mean(sw(1:nw));
            else
                results(d).(alg).worst_day_total_cost = tr;
                results(d).(alg).cvar95_total_cost = tr;
            end
        end
        results(d).demand_stats = ds;

        fprintf('  Test progress: %d/%d (Delta=%+.1f), elapsed=%.1fs\n', d, n_total, delta, toc(tt));
    end
    fprintf('[Cluster R-%d] Completed in %.1f s\n\n', n_s, toc(t0));
end

function r = truncnorm_rnd(a, b, n)
    u = rand(n, 1); Fa = normcdf(a); Fb = normcdf(b);
    r = norminv(Fa + u .* (Fb - Fa));
end
