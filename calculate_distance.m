% 解析多车路径并计算各车辆行驶距离
% Input: route -- 含0分隔符的串联路径; D -- 距离矩阵; qidian -- 车场索引
% Output: dis -- [n_car×1] 各车行驶距离
function dis = calculate_distance(route, D, qidian)
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

    dis = zeros(n_car, 1);
    if n_car == 1
        r = [qidian(1), route];
        for i = 1:length(r)-1
            dis = dis + D(r(i), r(i+1));
        end
        dis = dis + D(r(end), r(1));
    else
        for car = 1:n_car
            if car == 1
                r = route(1:idx(1)-1);
            elseif car == n_car
                r = route(idx(end)+1:end);
            else
                r = route(idx(car-1)+1:idx(car)-1);
            end
            r = [qidian(car), r];
            for i = 1:length(r)-1
                dis(car) = dis(car) + D(r(i), r(i+1));
            end
            dis(car) = dis(car) + D(r(end), qidian(car));
        end
    end
end
