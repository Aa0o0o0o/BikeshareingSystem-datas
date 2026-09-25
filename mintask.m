% 验证路径是否满足每车最小任务数约束
% Input: current_solution -- 含0分隔符的串联路径; min_task -- 最小任务数
% Output: is_valid -- true/false
function is_valid = mintask(current_solution, min_task)
    is_valid = true;
    z = find(current_solution == 0);
    if isempty(z)
        if length(current_solution) < min_task
            is_valid = false;
        end
    else
        if z(1) <= min_task || z(end) > length(current_solution)-min_task
            is_valid = false;
        else
            for j = 1:length(z)-1
                if z(j+1) - z(j) - 1 < min_task
                    is_valid = false;
                    break;
                end
            end
        end
    end
end
