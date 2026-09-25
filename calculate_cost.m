% 多车辆路径总成本（运输+期望缺货+未访问惩罚）
% Input: route -- 含0分隔符的串联路径; xi -- 初始库存
%        mean, std -- 需求分布参数; D -- 距离矩阵
%        qidian -- 车场索引; p, c, C -- 缺货/距离/容量成本
% Output: cost -- 总成本
function cost = calculate_cost(route, xi, mean, std, D, qidian, p, c, C)
    if isempty(qidian)
        error('qidian is empty.');
    end

    idx = find(route == 0);
    n_car = length(idx) + 1;

    if n_car > length(qidian)
        n_car = length(qidian);
        if n_car > 1
            idx = idx(1:n_car-1);
        else
            idx = [];
        end
    end

    cost = 0;
    if n_car == 1 || length(qidian) == 1
        r = [qidian(1), route, qidian(1)];
        [~, c1] = socpcost(r, xi, mean, std, p, C);
        if isempty(c1), c1 = Inf; end
        cost = cost + c1;
    else
        for car = 1:n_car
            if car == 1
                r = route(1:idx(1)-1);
            elseif car == n_car
                r = route(idx(end)+1:end);
            else
                r = route(idx(car-1)+1:idx(car)-1);
            end
            if isempty(r), continue; end
            r = [qidian(car), r, qidian(car)];
            [~, c1] = socpcost(r, xi, mean, std, p, C);
            if isempty(c1), c1 = Inf; end
            cost = cost + c1;
        end
    end

    dis = calculate_distance(route, D, qidian);
    cost = cost + sum(dis * c);

    unvisited = setdiff(1:size(D,1), [route(:)', qidian(:)']);
    for i = 1:length(unvisited)
        s = unvisited(i);
        fai = (mean(s) - xi(s))/2 + 0.5*sqrt(std(s)^2 + (xi(s) - mean(s))^2);
        cost = cost + fai * p;
    end
end
