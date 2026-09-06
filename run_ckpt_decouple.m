function run_ckpt_decouple(p)
% decouple 模式 driver: 预辐照(无O, 不设ckpt) -> 零剂量氧化(ckpt分段)。
% 用法: p = build_p_decouple(dose_dpa);  run_ckpt_decouple(p);
%
% 段1 辐照: dose_rate=p.dose_rate, O_DCB=0, [0, p.irr_time]
%          单次 ode15s, 切片由 tspan 向量给出 (num_ckpt+1 个采样点), 无 checkpoint
% 段2 氧化: dose_rate=0, O_DCB=1, [0, p.oxi_time], 曝露钟从0起
%          交接时 V 场与边界压到 p.def_floor_V, I 压到 p.def_floor_I,
%          缺陷不再介导金属扩散, RIS 剖面冻结
%          num_ckpt 窗分段积分, 每窗末存 checkpoint
%
% 输出:      <rundir>/decouple/<case_tag>/dose<p.dose>/   csv+png (后处理用氧化段切片)
%            同文件夹 irr_timeseries.mat 为辐照段切片轨迹
% checkpoint: <rundir>/checkpoint/<case_tag>/decouple_dose<p.dose>/checkpoint.mat

% ---------- 路径: 数据写进运行目录, 不写进代码目录 ----------
% p.rundir 优先 (标定驱动传入), 否则用 run_root() (= $MATFDM_RUN, 未设则代码目录)。
% 编译成 standalone 后 mfilename('fullpath') 指向 MCR 的 CTF 解包目录 —— 绝不能
% 拿它当输出根, 否则 120 条并行腿会全写进各自的节点临时目录, 结果拿不回来。
if isfield(p,'rundir') && ~isempty(p.rundir)
    codedir = char(p.rundir);
else
    codedir = run_root();
end
tag     = sprintf('%g', p.dose);
% 交接方式不同的两版结果不互相覆盖: 重置版另存到 dose<x>_reset
if isfield(p,'handoff_reset_defects') && p.handoff_reset_defects
    tag = [tag '_reset'];
end
% case_tag 隔离每个 CMA 样本; 缺了它同一代 40 个样本会全撞进同一个 dose<x>/
if isfield(p,'case_tag') && ~isempty(p.case_tag)
    case_tag = char(p.case_tag);
else
    case_tag = 'default';
end
assert(~isempty(regexp(case_tag,'^[A-Za-z0-9_-]+$','once')), ...
       'case_tag may only contain letters, digits, _ and -');
outdir  = fullfile(codedir, 'decouple', case_tag, ['dose' tag]);
ckptdir = fullfile(codedir, 'checkpoint', case_tag, ['decouple_dose' tag]);
if ~exist(outdir,'dir'),  mkdir(outdir);  end
if ~exist(ckptdir,'dir'), mkdir(ckptdir); end
ckpt = fullfile(ckptdir, 'checkpoint.mat');

% ---------- 墙钟预算 ----------
WALL_BUDGET = str2double(getenv('WALL_BUDGET'));
if isnan(WALL_BUDGET), WALL_BUDGET = inf; end
tStart = tic;

% ---------- 交接时缺陷场的重置目标 = 热平衡浓度 ----------
% 默认取 p.V_init / p.I_init, 也就是 dVdt/dIdt 里 Ks 汇项拉向的那个 Veq/Ieq,
% 这样重置后 Ks*(Veq-V) 恒为 0, 自洽。def_floor_* 可单独覆盖。
if isfield(p,'def_floor_V'), floorV = p.def_floor_V; else, floorV = p.V_init; end
if isfield(p,'def_floor_I'), floorI = p.def_floor_I; else, floorI = p.I_init; end

% ---------- 两段参数: 同一 p, 每段只改 dose_rate / O_DCB ----------
p1 = p;  p1.O_DCB = 0;                        % 辐照段: 无 O, 纯 RIS
p2 = p;  p2.dose_rate = 0;  p2.O_DCB = 1;     % 氧化段: 零剂量, O 开

