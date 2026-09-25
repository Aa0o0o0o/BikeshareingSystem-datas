# Dependencies / 依赖说明

## Python / Python 环境

- Python >= 3.10. The default `python_patent_rewrite/examples/end_to_end.py` pipeline uses only the standard library. / 默认小算例仅依赖 Python 标准库。
- `python_patent_rewrite/pyproject.toml` declares optional `cvxpy>=1.4` for the alternative SOCP backend and `pytest>=8` for development. Neither is required for the documented `unittest` check. / 可选 SOCP 后端使用 `cvxpy>=1.4`；`pytest>=8` 仅为开发选项。
- Root `generate_random_clusters.py` uses NumPy and SciPy to read/write MATLAB data. Install them in the Python environment if running this generator; it is not needed for the deterministic example. / 根目录的随机簇生成脚本依赖 NumPy、SciPy；确定性小算例无需运行它。
- Optional: XeLaTeX and its TikZ/pgfplots packages for compiling generated `.tex` reports to PDF. The scripts can still run without it. / 可选：XeLaTeX 及 TikZ/pgfplots，用于将生成的报告编译为 PDF。

## MATLAB / MATLAB 环境

- MATLAB with `coneprog` (Optimization Toolbox), `kmeans`/`fitgmdist`/`pdist2` (Statistics and Machine Learning Toolbox), and `parfor` (Parallel Computing Toolbox) for the corresponding experiment paths. / 相应实验路径使用上述 MATLAB 函数及工具箱。
- Gurobi MATLAB API and a valid license for the exact-comparison code path in `gurobi_pctsp_solver.m`. Other modes may also invoke this solver through comparison routines; check the selected mode before running. / 精确算法对比代码使用 Gurobi MATLAB API 及有效许可证，其他对比流程也可能调用它。
- The `.mat` inputs are provided as the `v0.1.0` Release attachment; extract them to the repository root before running `main_demo.m`. / `.mat` 输入见 `v0.1.0` Release 附件，运行前解压到仓库根目录。

No environment lockfile was present in the source project. Solver availability and MATLAB runtime results should be recorded when reproducing full experiments. / 原项目没有环境锁定文件；完整实验复现应记录求解器可用性及 MATLAB 运行结果。
