% 期望缺货成本（NS策略或给定路径）
% Input: sol -- 路径解（空表示NS）; data -- 含xi,mean_demand,std_demand,qidian的结构体
%        D -- 距离矩阵; p, c, C -- 成本参数
% Output: cost -- 总解析成本
function cost = compute_analytical_cost(sol, data, D, p, c, C)
    if isempty(sol)
        n = length(data.xi);
        cost = 0;
        for i = 1:n
            fai = (data.mean_demand(i) - data.xi(i))/2 + ...
                  0.5*sqrt(data.std_demand(i)^2 + (data.xi(i) - data.mean_demand(i))^2);
            cost = cost + fai * p;
        end
    else
        cost = calculate_cost(sol, data.xi, data.mean_demand, data.std_demand, ...
                              D, data.qidian, p, c, C);
    end
end
