% Compute station geographic distance matrix (Haversine approx., 111km/deg)
% Input: 2021_stations.csv (station ID, lat/lon)
% Output: distance.mat (n×n distance matrix in km)

filename = '2021_stations.csv';
S = readtable(filename);

n = height(S);
lat = S.latitude;
lon = S.longitude;

D = zeros(n);
for i = 1:n
    for j = 1:n
        D(i,j) = 111 * (abs(lat(i)-lat(j)) + abs(lon(i)-lon(j)));
    end
end

save('distance.mat', 'D');

figure;
scatter(lat(1:570), lon(1:570), 'filled');
hold on;
scatter(lat(572:end), lon(572:end), 'filled');
xlabel('Latitude'); ylabel('Longitude');
title('Station Distribution');
