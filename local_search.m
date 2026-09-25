% 局部搜索：三种邻域结构（Swap/Insert/Reverse），首改进策略
% Input: repaired_solution -- 当前解; operator -- 1=Swap, 2=Insert, 3=Reverse
%        xi, mean, std -- 库存与需求参数; distance_matrix -- 距离矩阵
%        qidian -- 车场; p, c -- 成本参数; maxDistance -- 最大行驶距离
%        min_task -- 最小任务数; C -- 车辆容量; localsearch_iterations -- 迭代次数
% Output: bestcost_nb -- 改进后成本; bestroute_nb -- 改进后解
function [bestcost_nb, bestroute_nb] = local_search(repaired_solution, operator, xi, mean, std, distance_matrix, qidian, p, c, maxDistance, min_task, C, localsearch_iterations)
    if operator == 1
        [bestcost_nb, bestroute_nb] = swap_neighborhood(repaired_solution, xi, mean, std, distance_matrix, qidian, p, c, maxDistance, C, localsearch_iterations);
    elseif operator == 2
        [bestcost_nb, bestroute_nb] = insert_neighborhood(repaired_solution, xi, mean, std, distance_matrix, qidian, p, c, maxDistance, min_task, C, localsearch_iterations);
    elseif operator == 3
        [bestcost_nb, bestroute_nb] = reverse_neighborhood(repaired_solution, xi, mean, std, distance_matrix, qidian, p, c, maxDistance, C, localsearch_iterations);
    end
end

function [bestcost, cur] = swap_neighborhood(sol, xi, mean, std, D, qidian, p, c, maxDist, C, maxIter)
    cur = sol; bestcost = calculate_cost(cur, xi, mean, std, D, qidian, p, c, C);
    for iter = 1:maxIter
        best = bestcost; best_r = cur;
        nz = find(cur ~= 0);
        for k = 1:length(nz)-1
            for j = k+1:length(nz)
                r = swap(cur, nz(k), nz(j));
                if any(calculate_distance(r, D, qidian) > maxDist), continue; end
                cc = calculate_cost(r, xi, mean, std, D, qidian, p, c, C);
                if cc < best, best = cc; best_r = r; end
            end
        end
        if best < bestcost
            cur = best_r; bestcost = best;
        else
            break;
        end
    end
end

function [bestcost, cur] = insert_neighborhood(sol, xi, mean, std, D, qidian, p, c, maxDist, min_task, C, maxIter)
    cur = sol; bestcost = calculate_cost(cur, xi, mean, std, D, qidian, p, c, C);
    for iter = 1:maxIter
        best = bestcost; best_r = cur;
        nz = find(cur ~= 0);
        for k = nz
            for pos = 1:length(cur)+1
                if pos == k || pos == k+1, continue; end
                r = insert(cur, k, pos);
                if any(calculate_distance(r, D, qidian) > maxDist) || ~mintask(r, min_task)
                    continue;
                end
                cc = calculate_cost(r, xi, mean, std, D, qidian, p, c, C);
                if cc < best, best = cc; best_r = r; end
            end
        end
        if best < bestcost
            cur = best_r; bestcost = best;
        else
            break;
        end
    end
end

function [bestcost, cur] = reverse_neighborhood(sol, xi, mean, std, D, qidian, p, c, maxDist, C, maxIter)
    cur = sol; bestcost = calculate_cost(cur, xi, mean, std, D, qidian, p, c, C);
    for iter = 1:maxIter
        best = bestcost; best_r = cur;
        z = find(cur == 0);
        n_car = length(z) + 1;
        if n_car == 1
            for k = 1:length(cur)-1
                for j = k+1:length(cur)
                    r = reverse(cur, k, j);
                    if any(calculate_distance(r, D, qidian) > maxDist), continue; end
                    cc = calculate_cost(r, xi, mean, std, D, qidian, p, c, C);
                    if cc < best, best = cc; best_r = r; end
                end
            end
        else
            for car = 1:n_car
                if car == 1
                    seg = 1:z(1)-1;
                elseif car == n_car
                    seg = z(end)+1:length(cur);
                else
                    seg = z(car-1)+1:z(car)-1;
                end
                for k = 1:length(seg)-1
                    for j = k+1:length(seg)
                        r = reverse(cur, seg(k), seg(j));
                        if any(calculate_distance(r, D, qidian) > maxDist), continue; end
                        cc = calculate_cost(r, xi, mean, std, D, qidian, p, c, C);
                        if cc < best, best = cc; best_r = r; end
                    end
                end
            end
        end
        if best < bestcost
            cur = best_r; bestcost = best;
        else
            break;
        end
    end
end
