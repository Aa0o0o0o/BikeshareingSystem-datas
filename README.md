# BikeshareingSystem-code
Two-Stage Distributionally Robust Repositioning with Routing Decisions in Dockless Bike-Sharing Systems

Research code and data for bike-sharing repositioning under demand uncertainty.

共享单车需求不确定性下的两阶段分布鲁棒再平衡：研究代码与实验数据。

English
Overview

This repository accompanies the manuscript “Two-Stage Distributionally Robust Repositioning with Routing Decisions in Dockless Bike-Sharing Systems.” It brings together the code and experimental data used to investigate the joint optimization of vehicle routes and bicycle inventory reallocation under uncertain demand.

The study considers static repositioning operations conducted before the next service period. Using demand means and variances, the proposed distributionally robust formulation minimizes transportation costs and worst-case expected shortage costs over a set of admissible demand distributions.

The purpose of this repository is to make the numerical study transparent and reproducible, and to support further research on bike-sharing operations and routing–inventory optimization.

Methodology

The solution framework combines two components:

Route optimization: LS-ANS searches for station selections and vehicle routes through destroy-and-repair operations and local-search moves.
Inventory optimization: Given the routes, second-order cone programming (SOCP) subproblems determine the corresponding pickup and delivery quantities.

A mixed-integer second-order cone programming (MI-SOCP) formulation provides an exact benchmark for small instances.

Numerical experiments

The numerical study includes:

Experiment	Purpose
Real-world case study	Evaluate repositioning plans using data from the Montréal BIXI system.
Comparison with exact optimization	Assess solution quality on small instances using Gurobi.
Distribution-shift experiments	Evaluate out-of-sample performance under shifts in demand means.
Ablation study	Examine the contributions of search phases and individual operators, including their computational costs.

Benchmarks include the Greedy Mean–Standard Deviation Threshold policy (G-MS) and the No Scheduling policy (NS).

The real-world study uses BIXI operational data from May–October 2024, with May–August used for training and September–October reserved for validation. Although the motivating application is dockless bike sharing, the empirical evaluation uses data from a docked system. Synthetic experiments provide additional controlled comparisons across different network sizes.

Reproducibility and interpretation

The code and data should be read alongside the experimental setup and metric definitions in the manuscript. Optimization objective values and empirical out-of-sample costs serve different purposes and should be compared only under consistent evaluation settings.

Random seeds, stopping criteria, solver settings, and hardware can affect computational results. Exact numerical agreement is not guaranteed across different software environments, and runtime comparisons require particular care.

BIXI is acknowledged as the source of the real-world operational data. Data-processing procedures and synthetic-instance generation are part of the experimental workflow.

Project status and citation

The manuscript is currently in preparation. Repository contents and documentation may be updated as the study is finalized.

If you use this work, please acknowledge this repository and cite the associated manuscript once its bibliographic details become available. For reproducibility, please also record the release or commit used in your experiments.

Questions, reproducibility reports, and suggestions are welcome through GitHub Issues.
