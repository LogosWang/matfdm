%% couple 模式单作业: dose rate 1e-7 dpa/s 辐照与氧化同时, 累计 40 dpa (t_end = 4e8 s)
% 网格 ny = 100, dy = 50 nm (沿 GB 共 5000 nm); 其余参数来自 build_p -> build_p_decouple。
clearvars; clear rhs_aks;

p = build_p(1e-7);
p.dose  = 40;
% p.t_end = p.dose / p.dose_rate;     % 4e8 s
p.t_end = 40*365*24*60*60;
p.dose_rate = p.dose / p.t_end;
p.ny    = 100;
p.dy    = 50;

% 合金成分 (at%): Fe 67.89, Cr 19.32, Ni 11.55, Si 1.24; 初值与远场 Dirichlet 同值
p.Cr_init = 0.1932;   p.Cr_DCB = 0.1932;
p.Fe_init = 0.6789;   p.Fe_DCB = 0.6789;
p.Ni_init = 0.1155;   p.Ni_DCB = 0.1155;
p.Si_init = 0.0124;   p.Si_DCB = 0.0124;

% 最大步长放宽: 默认 9000 s 在 4e8 s 上至少 4.4 万步; 仍小于窗长 t_end/num_ckpt = 8e6 s,
% 求解行为与 num_ckpt 解耦
p.max_step = 5e6;
run_ckpt(p);
