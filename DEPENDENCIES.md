# Dependencies / 依赖说明

- MATLAB: Optimization Toolbox (`coneprog`), Statistics and Machine Learning Toolbox (`kmeans`, `fitgmdist`, `pdist2`), and Parallel Computing Toolbox (`parfor`) for the corresponding experiment modes. / 相应实验模式需要上述 MATLAB 工具箱。
- Gurobi MATLAB API and a valid license are required for the exact-comparison path in `gurobi_pctsp_solver.m`. / 精确算法对比路径需要 Gurobi MATLAB API 和有效许可证。
- Python with NumPy and SciPy is needed only to run `generate_random_clusters.py`; the MATLAB input `.mat` files are included in the Release attachment. / 仅运行随机簇生成脚本时需要 Python、NumPy 和 SciPy；MATLAB 输入数据见 Release 附件。
