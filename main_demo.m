% 公共自行车调度实验主程序：4种运行模式
% Mode 1: 随机簇L2鲁棒性测试（训练→多分布偏移验证）
% Mode 2: 基线参数分析 + 路径可视化 + LaTeX表格
% Mode 3: Sep/Oct真实事件验证（滚动时域每日重置）
% Mode 4: R-9 全算法对比（NS / G-MS / LS-ANS / Gurobi / Exact）
clear; close all; clc;

if ~exist('Cluster_Results.mat', 'file')
    error('Cluster_Results.mat not found. Run station_clustering_gmm.m first.');
end
load('Cluster_Results.mat', 'Cluster_Info');

exp_choice = input('Select mode [1/2/3/4]: ', 's');

%% Mode 1: 随机簇L2鲁棒性测试
if exp_choice == '1'
    if exist('training_comparison_9stations.txt', 'file')
        delete('training_comparison_9stations.txt');
    end
    if exist('l2_robustness_random_clusters.txt', 'file')
        delete('l2_robustness_random_clusters.txt');
    end

    if ~exist('Random_Clusters.mat', 'file')
        error('Random_Clusters.mat not found. Run generate_random_clusters.py first.');
    end
    load('Random_Clusters.mat', 'Fixed_Data');
    n_rand = length(Fixed_Data);
    cluster_sizes = [9, 15, 30, 50];
    cluster_labels = arrayfun(@(x) sprintf('R-%d', x), cluster_sizes, 'UniformOutput', false);

    base_params = struct('p', 5, 'c', 0.1, 'C', 25, 'capacity', 30);
    delta_values = [-0.3, -0.2, -0.1, 0, 0.1, 0.2, 0.3];
    n_greedy_values = [0.1, 0.5, 1.5];

    rand_data_list = cell(n_rand, 1);
    for k = 1:n_rand
        fd = Fixed_Data(k);
        n_s = length(fd.lon);
        if n_s <= 15, n_v = 1;
        elseif n_s <= 30, n_v = 2;
        else, n_v = 3; end

        data = struct();
        data.JWD = [fd.lon, fd.lat];
        data.xi = fd.initial_bikes;
        data.mean_demand = fd.mean_demand;
        data.std_demand = fd.std_demand;
        data.n_stations = n_s;
        data.n_vehicles = n_v;
        c_lon = mean(fd.lon); c_lat = mean(fd.lat);
        [~, ord] = sort(sqrt((fd.lon - c_lon).^2 + (fd.lat - c_lat).^2), 'ascend');
        data.qidian = ord(1:n_v);
        data.station_ids = fd.station_ids;
        rand_data_list{k} = data;
    end

    all_results = cell(n_rand, 1);
    ensure_parpool(4);
    parfor k = 1:n_rand
        do_comp = false;  % 9站点训练对比已移至Mode 4
        all_results{k} = run_l2_robustness_test(rand_data_list{k}, base_params, delta_values, ...
            90, 30, n_greedy_values, do_comp);
    end

    % 结果汇总
    fid = fopen('l2_robustness_random_clusters.txt', 'w');
    fprintf(fid, 'L2 Robustness Test - Random Clusters\n');
    fprintf(fid, '%-8s %-6s %-16s %10s %10s %10s\n', 'Cluster', 'Delta', 'Algorithm', 'AvgCost', 'WorstDay', 'Worst5%%Avg');
    alg_fields = {'NS', 'GMS_n1', 'GMS_n5', 'GMS_n15', 'LS_ANS', 'Exact'};
    alg_disp = {'NS', 'G-MS(0.1)', 'G-MS(0.5)', 'G-MS(1.5)', 'LS-ANS', 'Exact'};
    for k = 1:n_rand
        for d = 1:length(delta_values)
            for a = 1:length(alg_fields)
                if isfield(all_results{k}(d), alg_fields{a})
                    res = all_results{k}(d).(alg_fields{a});
                    fprintf(fid, '%-8s %-6.2f %-16s %10.2f %10.2f %10.2f\n', ...
                        cluster_labels{k}, delta_values(d), alg_disp{a}, ...
                        res.avg_total_cost, res.worst_day_total_cost, res.cvar95_total_cost);
                end
            end
        end
    end

    fprintf(fid, '\n\n=== Demand Distribution Analysis ===\n');
    fprintf(fid, '%-8s %-6s %10s %10s %10s %10s %10s %10s %10s %10s %10s\n', ...
        'Cluster', 'Delta', 'Mean', 'Std', 'Min', 'Max', 'Median', 'Q25', 'Q75', 'PctNeg', 'PctCap');
    for k = 1:n_rand
        for d = 1:length(delta_values)
            if isfield(all_results{k}(d), 'demand_stats')
                ds = all_results{k}(d).demand_stats;
                fprintf(fid, '%-8s %-6.2f %10.2f %10.2f %10.2f %10.2f %10.2f %10.2f %10.2f %10.2f %10.2f\n', ...
                    cluster_labels{k}, delta_values(d), ...
                    ds.overall_mean, ds.overall_std, ds.min_demand, ds.max_demand, ...
                    ds.median_demand, ds.q25, ds.q75, ds.pct_negative, ds.pct_exceed_cap);
            end
        end
    end
    fclose(fid);

    % LS-ANS路径可视化
    T = 10;
    for k = 1:n_rand
        data = rand_data_list{k}; label = cluster_labels{k};
        best_gs = []; best_gc = inf;
        for i = 1:length(n_greedy_values)
            [gs, gc] = Greedy_MeanStd_solver(data.JWD, data.xi, data.mean_demand, data.std_demand, ...
                data.qidian, base_params.p, base_params.c, base_params.C, n_greedy_values(i), struct('verbose', false));
            if gc < best_gc, best_gc = gc; best_gs = gs; end
        end
        opts = struct('num_iterations', 300, 'localsearch_iterations', 10, 'no_improve_max', 50, 'verbose', false);
        if ~isempty(best_gs), opts.initial_solution = best_gs; end
        [ls_sol, ~, ~] = LS_ANS_solver(data.JWD, data.xi, data.mean_demand, data.std_demand, ...
            data.qidian, base_params.p, base_params.c, base_params.C, T, opts);
        qty = compute_quantities(ls_sol, data, base_params.p, base_params.C);
        plot_cluster_route_scientific(data, ls_sol, qty, label, base_params.p, base_params.c, base_params.C);
        saveas(gcf, sprintf('Route_Visualization_%s_LS_ANS_Mode1.png', strrep(label, '-', '_')));
        close(gcf);
    end
