% 从真实事件数据计算各站点每日净需求的均值与标准差
% Input: cluster_data -- 含station_ids的结构体; events -- 事件结构体
% Output: test_mean, test_std -- [n_stations×1]; daily_net -- [n_stations×n_days]; n_days -- 天数
function [test_mean, test_std, daily_net, n_days] = compute_test_parameters(cluster_data, events)
    station_ids = cluster_data.station_ids;
    n_stations = length(station_ids);

    borrow_days = dateshift(events.Time_start, 'start', 'day');
    return_days = dateshift(events.Time_end, 'start', 'day');

    unique_days = sort(unique([borrow_days(:); return_days(:)]));
    n_days = length(unique_days);

    daily_net = zeros(n_stations, n_days);
    for d = 1:n_days
        day_mask_b = (borrow_days == unique_days(d));
        day_mask_r = (return_days == unique_days(d));
        for s = 1:n_stations
            sid = station_ids(s);
            daily_net(s, d) = sum(events.Station_end(day_mask_r) == sid) ...
                            - sum(events.Station_start(day_mask_b) == sid);
        end
    end

    test_mean = mean(daily_net, 2);
    test_std = std(daily_net, 0, 2);
end
