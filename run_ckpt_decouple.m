function run_ckpt_decouple(p)
% decouple 模式 driver: 预辐照(无O, 不设ckpt) -> 零剂量氧化(ckpt分段)。
% 用法: p = build_p_decouple(dose_dpa);  run_ckpt_decouple(p);
%
% 段1 辐照: dose_rate=p.dose_rate, O_DCB=0, [0, p.irr_time]
%          单次 ode15s, 切片由 tspan 向量给出 (num_ckpt+1 个采样点), 无 checkpoint
% 段2 氧化: dose_rate=0, O_DCB=1, [0, p.oxi_time], 曝露钟从0起, 全场继承
%          num_ckpt 窗分段积分, 每窗末存 checkpoint, 采样点=窗边界 (num_ckpt+1 个)
%
% 输出:      <codedir>/decouple/dose<p.dose>/   csv+png (后处理用氧化段切片)
%            同文件夹 irr_timeseries.mat 为辐照段切片轨迹 (原始 Y1, 需要时另行后处理)
% checkpoint: <codedir>/checkpoint/decouple_dose<p.dose>/checkpoint.mat (仅氧化段)
%            辐照段中断则整段重跑 (按要求不设 ckpt)

% ---------- 路径 ----------
codedir = fileparts(mfilename('fullpath'));
tag     = sprintf('%g', p.dose);
outdir  = fullfile(codedir, 'decouple', ['dose' tag]);
ckptdir = fullfile(codedir, 'checkpoint', ['decouple_dose' tag]);
if ~exist(outdir,'dir'),  mkdir(outdir);  end
if ~exist(ckptdir,'dir'), mkdir(ckptdir); end
ckpt = fullfile(ckptdir, 'checkpoint.mat');

% ---------- 墙钟预算 ----------
WALL_BUDGET = str2double(getenv('WALL_BUDGET'));
if isnan(WALL_BUDGET), WALL_BUDGET = inf; end
tStart = tic;

% ---------- 两段参数: 同一 p, 每段只改 dose_rate / O_DCB ----------
p1 = p;  p1.O_DCB = 0;                        % 辐照段: 无 O, 纯 RIS
p2 = p;  p2.dose_rate = 0;  p2.O_DCB = 1;     % 氧化段: 零剂量, O 开

N  = p.nx*p.ny;   M = 6*N + 5*p.ny;
nS = p.num_ckpt;                              % 两段切片数一致: nS+1 采样点
t1 = linspace(0, p.irr_time, nS+1);
t2 = linspace(0, p.oxi_time, nS+1);

absTol = build_abstol(M, N, p);
opts = odeset('RelTol',1e-4, 'AbsTol',absTol, 'NonNegative',1:M, ...
              'JPattern',jpattern_aks(p.nx,p.ny), 'BDF','on', 'MaxOrder',2, 'Stats','off');

% ---------- 载入 checkpoint (只可能是氧化段) 或从头 ----------
if isfile(ckpt)
    S = load(ckpt);
    kstart = S.kdone + 1;  y0 = S.y0;  Y1 = S.Y1;  Y2 = S.Y2;
    t1 = S.t1;  t2 = S.t2;  p1 = S.p1;  p2 = S.p2;
    fprintf('[resume] 氧化段从窗 %d/%d 续算 (dose=%g dpa)\n', kstart, nS, p.dose);
else
    % ---- 段1: 辐照, 单次积分, tspan 向量直接给出切片 ----
    y0 = initial_state(p1);
    if p.irr_time > 0
        fprintf('[irr] 辐照段: dose=%g dpa @ %.2g dpa/s, t=%.3e s, %d 切片\n', ...
                p.dose, p.dose_rate, p.irr_time, nS+1);
        [~, yy] = ode15s(@(t,y) rhs_aks(t,y,p1), t1, y0, opts);
        Y1 = yy';                             % M x (nS+1)
        y0 = Y1(:, end);
        fprintf('[irr] 辐照段完成, 耗时 %.0f s\n', toc(tStart));
    else
        Y1 = repmat(y0, 1, nS+1);             % dose=0 对照腿: 跳过辐照
        fprintf('[irr] dose=0, 跳过辐照段\n');
    end
    save(fullfile(outdir,'irr_timeseries.mat'), 'Y1','t1','p1','-v7.3');

    % ---- 交接: Robin BC 下 mouth O 是真实状态量, 无需置位 ----
    % 从辐照段末值(=0)起, 由表面膜阻抗 kRobin/(sqrt(t)+10) 向 O_DCB 充电。

    kstart = 1;  kdone = 0;
    Y2 = nan(M, nS+1);  Y2(:,1) = y0;
    save(ckpt, 'kdone','y0','Y1','Y2','t1','t2','p1','p2','-v7.3');
    fprintf('[handoff] 转氧化段: %d 窗, t=%.3e s (%.0f h)\n', nS, p.oxi_time, p.oxi_time/3600);
end

% ---------- 段2: 氧化, ckpt 分段 ----------
for k = kstart:nS
    seg = ode15s(@(t,y) rhs_aks(t,y,p2), [t2(k) t2(k+1)], y0, opts);
    y0  = seg.y(:, end);   Y2(:, k+1) = y0;   kdone = k;
    save(ckpt, 'kdone','y0','Y1','Y2','t1','t2','p1','p2','-v7.3');
    fprintf('[ckpt] 氧化 %d/%d  t=%.3e s  累计 %.0f s\n', k, nS, t2(k+1), toc(tStart));
    if toc(tStart) > WALL_BUDGET
        fprintf('[wall] 预算耗尽, 已存 checkpoint, 退出等重排\n');
        if batchStartupOptionUsed, exit(0); else, return; end
    end
end

% ---------- 后处理: decouple 版, 两段切片分别传入 ----------
fprintf('[done] 两段完成, 后处理 -> %s\n', outdir);
sel = round(linspace(1, nS+1, 10*p.num_output+1));
postprocess_decouple(Y1(:,sel), t1(sel), Y2(:,sel), t2(sel), p1, outdir);
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
CO=ones(ny,1)*p.O_init;              % Robin BC: 口部不再钉 O_DCB
CCr2O3=ones(ny,1)*p.Cr2O3_init; CFe3O4=ones(ny,1)*p.Fe3O4_init;
CFeCr2O4=ones(ny,1)*p.FeCr2O4_init; CSiO2=ones(ny,1)*p.SiO2_init;
y0=[V(:);I(:);CCr(:);CFe(:);CNi(:);CSi(:);CO(:);CCr2O3(:);CFe3O4(:);CFeCr2O4(:);CSiO2(:)];
end

function absTol = build_abstol(M, N, p)
absTol = zeros(M,1);
absTol(1:2*N)          = 1e-12;   % V, I
absTol(2*N+1:6*N)      = 1e-7;    % Cr,Fe,Ni,Si
absTol(6*N+1:6*N+p.ny) = 1e-6;    % O
absTol(6*N+p.ny+1:M)   = 1e-5;    % 4 氧化物
end