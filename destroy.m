% LNS破坏算子：随机移除或最差移除站点，保证每车最小任务数
% Input: current_solution -- 当前解; destroy_operator -- 1=随机, 2=最差
%        n_vehicles -- 车辆数; score -- 站点需求评分; min_task -- 最小任务数
% Output: destroyed_solution -- 破坏后的解
function destroyed_solution = destroy(current_solution, destroy_operator, n_vehicles, score, min_task)
    destroyed_solution = current_solution;
    if isempty(current_solution) || length(current_solution) <= (n_vehicles-1)
        return;
    end

    max_remove = length(current_solution) - (n_vehicles-1);
    if max_remove <= 0, return; end
    n_remove = randi(max_remove);
    temp = current_solution;

    if destroy_operator == 1
        for i = 1:n_remove
            nonzero_idx = find(temp ~= 0);
            if isempty(nonzero_idx), break; end
            ridx = nonzero_idx(randi(length(nonzero_idx)));
            temp(ridx) = [];
            if mintask(temp, min_task)
                destroyed_solution = temp;
            else
                temp = destroyed_solution;
                break;
            end
        end
    elseif destroy_operator == 2
        for i = 1:n_remove
            elems = temp(temp ~= 0);
            if isempty(elems), break; end
            [~, mi] = min(score(elems));
            s = elems(mi);
            sidx = find(temp == s, 1);
            temp(sidx) = [];
            if mintask(temp, min_task)
                destroyed_solution = temp;
            else
                temp = destroyed_solution;
                break;
            end
        end
    end
end