end

%% Mode 2: 基线参数分析
if exp_choice == '2'
    diary('Log.txt');

    if exist('Simulation_Fixed_Data.mat', 'file')
        load('Simulation_Fixed_Data.mat', 'Fixed_Data');
    else
        Fixed_Data = struct(); rng(42); cap = 30;
        for k = 1:Cluster_Info.optimal_K
            stats = Cluster_Info.Cluster_Stats(k);
            n_s = stats.n_stations;
            Fixed_Data(k).type = 'original';
            Fixed_Data(k).cluster_id = k;
            Fixed_Data(k).lon = stats.lon;
            Fixed_Data(k).lat = stats.lat;
            Fixed_Data(k).mean_demand = stats.demand_mean;
            Fixed_Data(k).std_demand = stats.demand_std;
            Fixed_Data(k).initial_bikes = randi([0, cap], n_s, 1);
            Fixed_Data(k).station_ids = [];
            if isfield(Cluster_Info, 'station_ids')
                Fixed_Data(k).station_ids = Cluster_Info.station_ids(stats.station_indices);
            end
        end
        save('Simulation_Fixed_Data.mat', 'Fixed_Data');
    end

    n_clusters = Cluster_Info.optimal_K;
    cluster_data_list = cell(n_clusters, 1);
    cluster_labels = cell(n_clusters, 1);
    for k = 1:n_clusters
        fd = Fixed_Data(k); stats = Cluster_Info.Cluster_Stats(k);
        data = struct();
        data.JWD = [fd.lon, fd.lat];
        data.xi = fd.initial_bikes;
        data.mean_demand = fd.mean_demand;
        data.std_demand = fd.std_demand;
        data.n_vehicles = stats.n_vehicles;
        data.n_stations = stats.n_stations;
        n_v = data.n_vehicles;
        dist = sqrt((fd.lon - stats.hub_lon).^2 + (fd.lat - stats.hub_lat).^2);
        [~, ord] = sort(dist, 'ascend');
        data.qidian = ord(1:n_v);
        data.station_ids = fd.station_ids;
        if k == 5
            data.n_vehicles = 4; data.qidian = ord(1:4);
        end
        cluster_data_list{k} = data;
        cluster_labels{k} = sprintf('Original-%d', k);
    end

    scope = input('Select scope [1=Quick/2=Full]: ', 's');
    if scope == '1'
        run_idx = 1:min(3, n_clusters); quick = true;
    else
        run_idx = 1:n_clusters; quick = false;
    end

    p_base = 5; c_base = 0.1; Q_base = 25; T = 10;
    n_values = [0.1, 0.5, 1.5];

    all_solutions = cell(n_clusters, 1);
    all_costs = cell(n_clusters, 1);
    all_quantities = cell(n_clusters, 1);

    tic; ensure_parpool(4);
    n_run = length(run_idx);
    run_sol = cell(n_run, 1); run_cost = cell(n_run, 1); run_qty = cell(n_run, 1);
    parfor ii = 1:n_run
        k = run_idx(ii); data = cluster_data_list{k};
        solutions = struct(); costs = struct(); quantities = struct();

        costs.NS = calculate_NS_cost(data, p_base);
        solutions.NS = []; quantities.NS = [];

        best_gc = inf; best_gs = [];
        for i = 1:length(n_values)
            np = n_values(i); nk = sprintf('n%.0f', np*10);
            [gs, gc] = Greedy_MeanStd_solver(data.JWD, data.xi, data.mean_demand, data.std_demand, ...
                data.qidian, p_base, c_base, Q_base, np, struct('verbose', false));
            solutions.(['GMS_' nk]) = gs; costs.(['GMS_' nk]) = gc;
            quantities.(['GMS_' nk]) = compute_quantities(gs, data, p_base, Q_base);
            if gc < best_gc, best_gc = gc; best_gs = gs; end
        end

        opts = struct('num_iterations', 300, 'localsearch_iterations', 10, 'no_improve_max', 50, 'verbose', false);
        if ~isempty(best_gs), opts.initial_solution = best_gs; end
        [ls_sol, ls_cost, ~] = LS_ANS_solver(data.JWD, data.xi, data.mean_demand, data.std_demand, ...
            data.qidian, p_base, c_base, Q_base, T, opts);
        quantities.LS_ANS = compute_quantities(ls_sol, data, p_base, Q_base);
        solutions.LS_ANS = ls_sol; costs.LS_ANS = ls_cost;

        run_sol{ii} = solutions; run_cost{ii} = costs; run_qty{ii} = quantities;
        plot_cluster_route_scientific(data, ls_sol, quantities.LS_ANS, cluster_labels{k}, p_base, c_base, Q_base);
    end

    for ii = 1:n_run
        k = run_idx(ii);
        all_solutions{k} = run_sol{ii}; all_costs{k} = run_cost{ii}; all_quantities{k} = run_qty{ii};
    end

    fprintf('Baseline analysis completed in %.1f s\n', toc);

    if quick
        save('Baseline_Results_Quick.mat', 'all_solutions', 'all_costs', 'all_quantities', ...
             'cluster_data_list', 'cluster_labels', 'p_base', 'c_base', 'Q_base', 'n_values', 'run_idx');
    else
        save('Baseline_Results.mat', 'all_solutions', 'all_costs', 'all_quantities', ...
             'cluster_data_list', 'cluster_labels', 'p_base', 'c_base', 'Q_base', 'n_values');
        save('Experiment_Results.mat', 'cluster_data_list', 'all_solutions', 'cluster_labels');
    end
    generate_baseline_tex(all_costs, cluster_labels, n_values, p_base, c_base, Q_base, n_clusters, run_idx);
    diary off;
