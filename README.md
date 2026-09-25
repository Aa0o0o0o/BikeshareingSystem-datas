# Shared-bike distributionally robust repositioning / 共享单车分布鲁棒再平衡

Research code for route and inventory decisions under uncertain bike demand. This release contains the original MATLAB 6.18 prototype and an independent Python reconstruction. The Python implementation is a documented reconstruction, **not** a claim of numerical equivalence to the MATLAB prototype.

共享单车需求不确定性下的路径与库存联合优化研究代码。本版本包含原始 MATLAB 6.18 原型和独立的 Python 重构。Python 实现是有明确工程约定的重构，**不代表**与 MATLAB 原型逐数值等价。

## Repository contents / 仓库内容

| Path | Description / 说明 |
| --- | --- |
| `main_demo.m` and root `*.m` | Original MATLAB experiment entry point and functions / 原始 MATLAB 实验入口及函数 |
| `generate_random_clusters.py` | MATLAB experiment data generator; requires NumPy and SciPy / 随机簇数据生成器 |
| `export_cluster_csv.m` | Export a MATLAB cluster to CSV for the Python example / 将 MATLAB 数据导出为 Python 示例 CSV |
| `python_patent_rewrite/src/` | Python reconstruction / Python 重构源码 |
| `python_patent_rewrite/examples/` | Deterministic small case and a small exported real-data case / 确定性小算例及小规模真实数据示例 |
| `python_patent_rewrite/tests/` | Python checks / Python 检查 |
| `python_patent_rewrite/configs/representative_case.json` | Recorded example parameters; the scripts currently set these values in code / 示例参数记录，脚本目前在代码中设置同值参数 |
| `DEPENDENCIES.md` | Software and solver requirements / 软件与求解器依赖 |

The repository excludes generated figures, LaTeX/PDF reports, logs, caches and full `.mat` data. Source `.m` and `.py` files and the two CSV examples are copied without algorithm or parameter edits.

仓库不包含生成的图片、LaTeX/PDF 报告、日志、缓存和完整 `.mat` 数据。`.m`、`.py` 源文件及两份 CSV 示例均保持原样，未修改算法和参数。

## Full input data / 完整输入数据

