% 构造初始解：优先服务库存偏离均值±1std的站点，按最近邻规则分配车辆
% Input: xi, mean, std -- 库存与需求参数; distance_matrix -- 距离矩阵
%        qidian -- 车场; n_customers -- 站点数
% Output: sol -- 含0分隔符的串联路径
function sol = initial_sol(xi, mean, std, distance_matrix, qidian, n_customers)
    sta = find(xi < mean - std | xi > mean + std);
    sta = setdiff(sta, qidian);
    route = cell(length(qidian), 1);
    pos = qidian;
    while ~isempty(sta)
        mini = Inf;
        for i = 1:length(sta)
            for j = 1:length(pos)
                d = distance_matrix(pos(j), sta(i));
                if d < mini
                    mini = d; car = j; platform = i;
                end
            end
        end
        next = sta(platform);
        pos(car) = next;
        sta(platform) = [];
        route{car} = [route{car}, next];
    end
    sol = [];
    for car = 1:length(qidian)
        if car == length(qidian)
            sol = [sol, route{car}];
        else
            sol = [sol, route{car}, 0];
        end
    end
end
