function p = build_p_decouple(dose)
% 唯一的参数来源。main 和 run_ckpt 都调用它, 保证参数不漂移。
% 改物理参数只改这里。
 
p.dim   = 2;
p.nx    = 50;
p.ny    = 150;
 
p.dt          = 1e-5;
p.GBrecovert  = 0.8 * p.dt;
p.dx    = 2;
p.dy    = 1;
% p.t_end = 1e7;

p.num_ckpt = 50;
p.num_output = 10;

% ---- 缺陷场 ----
p.V_init = 1e-12;  p.V_DBC = 1e-12;
p.I_init = 1e-12;  p.I_DBC = 1e-12;
p.Ks = 1e-3;
DCrV = 7.5e6;
DFeV = 6e6;
DNiV = 5e6;
DSiV = 8e6;
p.DV = [DCrV, DFeV, DNiV,DSiV];
DCrI = 2e6;
DFeI = 2e6;
DNiI = 2e6;
DSiI = 5e6;
p.DI = [DCrI,DFeI,DNiI,DSiI];
p.f0V = 0.8;  p.f0I = 0.7;
p.dose_rate   = 6e-6;
p.dose = dose;
p.irr_time = p.dose/p.dose_rate;
p.oxi_time = 500*60*60;


% ← 扫描时由外部覆盖
p.recomb_rate = 1e4;
 
% ---- 金属 / O 初值与边界 ----
p.Cr_init = 0.211;   p.Cr_DCB = 0.211;
p.Fe_init = 0.699;   p.Fe_DCB = 0.699;
p.Ni_init = 0.085;   p.Ni_DCB = 0.085;
p.Si_init = 0.005;   p.Si_DCB = 0.005;
p.O_init  = 0.0;   p.O_DCB  = 1.0;
p.Cr2O3_init = 0.0;  p.Fe3O4_init = 0.0;
p.FeCr2O4_init = 0.0; p.SiO2_init = 0.0;



p.Dgb = 5e-4;  
p.bypass = 1.0;
p.bypass_threshold = 0.6;
p.vc = 8e-6; p.vw = 2e-6;


% ---- 穿膜输运 (nm^2/s; 1e-17 cm2/s = 1e-3 nm2/s) ----
p.DCr2O3O  = 5e-5;      % O 穿内层
% p.DCr2O3Fe = 5e-5;      % Fe 穿内层
% p.DCr2O3Ni = 5e-6;      % Ni 穿内层 (< Fe)
% p.DOout    = 0.001;      % O 穿外层
% calc_DO 沿GB通道节流组 (与穿膜组物理不同, 独立)
p.DCr2O3 = p.DCr2O3O;  p.DFe3O4 = 0.05;  p.DFeCr2O4 = 0.03;  p.DSiO2 = 0.05;
 
% ---- 界面动力学 (nm/s) ----
p.kCr = 2e-3;  p.kSi = 2e-3;  p.kFe = 1e-4;  p.kspin = 2e-4;
 
% ---- 热力学门控 (无量纲; 默认全关) ----
p.E_Si = 0;  p.E_Cr = 0;  p.E_mag = 0.002;  p.E_spin = 0;
p.kRobin = 0.4;
% O场(水归一)与金属(site fraction)的原子当量换算: rOM = C_O,ref/Nden
% 满水通道 O 密度锚 ~33/87≈0.38; 稀载流子则 <<1。=1 完全还原旧行为。
p.rOM = 22/87;
% ---- 数值 ----
p.Lmin = 0.3;  p.epsP = 1e-5;  p.epsC = 1e-12;  p.tolNode = 1e-12;
p.kdiss = 0;
 
% ---- 物性 ----
p.slab = 1;  p.DO0 = 0.05;  p.DOmax = 10;  p.alpha = 2.0;  p.oxide_character = 0.08;
p.NA = 6.02e23;  p.Nden = 87;
p.Cr2O3den   = 5.22e-21;  p.Cr2O3mass   = 151.99;
p.Fe3O4den   = 5.17e-21;  p.Fe3O4mass   = 231.53;
p.FeCr2O4den = 5.37e-21;  p.FeCr2O4mass = 234.38;
p.SiO2den    = 2.2e-21;   p.SiO2mass    = 60.08;
p.solver = 1;
end