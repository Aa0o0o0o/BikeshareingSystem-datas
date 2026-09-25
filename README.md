# Shared-bike distributionally robust repositioning / 共享单车分布鲁棒再平衡

MATLAB research code for joint vehicle-routing and bike-inventory decisions under uncertain demand. / 需求不确定性下车辆路径与单车库存联合优化的 MATLAB 研究代码。

## Code / 代码

`main_demo.m` is the experiment entry point. It prompts for mode 1 (distribution shift), 2 (baseline), 3 (September/October validation), or 4 (small-instance algorithm comparison). `generate_random_clusters.py` generates synthetic cluster inputs for the MATLAB experiments. / `main_demo.m` 是实验入口，依次提供分布偏移、基线、9—10 月验证和小规模算法对比四种模式；`generate_random_clusters.py` 用于生成 MATLAB 实验的随机簇输入。

## Data / 数据

Download the single [v0.1.0 data ZIP](https://github.com/Aa0o0o0o/BikeshareingSystem-datas/releases/download/v0.1.0/bikeshare-6.18-input-data-v0.1.0.zip) and extract it into the repository root, beside `main_demo.m`. / 下载单个 [v0.1.0 数据附件](https://github.com/Aa0o0o0o/BikeshareingSystem-datas/releases/download/v0.1.0/bikeshare-6.18-input-data-v0.1.0.zip)，解压到 `main_demo.m` 所在的仓库根目录。

The archive preserves 10 input `.mat` files: `May.mat`–`Oct.mat`, `stations.mat`, `Cluster_Results.mat`, `Simulation_Fixed_Data.mat`, and `Random_Clusters.mat`. SHA-256: `B190F48E9E341E72CE7FB43453F6AEEA30E9520569551C80B10D5DC154EF5839`. / 附件保留上述 10 个输入文件的原始内容；生成的实验结果不在附件中。

## Run / 运行

Set the MATLAB current folder to the repository root, then run `main_demo`. Mode 2 asks for Quick or Full; run mode 2 Full before mode 3 because it generates `Baseline_Results.mat`. Modes 1 and 4 use `Random_Clusters.mat`. / 将 MATLAB 当前目录设为仓库根目录并运行 `main_demo`。模式 2 可选 Quick 或 Full；模式 3 需要先运行模式 2 Full 生成 `Baseline_Results.mat`。模式 1、4 使用 `Random_Clusters.mat`。

Software requirements are in [DEPENDENCIES.md](DEPENDENCIES.md). The repository contains source code only; generated figures, LaTeX reports, caches, and result files are excluded. / 软件依赖见[依赖说明](DEPENDENCIES.md)。仓库仅保留源码，不收录生成的图片、LaTeX 报告、缓存和结果文件。
