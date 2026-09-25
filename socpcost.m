% 单路径SOCP：最优取放量与期望缺货成本（coneprog求解器版本）
% Input: route -- 站点序列（含车场首尾）; xi -- 初始库存
%        mean, std_demand -- 需求均值/标准差; p, C -- 缺货成本、车辆容量
% Output: x -- [K×1] 取放量; cost -- 最优成本
function [x, cost] = socpcost(route, xi, mean, std_demand, p, C)
    K = length(route);

    % 二阶锥约束：||[z_i; w_i - v_i]||_2 <= w_i + v_i
    for i = 1:K
        ei_x = zeros(1, K);
        ei_y = zeros(K, 1);
        ei_x(i) = 1;
        ei_y(i) = 1;
        A = zeros(2, 6*K);
        A(1, 2*K+1:3*K) = ei_x;   % z_i
        A(2, 3*K+1:4*K) = ei_x;   % w_i
        A(2, 4*K+1:5*K) = -ei_x;  % -v_i
        d = [zeros(3*K, 1); ei_y; ei_y; zeros(K, 1)];
        if i == 1
            socConstraint = secondordercone(A, zeros(2,1), d, 0);
        else
            socConstraint(i,1) = secondordercone(A, zeros(2,1), d, 0);
        end
    end

    % 目标函数
    f3 = mean(route);
    sigma = std_demand(route);
    f4 = sigma.^2 + f3.^2;
    f = [zeros(K,1); ones(K,1); f3(:); f4(:); zeros(2*K,1)];

    % 不等式约束 A*x <= b
    Aineq = zeros(3*K-2, 6*K);
    for i = 1:K-1
        Aineq(i, 1:i) = 1;
        Aineq(K-1+i, 1:i) = -1;
    end
    for i = 1:K
        ei_x = zeros(1, K);
        ei_x(i) = 1;
        Aineq(2*K-2+i, :) = [zeros(1,K), -ei_x, zeros(1,2*K), ei_x, zeros(1,K)];
    end
    bineq = zeros(3*K-2, 1);
    bineq(K:2*K-2) = C;

    % 等式约束
    Aeq = [ones(1,K), zeros(1,5*K)];
    beq = 0;

    % 变量边界
    lb = [-xi(route); -inf(2*K,1); zeros(K,1); -inf(2*K,1)];
    ub = [(30 - xi(route)); inf(5*K,1)];

    % 求解
    opts = optimoptions('coneprog', 'Display', 'off');
    [sol, cost] = coneprog(double(f), socConstraint, double(Aineq), double(bineq), ...
                           double(Aeq), double(beq), double(lb), double(ub), opts);

    x = sol(1:K);
end
