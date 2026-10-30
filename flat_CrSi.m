%% Cr / Si 效果解耦测试入口 (RIS 后分别把 Cr 或 Si 重置为均匀 initial 场, 不同 dose 氧化, parpool 并行)
% 输出 decouple/dose<x>_laplace_flatCr/ 与 _flatSi/, 见 run_flat_solute_test 头注释。
clearvars; clear rhs_aks;
run_flat_solute_test([0.5 3.0], {'Cr','Si'});
