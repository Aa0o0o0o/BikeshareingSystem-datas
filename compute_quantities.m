% 解析多车路径并调用SOCP计算装卸量
% Input: sol -- 固定路径解（多车以0分隔）
%        data -- 含xi, mean_demand, std_demand, qidian, n_vehicles的结构体
%        p, C -- SOCP参数
% Output: qty -- 结构体，含vehicle1, vehicle2等字段，每个含stations和quantities
function qty = compute_quantities(sol, data, p, C)
    qty = struct();
    if isempty(sol), return; end
    n_v = data.n_vehicles;
    idx = find(sol == 0);
    for v = 1:n_v
        if n_v == 1
            r = sol;
        else
            if v == 1
                r = sol(1:idx(1)-1);
            elseif v == n_v
                r = sol(idx(end)+1:end);
            else
                r = sol(idx(v-1)+1:idx(v)-1);
            end
        end
        if isempty(r), continue; end
        r_depot = [data.qidian(v), r, data.qidian(v)];
        try
            [x, ~] = socpcost(r_depot, data.xi, data.mean_demand, data.std_demand, p, C);
            qty.(sprintf('vehicle%d', v)).stations = r_depot;
            qty.(sprintf('vehicle%d', v)).quantities = x(1:length(r_depot));
        catch
            qty.(sprintf('vehicle%d', v)).stations = r_depot;
            qty.(sprintf('vehicle%d', v)).quantities = zeros(length(r_depot), 1);
        end
    end
end
