%% RIS 段 dx 网格敏感性扫描入口 (Dirichlet 与 Robin 两种 GB 汇, parpool 并行)
% 输出 scan_dx/Dirich/dx*/, scan_dx/Robin/dx*/, 叠加图与 summary.csv 见 scan_dx_onlyRIS 头注释。
clearvars; clear rhs_aks;
scan_dx_onlyRIS(3.0, [0.25 0.5 1 2]);
