function p = build_p_decouple(dose)
% 唯一的参数来源。main 和 run_ckpt 都调用它, 保证参数不漂移。
% 改物理参数只改这里。
 
p.dim   = 2;
p.nx    = 50;
p.ny    = 150;
 
p.dt          = 1e-5;
p.GBrecovert  = 0.8 * p.dt;
p.dx    = 0.3;
p.dy    = 1;
% p.t_end = 1e7;

p.num_ckpt = 50;
p.num_output = 10;

% ---- 缺陷场 ----
p.V_init = 1e-13;  p.V_DBC = 1e-13;
p.I_init = 1e-30;  p.I_DBC = 1e-30;

% 重置目标 = 热平衡浓度 (仅 handoff_reset_defects=true 时用到)。
% 取成与 Veq/Ieq 一致, 重置后 Ks*(Veq-V) 恒为 0。
p.def_floor_V = 1e-13;
p.def_floor_I = 1e-30;

% 辐照段结束交接到氧化段时, 缺陷场怎么处理:
%   false (默认) —— 保留辐照末态, 过饱和缺陷按 Ks 汇项以 1/Ks=1000 s 自然退火
%   true         —— 一次性重置到热平衡值 (def_floor_V / def_floor_I),
%                   相当于假定退火瞬间完成
% 两版结果分开存: true 时输出目录/checkpoint 变成 dose<x>_reset, 不覆盖默认版。
p.handoff_reset_defects = false;

p.Ks = 0.0;
DCrV = 1.9e7;
DFeV = 1.45e7;
DNiV = 1.15e7;
DSiV = 1.9e7;
p.DV = [DCrV, DFeV, DNiV,DSiV];
DCrI = 4e6;
DFeI = 4e6;
DNiI = 4e6;
DSiI = 1.4e7;
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

% ---- 穿膜输运 (nm^2/s; 1e-17 cm2/s = 1e-3 nm2/s) ----
p.DCr2O3O  = 3e-5;      % O 穿内层
p.DCr2O3 = p.DCr2O3O;  p.DFe3O4 = 0.0012;  p.DFeCr2O4 = 0.0006;  p.DSiO2 = 1.0;
 
% ---- 界面动力学 (nm/s) ----
p.kCr = 0.6;  p.kSi = 2e-5;  p.kFe = 1e-5;  p.kspin = 5e-4;
 
% ---- 热力学门控 (无量纲; 默认全关) ----
p.E_Si = 0;  p.E_Cr = 0;  p.E_mag = 0.008;  p.E_spin = 0;
p.kRobin = 0.4;
% O场(水归一)与金属(site fraction)的原子当量换算: rOM = C_O,ref/Nden
% 满水通道 O 密度锚 ~33/87≈0.38; 稀载流子则 <<1。=1 完全还原旧行为。
p.rOM = 22/87;
% ---- 数值 ----
p.Lmin = 0.3;  p.epsP = 1e-5;  p.epsC = 1e-12;  p.tolNode = 1e-12;
p.kdiss = 0;

% ---- 求解器数值参数 (全部可调, run_ckpt_decouple 读这些字段建 odeset) ----
p.rtol       = 1e-4;    % ode15s RelTol

% AbsTol。缺陷场 V/I 共用 atol_def —— 这是沿用的折中设定, 细节与"为什么不
% 按地板收紧"的实测结论写在 run_ckpt_decouple.m 的 build_abstol 里。
p.atol_def   = 1e-13;   % V, I
p.atol_metal = 1e-7;    % Cr, Fe, Ni, Si
p.atol_O     = 1e-6;    % O
p.atol_oxide = 1e-5;    % 4 种氧化物

% NonNegative 作用域。true = 1:M (原行为, 缺陷场也约束)。
% 置 false 需同时收紧 atol_def, 否则 V/I 会自由变负。
p.nonneg_defects = true;

% log() 的下限, 只为挡住 log(0)=-Inf / log(负)=复数, 必须【远低于任何物理值】。
% 教训: 曾把介质地板取成 p.V_init, 而 V_DBC 恰好也等于它, 结果紧邻边界那个面
% 两侧被钳成同值, dlogV 恒为 0, 把边界回流的恢复通量整个抹掉, V 在 i=2 列被
% 钉死在 0 -> 步长塌到 6e-7 s。地板绝不能落在任何实际会取到的值附近。
p.logfloor_C = 1e-12;    % 金属浓度 (实际量级 1e-3~0.7); 介质 V/I 不再进 log

% (D) 最大步长, 秒。不设时 ode15s 用 hmax = 0.1*(窗长) (odearguments.m:166),
% 于是求解行为会随 num_ckpt 变化 —— 这正是"改 checkpoint 数量就好转"的第二条
% 耦合通道。设成一个【小于最短窗长】的绝对值, 求解行为就与 num_ckpt 解耦。
% 参考: oxi_time=1.8e6 s, num_ckpt=200 -> 窗长 9000 s; num_ckpt=50 -> 36000 s。
p.max_step   = 36000;

% ---- 物性 ----
p.slab = 1;  p.DO0 = p.DSiO2;  p.DOmax = 10;  p.alpha = 2.0;  p.oxide_character = 0.08;
p.NA = 6.02e23;  p.Nden = 87;
p.Cr2O3den   = 5.22e-21;  p.Cr2O3mass   = 151.99;
p.Fe3O4den   = 5.17e-21;  p.Fe3O4mass   = 231.53;
p.FeCr2O4den = 5.05e-21;  p.FeCr2O4mass = 223.83;
p.SiO2den    = 2.2e-21;   p.SiO2mass    = 60.08;
p.solver = 1;
end