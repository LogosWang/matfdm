function run_ckpt(p)
% 分段积分 + checkpoint/restart 的 driver。整个 p 作为输入。
% 路径全部基于本文件所在文件夹(codedir):
%   checkpoint:  <codedir>/checkpoint/dose<tag>/checkpoint.mat
%   最终结果:    <codedir>/results_dose<tag>/   (与 main 一致的 mat/csv/png)
%
% 用法(本地):   p = build_p();  run_ckpt(p);        % build_p 见 main
% 用法(NERSC):  matlab -batch "p=build_p(); p.dose_rate=str2double(getenv('DOSE')); run_ckpt(p)"
%
% 机制: [0,t_end] 切成 nWin 窗, 每窗 ode15s 从上一窗末态续算, 每窗末存 checkpoint。
% 重启时若 checkpoint 存在则从 kdone+1 窗续。墙钟预算(env WALL_BUDGET, 秒)耗尽则
% 存盘退出(batch 下 exit 0)交 SLURM 重排; 交互式下仅 return。
 
% ---------- 路径(全部基于代码所在文件夹) ----------
codedir = fileparts(mfilename('fullpath'));
tag     = dose_tag(p.dose_rate);
ckptdir = fullfile(codedir, 'checkpoint', ['dose' tag]);
outdir  = fullfile(codedir, ['results_dose' tag]);
if ~exist(ckptdir,'dir'), mkdir(ckptdir); end
if ~exist(outdir,'dir'),  mkdir(outdir);  end
ckpt = fullfile(ckptdir, 'checkpoint.mat');
 
% ---------- 墙钟预算 ----------
WALL_BUDGET = str2double(getenv('WALL_BUDGET'));
if isnan(WALL_BUDGET), WALL_BUDGET = inf; end     % 本地不限
tStart = tic;
 
% ---------- 维度 / 采样轴(窗边界) ----------
N = p.nx*p.ny;  M = 6*N + 5*p.ny;
nWin  = 100;                                       % 100 窗 -> 101 采样点
t_out = linspace(0, p.t_end, nWin+1);
 
% ---------- solver ----------
absTol = build_abstol(M, N, p);
opts = odeset('RelTol',1e-4, 'AbsTol',absTol, 'NonNegative',1:M, ...
              'JPattern',jpattern_aks(p.nx,p.ny), 'BDF','on', 'MaxOrder',2, 'Stats','off');
 
% ---------- 载入 checkpoint 或冷启动 ----------
if isfile(ckpt)
    S = load(ckpt);
    kstart = S.kdone + 1;  y0 = S.y0;  Y = S.Y;  t_out = S.t_out;  p = S.p;
    fprintf('[resume] 从窗 %d/%d 续算 (dose=%g)\n', kstart, nWin, p.dose_rate);
else
    kstart = 1;  y0 = initial_state(p);  Y = nan(M, nWin+1);  Y(:,1) = y0;
    fprintf('[fresh] 冷启动 %d 窗 (dose=%g)\n', nWin, p.dose_rate);
end
 
% ---------- 分段积分主循环 ----------
for k = kstart:nWin
    seg = ode15s(@(t,y) rhs_aks(t,y,p), [t_out(k) t_out(k+1)], y0, opts);
    y0  = seg.y(:, end);
    Y(:, k+1) = y0;
 
    kdone = k;
    save(ckpt, 'kdone','y0','Y','t_out','p','-v7.3');
    fprintf('[ckpt] 窗 %d/%d, t=%.3e s, 累计 %.0f s\n', k, nWin, t_out(k+1), toc(tStart));
 
    if toc(tStart) > WALL_BUDGET
        fprintf('[wall] 预算耗尽, 已存 checkpoint, 退出等重排\n');
        if batchStartupOptionUsed, exit(0); else, return; end
    end
end
 
% ---------- 全部完成: 与 main 一致的保存+后处理, 删 checkpoint ----------
fprintf('[done] 全部完成, 后处理 -> %s\n', outdir);
postprocess_matfdm(Y, t_out, p, outdir);
delete(ckpt);
if batchStartupOptionUsed, exit(0); end
end
 
% =====================================================================
function y0 = initial_state(p)
ny=p.ny; nx=p.nx;
V=ones(ny,nx)*p.V_init;  V(:,1)=p.V_DBC;
I=ones(ny,nx)*p.I_init;  I(:,1)=p.I_DBC;
CCr=ones(ny,nx)*p.Cr_init; CCr(:,nx)=p.Cr_DCB;
CFe=ones(ny,nx)*p.Fe_init; CFe(:,nx)=p.Fe_DCB;
CNi=ones(ny,nx)*p.Ni_init; CNi(:,nx)=p.Ni_DCB;
CSi=ones(ny,nx)*p.Si_init; CSi(:,nx)=p.Si_DCB;
CO=ones(ny,1)*p.O_init; CO(1,1)=p.O_DCB;
CCr2O3=ones(ny,1)*p.Cr2O3_init; CFe3O4=ones(ny,1)*p.Fe3O4_init;
CNiFe2O4=ones(ny,1)*p.NiFe2O4_init; CSiO2=ones(ny,1)*p.SiO2_init;
y0=[V(:);I(:);CCr(:);CFe(:);CNi(:);CSi(:);CO(:);CCr2O3(:);CFe3O4(:);CNiFe2O4(:);CSiO2(:)];
end
 
function absTol = build_abstol(M, N, p)
absTol = zeros(M,1);
absTol(1:2*N)          = 1e-12;   % V, I
absTol(2*N+1:6*N)      = 1e-7;    % Cr,Fe,Ni,Si
absTol(6*N+1:6*N+p.ny) = 1e-6;    % O
absTol(6*N+p.ny+1:M)   = 1e-5;    % 4 氧化物
end
 
function tag = dose_tag(dose)
if dose == 0, tag = '0'; else, tag = sprintf('%.0e', dose); end   % 3e-7 -> '3e-07'
end
 