end

%% Mode 3: Sep/Oct真实事件验证
if exp_choice == '3'
    if ~exist('Baseline_Results.mat', 'file')
        error('Baseline_Results.mat not found. Run Mode 2 (full) first.');
    end
    load('Baseline_Results.mat', 'cluster_data_list', 'all_solutions', 'cluster_labels', 'all_quantities');
    n_clusters = length(cluster_data_list);

    load('Simulation_Fixed_Data.mat', 'Fixed_Data');
    for k = 1:n_clusters
        if length(Fixed_Data(k).initial_bikes) == cluster_data_list{k}.n_stations
            cluster_data_list{k}.xi = Fixed_Data(k).initial_bikes;
        else
            error('Fixed data mismatch for cluster %d', k);
        end
    end

    load('Sep.mat', 'Station_start_Sep', 'Station_end_Sep', 'Time_start_Sep', 'Time_end_Sep');
    sep_events = struct('Station_start', Station_start_Sep, 'Station_end', Station_end_Sep, ...
        'Time_start', Time_start_Sep, 'Time_end', Time_end_Sep);
    load('Oct.mat', 'Station_start_Oct', 'Station_end_Oct', 'Time_start_Oct', 'Time_end_Oct');
    oct_events = struct('Station_start', Station_start_Oct, 'Station_end', Station_end_Oct, ...
        'Time_start', Time_start_Oct, 'Time_end', Time_end_Oct);

    base_params = struct('p', 5, 'c', 0.1, 'C', 25, 'capacity', 30);
    alg_names = {'NS', 'GMS_n1', 'GMS_n5', 'GMS_n15', 'LS_ANS'};
    alg_labels = {'NS', 'G-MS(n=0.1)', 'G-MS(n=0.5)', 'G-MS(n=1.5)', 'LS-ANS'};
    months = {'Sep', 'Oct'}; month_events = {sep_events, oct_events};

    old_files = {'validation_sep.mat', 'validation_oct.mat', ...
        'empirical_performance_sep.txt', 'empirical_performance_oct.txt', ...
        'dro_performance_sep.txt', 'dro_performance_oct.txt'};
    for f = 1:length(old_files)
        if exist(old_files{f}, 'file'), delete(old_files{f}); end
    end

    all_month_results = cell(2, 1);
    for m = 1:2
        month_name = months{m}; events = month_events{m};
        month_res_cell = cell(n_clusters, 1);
        ensure_parpool(4);
        parfor k = 1:n_clusters
            if isempty(all_solutions{k}), continue; end
            data = cluster_data_list{k};
            solutions = all_solutions{k}; quantities = all_quantities{k};
            cluster_res = struct();
            for a = 1:length(alg_names)
                alg = alg_names{a}; sol = solutions.(alg);
                fq = [];
                if ~strcmp(alg, 'NS') && isfield(quantities, alg) && ~isempty(fieldnames(quantities.(alg)))
                    fq = quantities.(alg);
                end
                [at, tr, ash, dsh, ~] = rolling_horizon_simulation(data, sol, base_params, events, fq);
                if ~isempty(dsh)
                    wd = tr + max(dsh); sw = sort(dsh, 'descend');
                    nw = max(1, ceil(0.05 * length(sw))); cv = tr + mean(sw(1:nw));
                else
                    wd = tr; cv = tr;
                end
                cluster_res.(alg) = struct('transport_cost', tr, 'avg_shortage_cost', ash, ...
                    'avg_total_cost', at, 'worst_day_total_cost', wd, 'cvar95_total_cost', cv);
            end
            month_res_cell{k} = cluster_res;
        end

        month_res = repmat(struct(), n_clusters, 1);
        for k = 1:n_clusters
            if isempty(month_res_cell{k}), continue; end
            for a = 1:length(alg_names)
                month_res(k).(alg_names{a}) = month_res_cell{k}.(alg_names{a});
            end
        end
        all_month_results{m} = month_res;
        eval(sprintf('%s_results = month_res;', lower(month_name)));
        save(sprintf('validation_%s.mat', lower(month_name)), ...
             sprintf('%s_results', lower(month_name)), 'cluster_labels', 'alg_names', 'base_params');
    end

    for m = 1:2
        month_name = months{m}; res = all_month_results{m};
        fid = fopen(sprintf('%s_results.txt', lower(month_name)), 'w');
        fprintf(fid, '%s Validation Results\n', month_name);
        fprintf(fid, '%-12s %-15s %10s %12s %12s\n', 'Cluster', 'Algorithm', 'Transport', 'AvgShortage', 'AvgTotal');
        for k = 1:n_clusters
            if isempty(all_solutions{k}), continue; end
            for a = 1:length(alg_names)
                fprintf(fid, '%-12s %-15s %10.2f %12.2f %12.2f\n', ...
                    cluster_labels{k}, alg_labels{a}, ...
                    res(k).(alg_names{a}).transport_cost, ...
                    res(k).(alg_names{a}).avg_shortage_cost, ...
                    res(k).(alg_names{a}).avg_total_cost);
            end
        end
        fprintf(fid, '\n%-12s %-15s %12s %12s\n', 'Cluster', 'Algorithm', 'WorstDay', 'CVaR95');
        for k = 1:n_clusters
            if isempty(all_solutions{k}), continue; end
            for a = 1:length(alg_names)
                fprintf(fid, '%-12s %-15s %12.2f %12.2f\n', ...
                    cluster_labels{k}, alg_labels{a}, ...
                    res(k).(alg_names{a}).worst_day_total_cost, ...
                    res(k).(alg_names{a}).cvar95_total_cost);
            end
        end
        fclose(fid);
    end

    sep_res = all_month_results{1}; oct_res = all_month_results{2};
    fprintf('%-12s %-15s %6s %12s %12s %12s\n', 'Cluster', 'Algorithm', 'Month', 'Transport', 'AvgShort', 'AvgTotal');
    for k = 1:n_clusters
        if isempty(all_solutions{k}), continue; end
        for a = 1:length(alg_names)
            fprintf('%-12s %-15s %6s %12.2f %12.2f %12.2f\n', ...
                cluster_labels{k}, alg_labels{a}, 'Sep', ...
                sep_res(k).(alg_names{a}).transport_cost, ...
                sep_res(k).(alg_names{a}).avg_shortage_cost, ...
                sep_res(k).(alg_names{a}).avg_total_cost);
            fprintf('%-12s %-15s %6s %12.2f %12.2f %12.2f\n', ...
                '', '', 'Oct', ...
                oct_res(k).(alg_names{a}).transport_cost, ...
                oct_res(k).(alg_names{a}).avg_shortage_cost, ...
                oct_res(k).(alg_names{a}).avg_total_cost);
        end
    end
    fprintf('%-12s %-15s %6s %12s %12s\n', 'Cluster', 'Algorithm', 'Month', 'WorstDay', 'CVaR95');
    for k = 1:n_clusters
        if isempty(all_solutions{k}), continue; end
        for a = 1:length(alg_names)
            fprintf('%-12s %-15s %6s %12.2f %12.2f\n', ...
                cluster_labels{k}, alg_labels{a}, 'Sep', ...
                sep_res(k).(alg_names{a}).worst_day_total_cost, ...
                sep_res(k).(alg_names{a}).cvar95_total_cost);
            fprintf('%-12s %-15s %6s %12.2f %12.2f\n', ...
                '', '', 'Oct', ...
                oct_res(k).(alg_names{a}).worst_day_total_cost, ...
                oct_res(k).(alg_names{a}).cvar95_total_cost);
        end
    end
