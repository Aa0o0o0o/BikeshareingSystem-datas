% LNS修复算子：将未访问站点以随机或贪婪方式插入路径
% Input: destroyed_solution -- 破坏后的解; n_customers -- 站点总数
%        repair_operator -- 1=随机, 2=贪婪; qidian -- 车场; maxDistance -- 最大行驶距离
%        distance_matrix -- 距离矩阵; score -- 站点需求评分
% Output: repaired_solution -- 修复后的解
function repaired_solution = repair(destroyed_solution, n_customers, repair_operator, qidian, maxDistance, distance_matrix, score)
    unvisited = setdiff(1:n_customers, [destroyed_solution(:)', qidian(:)']);
    if isempty(unvisited)
        repaired_solution = destroyed_solution;
        return;
    end
    num_to_insert = randi(length(unvisited));

    if repair_operator == 1
        unvisited = unvisited(randperm(length(unvisited)));
        for i = 1:num_to_insert
            for attempt = 1:100
                pos = randi(length(destroyed_solution) + 1);
                new = [destroyed_solution(1:pos-1), unvisited(i), destroyed_solution(pos:end)];
                if all(calculate_distance(new, distance_matrix, qidian) < maxDistance)
                    destroyed_solution = new;
                    break;
                end
            end
        end
    elseif repair_operator == 2
        [~, ord] = sort(score(unvisited), 'descend');
        unvisited = reshape(unvisited(ord), 1, []);
        for i = 1:num_to_insert
            best_inc = Inf; best_pos = -1;
            for pos = 1:length(destroyed_solution)+1
                new = [destroyed_solution(1:pos-1), unvisited(i), destroyed_solution(pos:end)];
                if all(calculate_distance(new, distance_matrix, qidian) < maxDistance)
                    inc = sum(calculate_distance(new, distance_matrix, qidian)) - ...
                          sum(calculate_distance(destroyed_solution, distance_matrix, qidian));
                    if inc < best_inc
                        best_inc = inc;
                        best_pos = pos;
                    end
                end
            end
            if best_pos ~= -1
                destroyed_solution = [destroyed_solution(1:best_pos-1), unvisited(i), destroyed_solution(best_pos:end)];
            end
        end
    end
    repaired_solution = destroyed_solution;
end
