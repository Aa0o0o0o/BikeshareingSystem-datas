function export_cluster_csv(cluster_idx, month_name)
%export_cluster_csv Export one cluster's stations and one month of real trips to CSV.
%   Output goes to python_patent_rewrite/examples/data/ for the Python pipeline.
%   Usage: export_cluster_csv(2, 'May')

if nargin < 1, cluster_idx = 2; end
if nargin < 2, month_name = 'May'; end

out_dir = fullfile('python_patent_rewrite', 'examples', 'data');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

S = load('Simulation_Fixed_Data.mat');
c = S.Fixed_Data(cluster_idx);
ids = c.station_ids(:);

T_sta = table(ids, c.lon(:), c.lat(:), c.initial_bikes(:), ...
    'VariableNames', {'station_id', 'longitude', 'latitude', 'initial_inventory'});
sta_file = fullfile(out_dir, sprintf('cluster%d_stations.csv', cluster_idx));
writetable(T_sta, sta_file);

M = load(sprintf('%s.mat', month_name));
ss = M.(sprintf('Station_start_%s', month_name));
ee = M.(sprintf('Station_end_%s', month_name));
ts = M.(sprintf('Time_start_%s', month_name));
te = M.(sprintf('Time_end_%s', month_name));

mask = ismember(ss, ids) & ismember(ee, ids);
T_trip = table(ss(mask), ee(mask), ts(mask), te(mask), ...
    'VariableNames', {'start_station_id', 'end_station_id', 'start_time', 'end_time'});
T_trip.start_time.Format = 'yyyy-MM-dd''T''HH:mm:ss';
T_trip.end_time.Format = 'yyyy-MM-dd''T''HH:mm:ss';
trip_file = fullfile(out_dir, sprintf('cluster%d_%s_trips.csv', cluster_idx, lower(month_name)));
writetable(T_trip, trip_file);

fprintf('stations -> %s (%d stations)\n', sta_file, height(T_sta));
fprintf('trips    -> %s (%d trips)\n', trip_file, height(T_trip));
end