Download the single [`v0.1.0` data attachment](https://github.com/Aa0o0o0o/BikeshareingSystem-datas/releases/download/v0.1.0/bikeshare-6.18-input-data-v0.1.0.zip) from the [Release page](https://github.com/Aa0o0o0o/BikeshareingSystem-datas/releases/tag/v0.1.0). Extract it **into the repository root**, next to `main_demo.m`; do not place the `.mat` files under `python_patent_rewrite/`. The archive preserves the original filenames and bytes:

从 [v0.1.0 Release 页面](https://github.com/Aa0o0o0o/BikeshareingSystem-datas/releases/tag/v0.1.0) 下载单个数据附件 `bikeshare-6.18-input-data-v0.1.0.zip`，**解压到仓库根目录**，即 `main_demo.m` 所在目录；不要解压到 `python_patent_rewrite/`。压缩包保留原始文件名和字节内容：

```text
May.mat  Jun.mat  Jul.mat  Aug.mat  Sep.mat  Oct.mat
stations.mat  Cluster_Results.mat  Simulation_Fixed_Data.mat  Random_Clusters.mat
```

The six monthly files and `stations.mat` are source data; the remaining three `.mat` files are saved preprocessing inputs used by the experiment scripts. Generated result `.mat` files are intentionally absent. `main_demo.m` mode 3 needs `Baseline_Results.mat`, which mode 2 Full generates locally.

六个月份文件和 `stations.mat` 是源数据；另外三个 `.mat` 是实验脚本使用的预处理输入。生成的结果 `.mat` 文件不在附件内。`main_demo.m` 的模式 3 需要由模式 2 的 Full 运行在本地生成 `Baseline_Results.mat`。

Archive SHA-256 / 附件 SHA-256：`B190F48E9E341E72CE7FB43453F6AEEA30E9520569551C80B10D5DC154EF5839`。

## Quick Python reproduction / Python 小规模复现

Use Python 3.10 or newer. From the repository root:

```powershell
cd python_patent_rewrite
python examples/end_to_end.py
python -m unittest discover -s tests -v
```

The deterministic example needs no downloaded data or third-party Python package. It uses two vehicles, eight stations and generated trip events, with seed `2026`, shortage penalty `5`, transport cost `0.1/km`, station capacity `30`, vehicle capacity `25`, and `80` LS-ANS iterations. It writes reports and a route map under `outputs/`; these outputs are ignored by Git. XeLaTeX is optional for PDF compilation.

使用 Python 3.10 或更新版本，在仓库根目录运行以上命令。确定性小算例无需下载数据或安装第三方 Python 包：2 辆车、8 个站点、脚本生成的行程事件，随机种子 `2026`，缺车惩罚 `5`，运输成本 `0.1/km`，站点容量 `30`，车辆容量 `25`，LS-ANS 迭代 `80` 次。报告和路线图写入 `outputs/`，不会进入 Git；XeLaTeX 仅用于可选的 PDF 编译。

The included CSV example can be run separately:

```powershell
python examples/real_data_case.py
```

This reads `examples/data/cluster2_stations.csv` and `cluster2_may_trips.csv` (14 stations and 2,905 exported trips). To regenerate those CSVs from the released `.mat` inputs, run `export_cluster_csv(2, 'May')` in MATLAB from the repository root. That command replaces the example CSVs, so use a separate working copy if you need to keep the checked-in samples unchanged.

仓库内另附一个 CSV 小示例，可单独运行 `python examples/real_data_case.py`；它读取 `examples/data/` 下的 14 个站点和 2,905 条已导出行程。需要从 Release 中的 `.mat` 重新导出时，在仓库根目录的 MATLAB 中运行 `export_cluster_csv(2, 'May')`。该命令会覆盖示例 CSV，如需保留入库样本，请在单独工作副本中运行。

## MATLAB experiments / MATLAB 实验

Install MATLAB with the relevant Optimization, Statistics and Machine Learning, and Parallel Computing toolboxes; Gurobi is additionally used by the exact-comparison path. See [dependencies](DEPENDENCIES.md). After extracting the data, set MATLAB's current folder to the repository root and run:

```matlab
main_demo
```

The script prompts for mode `1/2/3/4`. Mode 2 additionally prompts for `1=Quick` or `2=Full`; mode 3 requires a prior mode 2 Full run. Mode 1/4 use `Random_Clusters.mat`. The code writes results to the current folder. We verified the actual entry points and input references but did not claim a full MATLAB benchmark replication from the Python check.

安装 MATLAB 及相关的 Optimization、Statistics and Machine Learning、Parallel Computing 工具箱；精确算法对比路径另使用 Gurobi，详见[依赖说明](DEPENDENCIES.md)。解压数据后，将 MATLAB 当前目录设为仓库根目录，运行 `main_demo`。程序提示选择模式 `1/2/3/4`；模式 2 还需选择 `1=Quick` 或 `2=Full`；模式 3 必须先完成模式 2 Full。模式 1/4 使用 `Random_Clusters.mat`。运行结果写入当前目录。小规模 Python 检查不代表完成全部 MATLAB 基准实验复现。

## Reproducibility notes / 复现说明

The MATLAB prototype and Python reconstruction use different implementation conventions in some places. For a scientific comparison, report the code commit, downloaded Release asset, software/solver versions, selected mode, random seed, and evaluation definition. The experimental parameter values in source code and `representative_case.json` have not been changed for this publication.

MATLAB 原型与 Python 重构在部分实现约定上存在差异。进行科研对比时，请记录代码提交、Release 数据附件、软件及求解器版本、实验模式、随机种子和评价口径。本次整理未更改源码及 `representative_case.json` 中的实验参数。
