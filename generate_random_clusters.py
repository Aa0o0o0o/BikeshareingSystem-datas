"""Generate random clusters based on real cluster statistics.
Output: Random_Clusters.mat (same structure as Simulation_Fixed_Data.mat).
"""
import numpy as np
import scipy.io as sio
import os

np.random.seed(42)

print("Loading Simulation_Fixed_Data.mat ...")
data = sio.loadmat('Simulation_Fixed_Data.mat')
fixed = data['Fixed_Data'][0, :]

real_stats = []
all_mean_demands = []
all_std_demands = []
all_lons = []
all_lats = []

for i in range(fixed.shape[0]):
    cluster = fixed[i]
    lon = cluster['lon'].flatten()
    lat = cluster['lat'].flatten()
    mean_d = cluster['mean_demand'].flatten()
    std_d = cluster['std_demand'].flatten()
    all_mean_demands.extend(mean_d)
    all_std_demands.extend(std_d)
    all_lons.extend(lon)
    all_lats.extend(lat)
    diam_km = 111 * np.sqrt((np.ptp(lon) * np.cos(np.radians(45.5)))**2 + np.ptp(lat)**2)
    real_stats.append({
        'n': len(lon), 'diam_km': diam_km,
        'mean_mean': np.mean(mean_d), 'mean_std': np.std(mean_d),
        'mean_min': np.min(mean_d), 'mean_max': np.max(mean_d),
        'std_mean': np.mean(std_d), 'cv_mean': np.mean(std_d / (np.abs(mean_d) + 1e-6)),
    })
    print(f"  Original Cluster {i+1} (n={len(lon)}): diam={diam_km:.2f}km, "
          f"mean=[{mean_d.min():.1f},{mean_d.max():.1f}], avg_cv={real_stats[-1]['cv_mean']:.2f}")

all_mean_demands = np.array(all_mean_demands)
all_std_demands = np.array(all_std_demands)
GLOBAL_LON_MIN, GLOBAL_LON_MAX = np.min(all_lons), np.max(all_lons)
GLOBAL_LAT_MIN, GLOBAL_LAT_MAX = np.min(all_lats), np.max(all_lats)
real_cvs = all_std_demands / (np.abs(all_mean_demands) + 1e-6)
print(f"\nGlobal bounds: lon=[{GLOBAL_LON_MIN:.4f},{GLOBAL_LON_MAX:.4f}], "
      f"lat=[{GLOBAL_LAT_MIN:.4f},{GLOBAL_LAT_MAX:.4f}]")
print(f"Global mean range: [{all_mean_demands.min():.1f}, {all_mean_demands.max():.1f}]")
print(f"Global avg CV: {np.mean(real_cvs):.3f}")


def generate_cluster(n_stations, cluster_id):
    rng = np.random.RandomState(42 + cluster_id * 100)
    base_diam_km = 1.5 + 0.12 * n_stations
    sigma_lon = (base_diam_km / 111) / 2.5
    sigma_lat = (base_diam_km / 111) / 2.5

    safe_lon_min = GLOBAL_LON_MIN + 3 * sigma_lon
    safe_lon_max = GLOBAL_LON_MAX - 3 * sigma_lon
    safe_lat_min = GLOBAL_LAT_MIN + 3 * sigma_lat
    safe_lat_max = GLOBAL_LAT_MAX - 3 * sigma_lat

    center_lon = rng.uniform(safe_lon_min, safe_lon_max)
    center_lat = rng.uniform(safe_lat_min, safe_lat_max)

    n_core = int(n_stations * 0.8)
    n_outlier = n_stations - n_core

    lons = np.empty(n_core)
    lats = np.empty(n_core)
    for i in range(n_core):
        while True:
            lon = center_lon + rng.normal(0, sigma_lon)
            lat = center_lat + rng.normal(0, sigma_lat)
            if GLOBAL_LON_MIN <= lon <= GLOBAL_LON_MAX and GLOBAL_LAT_MIN <= lat <= GLOBAL_LAT_MAX:
                lons[i] = lon; lats[i] = lat; break

    if n_outlier > 0:
        outlier_lons = np.empty(n_outlier)
        outlier_lats = np.empty(n_outlier)
        for i in range(n_outlier):
            while True:
                lon = center_lon + rng.normal(0, sigma_lon * 2.5)
                lat = center_lat + rng.normal(0, sigma_lat * 2.5)
                if GLOBAL_LON_MIN <= lon <= GLOBAL_LON_MAX and GLOBAL_LAT_MIN <= lat <= GLOBAL_LAT_MAX:
                    outlier_lons[i] = lon; outlier_lats[i] = lat; break
        lons = np.concatenate([lons, outlier_lons])
        lats = np.concatenate([lats, outlier_lats])

    hist, bin_edges = np.histogram(all_mean_demands, bins=20)
    bin_probs = hist / (hist.sum() + 1e-6)
    chosen_bins = rng.choice(len(bin_probs), size=n_stations, p=bin_probs)
    mean_demands = np.array([rng.uniform(bin_edges[b], bin_edges[b+1]) for b in chosen_bins])
    mean_demands += rng.normal(0, 1.5, n_stations)

    cv_hist, cv_bins = np.histogram(real_cvs, bins=15, range=(0.05, 2.0))
    cv_probs = cv_hist / (cv_hist.sum() + 1e-6)
    chosen_cv_bins = rng.choice(len(cv_probs), size=n_stations, p=cv_probs)
    cvs = np.clip(np.array([rng.uniform(cv_bins[b], cv_bins[b+1]) for b in chosen_cv_bins]), 0.05, 1.5)
    std_demands = np.abs(mean_demands) * cvs

    init_bikes = rng.randint(0, 31, size=n_stations).astype(np.float64)
    station_ids = np.arange(1000 + cluster_id * 100, 1000 + cluster_id * 100 + n_stations, dtype=np.uint16)

    cluster_struct = np.array([(
        np.array(['random'], dtype='<U8'),
        np.array([[cluster_id]], dtype=np.uint8),
        lons.reshape(-1, 1), lats.reshape(-1, 1),
        mean_demands.reshape(-1, 1), std_demands.reshape(-1, 1),
        init_bikes.reshape(-1, 1), station_ids.reshape(-1, 1)
    )], dtype=fixed.dtype)
    return cluster_struct


print("\n" + "=" * 60)
print("Generating 4 random clusters...")
print("=" * 60)

cluster_sizes = [9, 15, 30, 50]
random_clusters = []

if os.path.exists('Random_Clusters.mat'):
    os.remove('Random_Clusters.mat')
    print("Removed old Random_Clusters.mat")

for idx, n in enumerate(cluster_sizes, start=1):
    print(f"  Generating Cluster R-{n} (id={idx}) ...", end=" ")
    c = generate_cluster(n, idx)
    random_clusters.append(c)
    lon = c[0]['lon'].flatten()
    lat = c[0]['lat'].flatten()
    diam = 111 * np.sqrt((np.ptp(lon) * np.cos(np.radians(45.5)))**2 + np.ptp(lat)**2)
    print(f"done. Diam={diam:.2f}km, mean_range=[{c[0]['mean_demand'].min():.1f},{c[0]['mean_demand'].max():.1f}]")

all_random = np.concatenate(random_clusters, axis=0)
sio.savemat('Random_Clusters.mat', {'Fixed_Data': all_random})
print("\nSaved: Random_Clusters.mat")
print("Done!")
