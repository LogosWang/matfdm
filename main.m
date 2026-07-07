%% matfdm 本地入口
% 参数来自 build_p (与 run_ckpt/NERSC 共用同一份, 不漂移)。
% 保存 + 后处理来自 postprocess_matfdm (与 run_ckpt 共用, 与 checkpoint 版一模一样)。
% 想要 checkpoint / NERSC 版: 用 run_ckpt(p) 代替本脚本的求解段。
 
clearvars; clear rhs_aks;
 
p = build_p(1e-7);
% 单次运行想改 dose 就在这里覆盖, 例如:
% p.dose_rate = 3e-7;
 
%% ---- 初值 ----
ny = p.ny;  nx = p.nx;
V   = ones(ny,nx)*p.V_init;  V(:,1)   = p.V_DBC;
I   = ones(ny,nx)*p.I_init;  I(:,1)   = p.I_DBC;
CCr = ones(ny,nx)*p.Cr_init; CCr(:,nx)= p.Cr_DCB;
CFe = ones(ny,nx)*p.Fe_init; CFe(:,nx)= p.Fe_DCB;
CNi = ones(ny,nx)*p.Ni_init; CNi(:,nx)= p.Ni_DCB;
CSi = ones(ny,nx)*p.Si_init; CSi(:,nx)= p.Si_DCB;
CO  = ones(ny,1)*p.O_init;   CO(1,1)  = p.O_DCB;
CCr2O3 = ones(ny,1)*p.Cr2O3_init;  CFe3O4 = ones(ny,1)*p.Fe3O4_init;
CNiFe2O4 = ones(ny,1)*p.NiFe2O4_init;  CSiO2 = ones(ny,1)*p.SiO2_init;
 
N = nx*ny;  M = 6*N + 5*ny;
y0 = [V(:); I(:); CCr(:); CFe(:); CNi(:); CSi(:); ...
      CO(:); CCr2O3(:); CFe3O4(:); CNiFe2O4(:); CSiO2(:)];
assert(numel(y0) == M, '初值向量长度不匹配');
 
%% ---- AbsTol 分场 ----
absTol = zeros(M,1);
absTol(1:2*N)          = 1e-12;    % V, I
absTol(2*N+1:6*N)      = 1e-7;     % Cr,Fe,Ni,Si
absTol(6*N+1:6*N+ny)   = 1e-6;     % O
absTol(6*N+ny+1:M)     = 1e-5;     % 4 氧化物
 
%% ---- 求解 (ode15s + BDF, 冷启动 rhs) ----
opts = odeset( ...
    'RelTol',      1e-4, ...
    'AbsTol',      absTol, ...
    'NonNegative', 1:M, ...
    'JPattern',    jpattern_aks(p.nx, p.ny), ...
    'BDF',         'on', ...
    'MaxOrder',    2, ...
    'Stats',       'on', ...
    'OutputFcn',   @(t,y,flag) myprogress(t,y,flag,p.t_end));
 
fprintf('Starting ode15s, dose = %.2g ...\n', p.dose_rate);
tic;
sol = ode15s(@(t,y) rhs_aks(t,y,p), [0 p.t_end], y0, opts);
toc;
 
%% ---- 采样 + 保存 + 后处理 (与 run_ckpt 完全一致) ----
t_out = linspace(0, p.t_end, 101);
t_out = t_out(t_out <= sol.x(end));            % 部分完成也不崩
Y     = deval(sol, t_out);
 
outdir = fullfile(fileparts(mfilename('fullpath')), ...
                  sprintf('results_dose%s', dose_tag(p.dose_rate)));
postprocess_matfdm(Y, t_out, p, outdir);
 
% ---- 本地小工具: 与 run_ckpt 相同的 dose 命名 ----
function tag = dose_tag(dose)
if dose == 0, tag = '0'; else, tag = sprintf('%.0e', dose); end
end