N  = p.nx*p.ny;   M = 6*N + 5*p.ny;
nS = p.num_ckpt;
t1 = linspace(0, p.irr_time, nS+1);
t2 = linspace(0, p.oxi_time, nS+1);

rtol   = getf(p,'rtol',1e-4);
absTol = build_abstol(M, N, p);
nnIdx  = build_nonneg(M, N, p);
maxStp = getf(p,'max_step', 3600);
opts = odeset('RelTol',rtol, 'AbsTol',absTol, 'NonNegative',nnIdx, ...
              'JPattern',jpattern_aks(p.nx,p.ny), 'BDF','on', 'MaxOrder',2, ...
              'MaxStep',maxStp, 'Stats','off');

% ---------- 载入 checkpoint (只可能是氧化段) 或从头 ----------
if isfile(ckpt)
    S = load(ckpt);
    kstart = S.kdone + 1;  y0 = S.y0;  Y1 = S.Y1;  Y2 = S.Y2;
    t1 = S.t1;  t2 = S.t2;  p1 = S.p1;  p2 = S.p2;
    % 数值参数不随 checkpoint 冻结: 用当前 build_p_* 的值覆盖存档里的旧值。
    % (opts 本来就是用新 p 重建的; 这里同步的是 rhs_aks 直接读的那些字段。)
    for f = {'logfloor_C','atol_def'}
        if isfield(p, f{1}), p1.(f{1}) = p.(f{1});  p2.(f{1}) = p.(f{1});  end
    end
    fprintf('[resume] 氧化段从窗 %d/%d 续算 (dose=%g dpa)\n', kstart, nS, p.dose);
    % 只告警, 不改行为 (F 未修): 存档的 t2/Y2 网格与当前 num_ckpt 不一致时,
    % 调小 num_ckpt 会只积分 oxi_time 的一部分且后处理静默出图; 调大会索引越界。
    if numel(t2) ~= nS+1
        warning('run_ckpt_decouple:ckptGridMismatch', ...
            ['存档 t2 有 %d 个点 (num_ckpt=%d), 当前 p.num_ckpt=%d 不一致。\n' ...
             '  改 num_ckpt 前请先删掉 %s'], numel(t2), numel(t2)-1, nS, ckpt);
    end
