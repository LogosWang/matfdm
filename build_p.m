function p = build_p(drate)
% 唯一的参数来源。main 和 run_ckpt 都调用它, 保证参数不漂移。
% 改物理参数只改这里。
 
p.dim   = 2;
p.nx    = 50;
p.ny    = 100;
 
p.dt          = 1e-5;
p.GBrecovert  = 0.8 * p.dt;
p.dx    = 0.4;
p.dy    = 1;
p.t_end = 1e7;

p.num_ckpt = 1000;
p.num_output = 10;

% ---- 缺陷场 ----
p.V_init = 1e-13;  p.V_DBC = 1e-13;
p.I_init = 1e-13;  p.I_DBC = 1e-13;
p.Ks = 1e-3;
p.DV = [4.55e4, 3.21e4, 2.68e4, 5e4];    % Cr Fe Ni Si (V-mediated)
p.DI = [1.5e4,  1.5e4,  1.5e4,  3e4];    % Cr Fe Ni Si (I-mediated)
p.f0V = 0.8;  p.f0I = 0.7;
p.dose_rate   = drate;                     % ← 扫描时由外部覆盖
p.recomb_rate = 1e4;
 
% ---- 金属 / O 初值与边界 ----
p.Cr_init = 0.18;  p.Cr_DCB = 0.18;
p.Fe_init = 0.71;  p.Fe_DCB = 0.71;
p.Ni_init = 0.10;  p.Ni_DCB = 0.10;
p.Si_init = 0.01;  p.Si_DCB = 0.01;
p.O_init  = 0.0;   p.O_DCB  = 1.0;
p.Cr2O3_init = 0.0;  p.Fe3O4_init = 0.0;
p.NiFe2O4_init = 0.0; p.SiO2_init = 0.0;



p.Dgb = 5e-4;  
p.bypass = 1.0;
p.bypass_threshold = 0.6;
p.vc = 8e-6; p.vw = 2e-6;


% ---- 穿膜输运 (nm^2/s; 1e-17 cm2/s = 1e-3 nm2/s) ----
p.DCr2O3O  = 2e-4;      % O 穿内层
p.DCr2O3Fe = 2e-4;      % Fe 穿内层
p.DCr2O3Ni = 1e-5;      % Ni 穿内层 (< Fe)
p.DOout    = 8e-4;      % O 穿外层
% calc_DO 沿GB通道节流组 (与穿膜组物理不同, 独立)
p.DCr2O3 = p.DCr2O3O;  p.DFe3O4 = p.DOout;  p.DNiFe2O4 = p.DOout;  p.DSiO2 = 0.01;
 
% ---- 界面动力学 (nm/s) ----
p.kCr = 1e-3;  p.kSi = 1e-3;  p.kFe = 2e-4;  p.kNi = 2e-5;
 
% ---- 热力学门控 (无量纲; 默认全关) ----
p.E_Si = 0;  p.E_Cr = 0;  p.E_mag = 0;  p.E_trev = 0;
 
% ---- 数值 ----
p.Lmin = 0.3;  p.epsP = 1e-5;  p.epsC = 1e-12;  p.tolNode = 1e-12;
p.kdiss = 0;
 
% ---- 物性 ----
p.slab = 1;  p.DO0 = 0.1;  p.DOmax = 10;  p.alpha = 2.0;  p.oxide_character = 0.08;
p.NA = 6.02e23;  p.Nden = 87;
p.Cr2O3den   = 5.22e-21;  p.Cr2O3mass   = 151.99;
p.Fe3O4den   = 5.17e-21;  p.Fe3O4mass   = 231.53;
p.NiFe2O4den = 5.37e-21;  p.NiFe2O4mass = 234.38;
p.SiO2den    = 2.2e-21;   p.SiO2mass    = 60.08;
p.solver = 1;
end