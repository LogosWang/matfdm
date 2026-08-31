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
DCrV = 1e7;
DFeV = 7e6;
DNiV = 5e6;
DSiV = 9e6;
p.DV = [DCrV, DFeV, DNiV,DSiV];
DCrI = 2e6;
DFeI = 2e6;
DNiI = 2e6;
DSiI = 1e7;
p.DI = [DCrI,DFeI,DNiI,DSiI];
p.f0V = 0.78;
p.f0I = 0.44;
p.dose_rate   = 6e-6;
p.eff = 0.2;
p.dose = dose;
p.irr_time = p.dose/p.dose_rate;
p.oxi_time = 500*60*60;


% ← 扫描时由外部覆盖
p.recomb_rate = 1e4;
 
% ---- 金属 / O 初值与边界 ----
p.Cr_init = 0.2;   p.Cr_DCB = 0.2;
p.Fe_init = 0.7083;   p.Fe_DCB = 0.7083;
p.Ni_init = 0.089;   p.Ni_DCB = 0.089;
p.Si_init = 0.0027;   p.Si_DCB = 0.0027;
p.O_init  = 0.0;   p.O_DCB  = 1.0;
p.Cr2O3_init = 0.0;  p.Fe3O4_init = 0.0;
p.FeCr2O4_init = 0.0; p.SiO2_init = 0.0;



p.Dgb = 1e-9;  
p.bypass = 1.0;
p.bypass_threshold = 0.6;
p.vc = 8e-6; p.vw = 2e-6;


% ---- 穿膜输运 (nm^2/s; 1e-17 cm2/s = 1e-3 nm2/s) ----
p.DCr2O3O  = 6e-4;      % O 穿内层
% p.DCr2O3Fe = 5e-5;      % Fe 穿内层
% p.DCr2O3Ni = 5e-6;      % Ni 穿内层 (< Fe)
% p.DOout    = 0.001;      % O 穿外层
% calc_DO 沿GB通道节流组 (与穿膜组物理不同, 独立)
p.DCr2O3 = p.DCr2O3O;  p.DFe3O4 = 0.08;  p.DFeCr2O4 = 0.01;  p.DSiO2 = 0.3;
 
% ---- 界面动力学 (nm/s) ----
p.kCr = 0.04;  p.kSi = 0.0002;  p.kFe = 1e-5;  p.kspin = 0.0001;
 
% ---- 热力学门控 (无量纲; 默认全关) ----
p.E_Si = 0;  p.E_Cr = 0;  p.E_mag = 0.0004;  p.E_spin = 0;
p.kRobin = 0.44;
% O场(水归一)与金属(site fraction)的原子当量换算: rOM = C_O,ref/Nden
% 满水通道 O 密度锚 ~33/87≈0.38; 稀载流子则 <<1。=1 完全还原旧行为。
p.rOM = 33/87;
% ---- 数值 ----
p.Lmin = 0.3;  p.epsP = 1e-5;  p.epsC = 1e-12;  p.tolNode = 1e-12;
p.kdiss = 0;
 
% ---- 物性 ----
p.slab = 1;  p.DO0 = p.DSiO2;  p.DOmax = 10;  p.alpha = 2.0;  p.oxide_character = 0.08;
p.NA = 6.02e23;  p.Nden = 87;
p.Cr2O3den   = 5.22e-21;  p.Cr2O3mass   = 151.99;
p.Fe3O4den   = 5.17e-21;  p.Fe3O4mass   = 231.53;
p.FeCr2O4den = 5.05e-21;  p.FeCr2O4mass = 223.83;
p.SiO2den    = 2.2e-21;   p.SiO2mass    = 60.08;
p.solver = 1;
end