end

%% Mode 4: R-9 全算法对比（NS / G-MS / LS-ANS / Gurobi / Exact）
if exp_choice == '4'

    if exist('mode4_exact_comparison.txt', 'file')
        delete('mode4_exact_comparison.txt');
    end

    if ~exist('Random_Clusters.mat', 'file')
        error('Random_Clusters.mat not found. Run generate_random_clusters.py first.');
    end
    load('Random_Clusters.mat', 'Fixed_Data');
    fd = Fixed_Data(1); % R-9 是第一个簇
    n_s = length(fd.lon);

    % 构建 data 结构体
    data = struct();
    data.JWD = [fd.lon, fd.lat];
    data.xi = fd.initial_bikes;
    data.mean_demand = fd.mean_demand;
    data.std_demand = fd.std_demand;
    data.n_stations = n_s;
    data.n_vehicles = 1;
    c_lon = mean(fd.lon); c_lat = mean(fd.lat);
    [~, ord] = sort(sqrt((fd.lon - c_lon).^2 + (fd.lat - c_lat).^2), 'ascend');
    data.qidian = ord(1:1);
    data.station_ids = fd.station_ids;

    % 基础参数
    p = 5; c_val = 0.1; C = 25; n_train = 90;

    % 距离矩阵
    JWD = data.JWD; xi = data.xi; qidian = data.qidian;
    D = zeros(n_s);
    for i = 1:n_s
        for j = 1:n_s
            D(i,j) = 111 * sqrt((JWD(i,1)-JWD(j,1))^2 + (JWD(i,2)-JWD(j,2))^2);
        end
    end

    % 生成训练需求（截断正态）
    rng(111);
    train_d = zeros(n_s, n_train);
    for s = 1:n_s
        mu = data.mean_demand(s); sigma = data.std_demand(s);
        if sigma < 1e-6
            train_d(s, :) = mu;
        else
            a = (-50 - mu) / sigma; b = (80 - mu) / sigma;
            Fa = normcdf(a); Fb = normcdf(b);
            train_d(s, :) = mu + sigma * norminv(Fa + rand(1, n_train) .* (Fb - Fa));
        end
    end
    sample_mean = mean(train_d, 2);
    sample_std = std(train_d, 0, 2);

    data_est = struct('JWD', JWD, 'xi', xi, 'mean_demand', sample_mean, ...
                      'std_demand', sample_std, 'qidian', qidian, ...
                      'n_stations', n_s, 'n_vehicles', 1);

    % 运行各算法并计时
    results = struct();

    % NS（解析基线）
    t0 = tic;
    cost_NS = 0;
    for i = 1:n_s
        fai = (sample_mean(i) - xi(i))/2 + 0.5*sqrt(sample_std(i)^2 + (xi(i) - sample_mean(i))^2);
        cost_NS = cost_NS + fai * p;
    end
    results.NS = struct('cost', cost_NS, 'time', toc(t0));

    % G-MS 三个参数 (n=0.1, 0.5, 1.5)
    n_greedy_values = [0.1, 0.5, 1.5];
    best_gc = inf; best_gs = [];
    for i = 1:length(n_greedy_values)
        np = n_greedy_values(i); nk = sprintf('n%.0f', np*10);
        t0 = tic;
        [gs, gc] = Greedy_MeanStd_solver(JWD, xi, sample_mean, sample_std, ...
            qidian, p, c_val, C, np, struct('verbose', false));
        t_elapsed = toc(t0);
        results.(['GMS_' nk]) = struct('cost', gc, 'time', t_elapsed, 'route', gs);
        if gc < best_gc, best_gc = gc; best_gs = gs; end
    end

    % LS-ANS（以大邻域搜索优化）
    T = 10;
    t0 = tic;
    opts = struct('num_iterations', 300, 'localsearch_iterations', 10, 'no_improve_max', 50, 'verbose', false);
    if ~isempty(best_gs), opts.initial_solution = best_gs; end
    [ls_sol, ls_cost, ~] = LS_ANS_solver(JWD, xi, sample_mean, sample_std, ...
        qidian, p, c_val, C, T, opts);
    results.LS_ANS = struct('cost', ls_cost, 'time', toc(t0), 'route', ls_sol);

    % Gurobi（PCTSP 路径规划 + SOCP 精确评估）
    t0 = tic;
    [gr_sol, gr_cost, gr_time] = gurobi_pctsp_solver(JWD, xi, sample_mean, sample_std, ...
        qidian, p, c_val, C, struct('verbose', true));
    results.Gurobi = struct('cost', gr_cost, 'time', toc(t0), 'solver_time', gr_time, 'route', gr_sol);

    % Exact（暴力枚举）
    t0 = tic;
    [es, ec, exact_time, nodes] = Exact_solver_brute(JWD, xi, sample_mean, sample_std, qidian, p, c_val, C, struct('verbose', true));
    toc_exact = toc(t0);
    results.Exact = struct('cost', ec, 'time', toc_exact, 'solver_time', exact_time, 'nodes', nodes, 'route', es);

    % 输出到文件
    fid = fopen('mode4_exact_comparison.txt', 'w');
    fprintf(fid, 'Mode 4: R-9 Comprehensive Solver Comparison (Training Phase)\n');
    fprintf(fid, 'Parameters: p=%d, c=%.2f, C=%d, n_train=%d, n_stations=%d\n\n', p, c_val, C, n_train, n_s);
    fprintf(fid, '%-22s %12s %12s\n', 'Algorithm', 'TotalCost', 'Time(s)');
    fprintf(fid, '%-22s %12.2f %12.4f\n', 'NS', results.NS.cost, results.NS.time);
    fprintf(fid, '%-22s %12.2f %12.4f\n', 'G-MS (n=0.1)', results.GMS_n1.cost, results.GMS_n1.time);
    fprintf(fid, '%-22s %12.2f %12.4f\n', 'G-MS (n=0.5)', results.GMS_n5.cost, results.GMS_n5.time);
    fprintf(fid, '%-22s %12.2f %12.4f\n', 'G-MS (n=1.5)', results.GMS_n15.cost, results.GMS_n15.time);
    fprintf(fid, '%-22s %12.2f %12.4f\n', 'LS-ANS', results.LS_ANS.cost, results.LS_ANS.time);
    fprintf(fid, '%-22s %12.2f %12.4f\n', 'Gurobi (PCTSP+SOCP)', results.Gurobi.cost, results.Gurobi.time);
    fprintf(fid, '%-22s %12.2f %12.4f\n', 'Exact (Brute)', results.Exact.cost, results.Exact.time);
    fclose(fid);

    % 屏幕输出
    fprintf('\n=== Mode 4: R-9 Comprehensive Solver Comparison ===\n');
    fprintf('%-22s %12s %12s\n', 'Algorithm', 'TotalCost', 'Time(s)');
    fprintf('%-22s %12.2f %12.4f\n', 'NS', results.NS.cost, results.NS.time);
    fprintf('%-22s %12.2f %12.4f\n', 'G-MS (n=0.1)', results.GMS_n1.cost, results.GMS_n1.time);
    fprintf('%-22s %12.2f %12.4f\n', 'G-MS (n=0.5)', results.GMS_n5.cost, results.GMS_n5.time);
    fprintf('%-22s %12.2f %12.4f\n', 'G-MS (n=1.5)', results.GMS_n15.cost, results.GMS_n15.time);
    fprintf('%-22s %12.2f %12.4f\n', 'LS-ANS', results.LS_ANS.cost, results.LS_ANS.time);
    fprintf('%-22s %12.2f %12.4f\n', 'Gurobi (PCTSP+SOCP)', results.Gurobi.cost, results.Gurobi.time);
    fprintf('%-22s %12.2f %12.4f\n', 'Exact (Brute)', results.Exact.cost, results.Exact.time);
    fprintf('Exact solver evaluated %d nodes, internal time=%.4fs\n', results.Exact.nodes, results.Exact.solver_time);
    if isfinite(results.Gurobi.cost)
        fprintf('Gurobi route: [%s], internal time=%.4fs\n', mat2str(results.Gurobi.route), results.Gurobi.solver_time);
    end
    fprintf('\nResults saved to mode4_exact_comparison.txt\n');
