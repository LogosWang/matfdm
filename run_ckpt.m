function run_ckpt(p)
% 分段积分 + checkpoint/restart 的 driver。整个 p 作为输入。
% 路径全部基于本文件所在文件夹(codedir):
%   checkpoint:  <codedir>/checkpoint/dose<tag>/checkpoint.mat
%   最终结果:    <codedir>/results_dose<tag>/   (与 main 一致的 mat/csv/png)
%
% 用法(本地):   p = build_p(3e-7);  run_ckpt(p);
% 用法(NERSC):  matlab -batch "p=build_p(str2double(getenv('DOSE'))); run_ckpt(p)"
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
N = p.nx*p.ny;  M = 6*N + 7*p.ny;                         % 末尾 2*ny 为氧化物分层积分 IA/IH (见 calc_DO)
nWin  = p.num_ckpt;                                       % 100 窗 -> 101 采样点
t_out = linspace(0, p.t_end, nWin+1);
 
% ---------- solver ----------
absTol = build_abstol(M, N, p);
opts = odeset('RelTol',getf(p,'rtol',1e-4), 'AbsTol',absTol, 'NonNegative',1:M, ...
              'JPattern',jpattern_aks(p.nx,p.ny,7), 'BDF','on', 'MaxOrder',2, ...
              'MaxStep',getf(p,'max_step',3600), 'Stats','off');
no_exit = getf(p,'no_exit',false);                        % 续算会用存档的 p 覆盖, 先取出来
 
% ---------- 载入 checkpoint 或冷启动 ----------
if isfile(ckpt)
    S = load(ckpt);
    if numel(S.y0) ~= M
        error('run_ckpt:ckptLayout', ...
            ['存档状态长 %d, 当前布局要 %d (6N+7ny, 含 IA/IH)。\n' ...
             '  这是旧 checkpoint, 不能续算, 请删掉 %s'], numel(S.y0), M, ckpt);
    end
    kstart = S.kdone + 1;  y0 = S.y0;  Y = S.Y;  t_out = S.t_out;  p = S.p;
    fprintf('[resume] 从窗 %d/%d 续算 (dose=%g)\n', kstart, nWin, p.dose_rate);
else
    kstart = 1;  y0 = initial_state(p);  Y = nan(M, nWin+1);  Y(:,1) = y0;
    fprintf('[fresh] 冷启动 %d 窗 (dose=%g)\n', nWin, p.dose_rate);
end
 
% ---------- 分段积分主循环 ----------
for k = kstart:nWin
    % (A) 同 run_ckpt_decouple: 单输出的 sol 形式在 neq=45750 时触发
    % ode15s.m:437 的 chunk=1, 每步 realloc+整体拷贝 dif3d+yout (~1.83 MB/步),
    % 时间 O(n^2)、内存 O(n), 而 sol 只被用来取末态。三点 tspan 走
    % ode15s.m:449 的预分配分支, 输出内存恒为 neq×3。
    [~, yy] = ode15s(@(t,y) rhs_aks(t,y,p), ...
                     [t_out(k), 0.5*(t_out(k)+t_out(k+1)), t_out(k+1)], y0, opts);
    y0  = yy(end,:).';
    Y(:, k+1) = y0;
 
    kdone = k;
    save(ckpt, 'kdone','y0','Y','t_out','p','-v7.3');
    fprintf('[ckpt] 窗 %d/%d, t=%.3e s, 累计 %.0f s\n', k, nWin, t_out(k+1), toc(tStart));
 
    if toc(tStart) > WALL_BUDGET
        fprintf('[wall] 预算耗尽, 已存 checkpoint, 退出等重排\n');
        if batchStartupOptionUsed && ~no_exit, exit(0); else, return; end
    end
end
 
% ---------- 全部完成: 与 main 一致的保存+后处理, 删 checkpoint ----------
fprintf('[done] 全部完成, 后处理 -> %s\n', outdir);
sel = round(linspace(1, nWin+1, 10*p.num_output+1));
postprocess_matfdm(Y(:,sel), t_out(sel), p, outdir);
delete(ckpt);
if batchStartupOptionUsed && ~no_exit, exit(0); end
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
CO=ones(ny,1)*p.O_init;                  % 口部是 Robin BC, 不预置 O_DCB (同 run_ckpt_decouple)
CCr2O3=ones(ny,1)*p.Cr2O3_init; CFe3O4=ones(ny,1)*p.Fe3O4_init;
CFeCr2O4=ones(ny,1)*p.FeCr2O4_init; CSiO2=ones(ny,1)*p.SiO2_init;
IA=zeros(ny,1); IH=zeros(ny,1);          % 无氧化物: 两个分层积分为 0
y0=[V(:);I(:);CCr(:);CFe(:);CNi(:);CSi(:);CO(:);CCr2O3(:);CFe3O4(:);CFeCr2O4(:);CSiO2(:);IA;IH];
end
 
function absTol = build_abstol(M, N, p)
absTol = zeros(M,1);
% 与 run_ckpt_decouple 同一套容差 (build_p 的 atol_* 来自 build_p_decouple)
absTol(1:2*N)          = getf(p,'atol_def',  1e-13);   % V, I
absTol(2*N+1:6*N)      = getf(p,'atol_metal',1e-7);    % Cr,Fe,Ni,Si
absTol(6*N+1:6*N+p.ny) = getf(p,'atol_O',    1e-6);    % O
absTol(6*N+p.ny+1:6*N+5*p.ny) = getf(p,'atol_oxide',1e-5);   % 4 氧化物
absTol(6*N+5*p.ny+1:6*N+6*p.ny) = getf(p,'atol_IA',1e-12);   % IA
absTol(6*N+6*p.ny+1:M)          = getf(p,'atol_IH',1e-3);    % IH
end
 
function tag = dose_tag(dose)
if dose == 0, tag = '0'; else, tag = sprintf('%.0e', dose); end   % 3e-7 -> '3e-07'
end

function v = getf(p, name, dflt)
if isfield(p, name) && ~isempty(p.(name)), v = p.(name); else, v = dflt; end
end
 