else
    % ---- 段1: 辐照, 单次积分, tspan 向量直接给出切片 ----
    y0 = initial_state(p1);
    if p.irr_time > 0
        fprintf('[irr] 辐照段: dose=%g dpa @ %.2g dpa/s, t=%.3e s, %d 切片\n', ...
                p.dose, p.dose_rate, p.irr_time, nS+1);
        % 这一段本来就用 tspan 向量 (ntspan>2), 走 ode15s 的预分配输出分支
        % (ode15s.m:449 zeros(neq,ntspan)), 内存有界 —— 所以辐照段一直能跑完。
        [~, yy] = ode15s(@(t,y) rhs_aks(t,y,p1), t1, y0, opts);
        Y1 = yy';                             % M x (nS+1)
        y0 = Y1(:, end);
        fprintf('[irr] 辐照段完成, 耗时 %.0f s\n', toc(tStart));
    else
        Y1 = repmat(y0, 1, nS+1);             % dose=0 对照腿: 跳过辐照
        fprintf('[irr] dose=0, 跳过辐照段\n');
    end
    if isfield(p,'keep_traj') && p.keep_traj
        save(fullfile(outdir,'irr_timeseries.mat'), 'Y1','t1','p1','-v7.3');
    end

    % ---- 交接: 缺陷场如何处理 ----
    % p.handoff_reset_defects
    %   false (默认): 保留辐照段末态的 V/I, 让 Ks 汇项以 1/Ks 的尺度自然退火。
    %   true        : 全场与边界一次性重置到热平衡值 (floorV/floorI)。
    %
    % 两者物理含义不同:
    %   保留末态 = 辐照停止后缺陷过饱和还在, 按 Ks 逐渐退火 (有限退火速率)
    %   重置     = 假定退火瞬间完成, 氧化段从热平衡缺陷浓度起步
    % 注意重置【不等于】缺陷场冻结: 金属的 RIS 剖面仍在, -div(J_V) 不为零,
    % V 仍会重新分布, 只是起点不同。
    if getf(p,'handoff_reset_defects', false)
        y0(      1 :   N) = floorV;           % V 全场
        y0(  N + 1 : 2*N) = floorI;           % I 全场
        p2.V_init = floorV;  p2.V_DBC = floorV;
        p2.I_init = floorI;  p2.I_DBC = floorI;
        fprintf('[handoff] 缺陷场重置为热平衡值: V=%g, I=%g\n', floorV, floorI);
    else
        fprintf(['[handoff] 保留辐照末态缺陷场: V=[%.3e, %.3e]  I=[%.3e, %.3e]\n' ...
                 '[handoff] (Veq=%.1e, Ieq=%.1e, dose_rate=0 => Ks 汇项以 1/Ks=%.0f s 退火)\n'], ...
                min(y0(1:N)), max(y0(1:N)), min(y0(N+1:2*N)), max(y0(N+1:2*N)), ...
                p2.V_init, p2.I_init, 1/p.Ks);
    end

    kstart = 1;  kdone = 0;
    Y2 = nan(M, nS+1);  Y2(:,1) = y0;
    save_checkpoint_atomic(ckpt,kdone,y0,Y1,Y2,t1,t2,p1,p2);
    fprintf('[handoff] 转氧化段: %d 窗, t=%.3e s (%.0f h)\n', nS, p.oxi_time, p.oxi_time/3600);
end

% ---------- 段2: 氧化, ckpt 分段 ----------
for k = kstart:nS
    % (A) 三点 tspan, 两个输出参数。
    % 原来写的是 seg = ode15s(..., [t2(k) t2(k+1)], ...) —— 单输出 => output_sol,
    % 而 neq=45750 时 ode15s.m:437 的
    %     chunk = min(max(100,50*refine), refine+floor(2^11/neq))
    % 取值为 1, 于是【每接受一步】都要 realloc 并整体拷贝
    %     dif3d (neq×(MaxOrder+2)×n) + yout (neq×n)  ≈ 1.83 MB/步,
    % 时间 O(n²)、内存 O(n): n=8000 步就是 ~15 GB 常驻 + ~59 TB 的 memcpy。
    % 这才是"内存越涨越多直到死机"和"checkpoint 数量影响速度"的根因,
    % 而且整个 sol 结构体只被用来取 seg.y(:,end), 全是白造的。
    % 给 3 个时间点就走 ntspan>2 的预分配分支 (ode15s.m:449), 输出内存恒为 neq×3。
    tw = tic;
    [~, yy] = ode15s(@(t,y) rhs_aks(t,y,p2), ...
                     [t2(k), 0.5*(t2(k)+t2(k+1)), t2(k+1)], y0, opts);
    y0  = yy(end,:).';     Y2(:, k+1) = y0;   kdone = k;
    save_checkpoint_atomic(ckpt,kdone,y0,Y1,Y2,t1,t2,p1,p2);
    fprintf('[ckpt] 氧化 %d/%d  t=%.3e s  本窗 %.1f s  累计 %.0f s\n', ...
            k, nS, t2(k+1), toc(tw), toc(tStart));
    if toc(tStart) > WALL_BUDGET
        fprintf('[wall] 预算耗尽, 已存 checkpoint, 退出等重排\n');
        if batchStartupOptionUsed && isempty(getenv('CALIB_NO_EXIT'))
            exit(0);                 % 独立腿模式: 退出让调度器续投
        else
            return;                  % pool worker / 交互: 只返回, 不杀进程
        end
    end
end