end

%% 辅助函数：NS基线成本
function cost = calculate_NS_cost(data, p)
    n = length(data.xi); cost = 0;
    for i = 1:n
        fai = (data.mean_demand(i) - data.xi(i))/2 + ...
              0.5*sqrt(data.std_demand(i)^2 + (data.xi(i) - data.mean_demand(i))^2);
        cost = cost + fai * p;
    end
end

%% 辅助函数：科学路径可视化
function plot_cluster_route_scientific(data, sol, qty_struct, label, p, c, Q)
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
                if qv > 0, qs = sprintf('+%.0f', qv); qc = c_drop; else, qs = sprintf('%.0f', qv); qc = c_pick; end
                text(JWD(i,1), JWD(i,2) - off_q, qs, 'FontSize', fs_q, ...
                    'FontWeight', 'bold', 'Color', qc, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
            end
        end
    end

    xlabel('Longitude', 'FontSize', 14, 'FontName', 'Arial', 'Color', c_txt, 'Interpreter', 'latex');
    ylabel('Latitude', 'FontSize', 14, 'FontName', 'Arial', 'Color', c_txt, 'Interpreter', 'latex');
    title(sprintf('%s: LS-ANS Route ($p$=%.0f, $\\kappa$=%.1f, $Q$=%d)', label, p, c, Q), ...
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

    print(fig, sprintf('Route_Visualization_%s_LS_ANS.png', strrep(label, '-', '_')), '-dpng', '-r400');
    close(fig);
end

%% 辅助函数：生成LaTeX表格
function generate_baseline_tex(all_costs, cluster_labels, n_values, p, c, Q, n_clusters, run_idx)
    if nargin < 8 || isempty(run_idx), run_idx = 1:n_clusters; end
    if length(run_idx) < n_clusters
        fname = 'experiment_results_quick.tex';
    else
        fname = 'experiment_results.tex';
    end
    fid = fopen(fname, 'w');
    for k = run_idx
        costs = all_costs{k}; label = cluster_labels{k}; baseline = costs.LS_ANS;
        fprintf(fid, '\\begin{table}[htbp]\n\\centering\n');
        fprintf(fid, '\\caption{Baseline Results for %s ($p$=%d, $\\kappa$=%.1f, $Q$=%d)}\n', label, p, c, Q);
        fprintf(fid, '\\label{tab:%s_baseline}\n', lower(strrep(label, '-', '')));
        fprintf(fid, '\\begin{tabular}{lcc}\n\\toprule\n');
        fprintf(fid, 'Algorithm & $TC$ & Gap (\\%%) \\\n\\midrule\n');
        for i = 1:length(n_values)
            nk = sprintf('n%.0f', n_values(i)*10);
            g_cost = costs.(['GMS_' nk]);
            fprintf(fid, 'G-n%s & %.2f & %.2f \\\n', nk(2:end), g_cost, 100*(g_cost-baseline)/baseline);
        end
        fprintf(fid, 'LS-ANS & %.2f & -- \\\n', costs.LS_ANS);
        fprintf(fid, 'NS & %.2f & %.2f \\\n', costs.NS, 100*(costs.NS-baseline)/baseline);
        fprintf(fid, '\\bottomrule\n\\end{tabular}\n\\end{table}\n\n');
    end
    fclose(fid);
end

%% 辅助函数：确保进程池并行环境
function ensure_parpool(min_workers)
    p = gcp('nocreate');
    if ~isempty(p) && p.NumWorkers >= min_workers
        is_thread = false;
        try, is_thread = strcmpi(p.Type, 'ThreadPool'); catch, try, is_thread = strcmpi(p.Cluster.Type, 'ThreadPool'); catch, end, end
        if ~is_thread, return; end
        delete(p);
    end
    delete(gcp('nocreate'));
    try
        parpool('Processes', min(min_workers, feature('numcores')));
    catch ME
        warning('Failed to start parallel pool: %s. Falling back to sequential.', ME.message);
    end
end


