function run_onlyRIS(p)
% onlyRIS 模式 driver: 只跑辐照段 (纯 RIS), 不做氧化。
% 用法: p = build_p_decouple(dose_dpa);  run_onlyRIS(p);
%
% 段: dose_rate=p.dose_rate, O_DCB=0, [0, p.irr_time]
%     O 与 4 个氧化物场仍在状态向量里, 但 O_DCB=0 => 不充电、不生长, 恒为初值。
%     num_ckpt 窗分段积分, 每窗末存 checkpoint (与 run_ckpt_decouple 同样的机制,
%     支持 WALL_BUDGET 中断续算)。
%
% 输出:      <codedir>/onlyRIS/dose<p.dose>/            csv + png + fields_timeseries.mat
% checkpoint: <codedir>/checkpoint/onlyRIS_dose<p.dose>/checkpoint.mat

% ---------- 路径 ----------
codedir = fileparts(mfilename('fullpath'));
% 目录名 dose<x>dpa: 与 onlyRIS/RIS_profile_plots.ipynb 的
% DOSES = ['0.5dpa','3.0dpa'] 对齐 (它按 f'dose{dose}' 拼路径, 对不上会 assert)。
% 用 %.1f 而不是 %g, 否则 3.0 会变成 "3" 而 notebook 要的是 "3.0"。
tag     = sprintf('%.1fdpa', p.dose);
outdir  = fullfile(codedir, 'onlyRIS', ['dose' tag]);
ckptdir = fullfile(codedir, 'checkpoint', ['onlyRIS_dose' tag]);
if ~exist(outdir,'dir'),  mkdir(outdir);  end
if ~exist(ckptdir,'dir'), mkdir(ckptdir); end
ckpt = fullfile(ckptdir, 'checkpoint.mat');

% ---------- 墙钟预算 ----------
WALL_BUDGET = str2double(getenv('WALL_BUDGET'));
if isnan(WALL_BUDGET), WALL_BUDGET = inf; end
tStart = tic;

% ---------- 参数: 只关掉 O ----------
p1 = p;  p1.O_DCB = 0;                        % 纯 RIS, 无氧化

N  = p.nx*p.ny;   M = 6*N + 5*p.ny;
nS = p.num_ckpt;
t1 = linspace(0, p.irr_time, nS+1);

rtol   = getf(p,'rtol',1e-4);
absTol = build_abstol(M, N, p);
nnIdx  = build_nonneg(M, N, p);
maxStp = getf(p,'max_step', 3600);
opts = odeset('RelTol',rtol, 'AbsTol',absTol, 'NonNegative',nnIdx, ...
              'JPattern',jpattern_aks(p.nx,p.ny), 'BDF','on', 'MaxOrder',2, ...
              'MaxStep',maxStp, 'Stats','off');

% ---------- 载入 checkpoint 或从头 ----------
if isfile(ckpt)
    S = load(ckpt);
    kstart = S.kdone + 1;  y0 = S.y0;  Y1 = S.Y1;  t1 = S.t1;  p1 = S.p1;
    for f = {'logfloor_C','atol_def'}
        if isfield(p, f{1}), p1.(f{1}) = p.(f{1}); end
    end
    fprintf('[resume] 辐照段从窗 %d/%d 续算 (dose=%g dpa)\n', kstart, nS, p.dose);
    if numel(t1) ~= nS+1
        warning('run_onlyRIS:ckptGridMismatch', ...
            ['存档 t1 有 %d 个点 (num_ckpt=%d), 当前 p.num_ckpt=%d 不一致。\n' ...
             '  改 num_ckpt 前请先删掉 %s'], numel(t1), numel(t1)-1, nS, ckpt);
    end
else
    y0 = initial_state(p1);
    kstart = 1;  kdone = 0;
    Y1 = nan(M, nS+1);  Y1(:,1) = y0;
    save(ckpt, 'kdone','y0','Y1','t1','p1','-v7.3');
    fprintf('[ris] 辐照段: dose=%g dpa @ %.2g dpa/s, t=%.3e s (%.0f h), %d 窗\n', ...
            p.dose, p.dose_rate, p.irr_time, p.irr_time/3600, nS);
end

% ---------- 主循环 ----------
for k = kstart:nS
    tw = tic;
    [~, yy] = ode15s(@(t,y) rhs_aks(t,y,p1), ...
                     [t1(k), 0.5*(t1(k)+t1(k+1)), t1(k+1)], y0, opts);
    y0 = yy(end,:).';   Y1(:, k+1) = y0;   kdone = k;
    save(ckpt, 'kdone','y0','Y1','t1','p1','-v7.3');
    fprintf('[ckpt] 辐照 %d/%d  t=%.3e s (%.3g dpa)  本窗 %.1f s  累计 %.0f s\n', ...
            k, nS, t1(k+1), t1(k+1)*p.dose_rate, toc(tw), toc(tStart));
    if toc(tStart) > WALL_BUDGET
        fprintf('[wall] 预算耗尽, 已存 checkpoint, 退出等重排\n');
        if batchStartupOptionUsed, exit(0); else, return; end
    end
end

% ---------- 后处理 ----------
fprintf('[done] 辐照段完成, 后处理 -> %s\n', outdir);
sel = round(linspace(1, nS+1, 10*p.num_output+1));
postprocess_onlyRIS(Y1(:,sel), t1(sel), p1, outdir);
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
CO=ones(ny,1)*p.O_init;
CCr2O3=ones(ny,1)*p.Cr2O3_init; CFe3O4=ones(ny,1)*p.Fe3O4_init;
CFeCr2O4=ones(ny,1)*p.FeCr2O4_init; CSiO2=ones(ny,1)*p.SiO2_init;
y0=[V(:);I(:);CCr(:);CFe(:);CNi(:);CSi(:);CO(:);CCr2O3(:);CFe3O4(:);CFeCr2O4(:);CSiO2(:)];
end

function absTol = build_abstol(M, N, p)
% 与 run_ckpt_decouple 保持一致, 细节见那里的同名函数注释。
aD = getf(p,'atol_def', 1e-13);
absTol = zeros(M,1);
absTol(      1 : 2*N)      = aD;                             % V, I
absTol(2*N + 1 : 6*N)      = getf(p,'atol_metal', 1e-7);     % Cr,Fe,Ni,Si
absTol(6*N + 1 : 6*N+p.ny) = getf(p,'atol_O',     1e-6);     % O
absTol(6*N + p.ny + 1 : M) = getf(p,'atol_oxide', 1e-5);     % 4 氧化物
end

function idx = build_nonneg(M, N, p)
if getf(p,'nonneg_defects', true)
    idx = 1:M;
else
    idx = 2*N + 1 : M;
end
end

function v = getf(p, name, dflt)
if isfield(p, name) && ~isempty(p.(name)), v = p.(name); else, v = dflt; end
end