% ---------- 后处理 ----------
fprintf('[done] 两段完成, 后处理 -> %s\n', outdir);
sel = round(linspace(1, nS+1, 10*p.num_output+1));
postprocess_decouple(Y1(:,sel), t1(sel), Y2(:,sel), t2(sel), p1, outdir);
delete(ckpt);
% 完成标记必须最后写: 全部 csv 落盘之后。硬杀在 postprocess 中途 -> 无标记 -> 重跑,
% 不会把写了一半的 csv 当成结果 (见 leg_is_complete.m)。
fid = fopen(fullfile(outdir,'_COMPLETE'), 'w');
fprintf(fid, '%s\ncase=%s dose=%g\n', datestr(now,'yyyy-mm-dd HH:MM:SS'), case_tag, p.dose);
fclose(fid);
if batchStartupOptionUsed && isempty(getenv('CALIB_NO_EXIT')), exit(0); end
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

function save_checkpoint_atomic(ckpt,kdone,y0,Y1,Y2,t1,t2,p1,p2)
tmp = [ckpt '.tmp'];
save(tmp, 'kdone','y0','Y1','Y2','t1','t2','p1','p2','-v7.3');
[ok,msg] = movefile(tmp,ckpt,'f');
assert(ok, 'checkpoint atomic replace failed: %s', msg);
end

function absTol = build_abstol(M, N, p)
% V/I 沿用共用的绝对容差 p.atol_def (默认 1e-13)。
%
% 这是一个【已知的折中】, 不是理想设定, 记在这里免得再被"优化"一次:
% ode15s 的 threshold = AbsTol/RelTol (odearguments.m:154), 误差权重
% invwt = 1./max(|y|, threshold) (ode15s.m:536)。1e-13/1e-4 = 1e-9 高于 V 的
% 地板 1e-13、更远高于 I 的地板 1e-30, 所以缺陷场实际处在误差控制之下方,
% 非负性靠 NonNegative 维持, log() 一侧靠 rhs_aks 传下去的物理地板兜底。
%
% 试过按各场地板收紧 (V->1e-17, I->1e-34) 让缺陷场真正被解出来, 结果是氧化段
% 的步长被缺陷场扩散模 (dx^2/(D_V*C) ~ 5e-8 s) 卡死, 9000 s 的窗推进不了
% (36 s 墙钟只走 8.5e-5 s)。而"把缺陷场冻住"只在 decouple 腿成立 ——
% full couple 模式下辐照与氧化同时发生, 缺陷场必须是活的。所以维持原设定。
aD = getf(p,'atol_def', 1e-13);
absTol = zeros(M,1);
absTol(      1 : 2*N)      = aD;                             % V, I
absTol(2*N + 1 : 6*N)      = getf(p,'atol_metal', 1e-7);     % Cr,Fe,Ni,Si
absTol(6*N + 1 : 6*N+p.ny) = getf(p,'atol_O',     1e-6);     % O
absTol(6*N + p.ny + 1 : M) = getf(p,'atol_oxide', 1e-5);     % 4 氧化物
end

function idx = build_nonneg(M, N, p)
% 沿用原来的全场非负约束。缺陷场的容差在误差控制之下方 (见 build_abstol),
% 所以需要 NonNegative 来保证 V/I 不变号。它会把越界分量置成【精确 0】
% (ode15s.m:767), 而 V/I/金属都要进 log() —— 这一侧由 rhs_aks 传给
% J_all_via_medium 的物理地板兜住, 不会再出 log(0) = -Inf。
% p.nonneg_defects=false 可把 V/I 移出约束, 但那样必须同时收紧它们的 AbsTol,
% 否则 V/I 会自由变负。
if getf(p,'nonneg_defects', true)
    idx = 1:M;                 % V, I, 金属, O, 4 氧化物
else
    idx = 2*N + 1 : M;         % 仅金属 + O + 4 氧化物
end
end

function v = getf(p, name, dflt)
% 取 p 的字段, 缺失或空则用默认值 (兼容 build_p / 旧 checkpoint)
if isfield(p, name) && ~isempty(p.(name)), v = p.(name); else, v = dflt; end
end
