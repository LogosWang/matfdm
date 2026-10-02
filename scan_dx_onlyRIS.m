function scan_dx_onlyRIS(dose, dx_list, opts)
% RIS 段 (onlyRIS) 的 dx 网格敏感性扫描: 两种 GB 缺陷汇 (Dirichlet / Robin) × 多个 dx,
% parpool 并行, 每个 (bc, dx) 一个 run_onlyRIS 作业。
%
% 用法:  scan_dx_onlyRIS(3.0, [0.25 0.5 1 2])
%        scan_dx_onlyRIS(3.0, [0.5 1 2], struct('ny',100,'nworkers',4))
%
% 网格: x 方向物理总长固定 Lx = 50 nm (opts.Lx 可改), 每个 dx 取 nx = Lx/dx + 1。
%       要求 dx 整除 Lx (0.25/0.5/1/2 都行), 否则报错, 不允许 Lx 偷偷变化。
%       ny 默认沿用 build_p; onlyRIS 沿 y 均匀, 可用 opts.ny 调小省时间。
% 参数: 其余全部来自 build_p_decouple(dose); Robin 腿用 build_p 里的 kgbV/kgbI。
%
% 输出:  <codedir>/scan_dx/Dirich/dx<dx>/   与   <codedir>/scan_dx/Robin/dx<dx>/
%           每个作业的常规后处理 (postprocess_onlyRIS: csv + png + fields_timeseries.mat)
%        <codedir>/scan_dx/<Dirich|Robin>/<El>_profile_vs_dx.png   4 个金属沿 x 的 GB 剖面叠加 (仅 p.make_plots=true)
%        <codedir>/scan_dx/<Dirich|Robin>/profiles_vs_dx.mat        叠加图的数据
%        <codedir>/scan_dx/summary.csv                              bc, dx, nx, Lx(=50), 各元素 GB 值, 墙钟
% checkpoint: 默认不存 (每个作业单次 ode15s 跑完, 中断即重跑); opts.ckpt=true 才按窗存到
%             <codedir>/checkpoint/scan_dx_<bc>_dx<dx>/ 并支持续算。
%
% opts (可选): Lx (默认 50), ny, num_ckpt, nworkers (默认 min(作业数, 6)), root (默认 'scan_dx'), ckpt (默认 false)

if nargin < 3, opts = struct(); end
codedir = fileparts(mfilename('fullpath'));
root    = fullfile(codedir, getf(opts, 'root', 'scan_dx'));
bcs     = {'dirichlet', 'robin'};
bcdir   = {'Dirich',    'Robin'};

p0 = build_p_decouple(dose);
Lx = getf(opts, 'Lx', 50);                     % nm, x 方向总长, 所有 dx 严格一致
bad = dx_list(abs(Lx./dx_list - round(Lx./dx_list)) > 1e-9);
if ~isempty(bad)
    error('scan_dx_onlyRIS:LxNotDivisible', 'dx = %s 不能整除 Lx = %g nm, 请换 dx 或 opts.Lx', mat2str(bad), Lx);
end
if isfield(opts,'ny'),       p0.ny       = opts.ny;       end
if isfield(opts,'num_ckpt'), p0.num_ckpt = opts.num_ckpt; end

% ---------- 作业列表 ----------
jobs = struct('bc',{},'bcdir',{},'dx',{},'p',{},'outdir',{});
for b = 1:2
    for dx = dx_list(:)'
        p = p0;
        p.dx = dx;  p.nx = round(Lx/dx) + 1;   % (nx-1)*dx == Lx 精确
        p.gb_defect_bc = bcs{b};
        p.outdir  = fullfile(root, bcdir{b}, sprintf('dx%g', dx));
        p.ckptdir = fullfile(codedir, 'checkpoint', sprintf('scan_dx_%s_dx%g', bcdir{b}, dx));
        p.skip_post = true;                  % worker 上不画图, 回到 client 再后处理
        p.no_ckpt   = ~getf(opts, 'ckpt', false);   % 默认不存 checkpoint, 一次积分到底
        jobs(end+1) = struct('bc',bcs{b},'bcdir',bcdir{b},'dx',dx,'p',p,'outdir',p.outdir); %#ok<AGROW>
    end
end
nj = numel(jobs);
fprintf('[scan_dx] dose=%g dpa, Lx=%g nm, ny=%d, %d 作业:\n', dose, Lx, p0.ny, nj);
for k = 1:nj
    fprintf('    %-9s dx=%-5g nx=%-4d Lx_actual=%g\n', jobs(k).bc, jobs(k).dx, jobs(k).p.nx, (jobs(k).p.nx-1)*jobs(k).dx);
end

% ---------- parpool ----------
nw = getf(opts, 'nworkers', min(nj, 6));
pool = gcp('nocreate');
if isempty(pool) || pool.NumWorkers ~= nw
    delete(pool);  pool = parpool('local', nw);
end
wall = zeros(nj, 1);
parfor k = 1:nj
    tw = tic;
    run_onlyRIS(jobs(k).p);
    wall(k) = toc(tw);
    fprintf('[scan_dx] 作业 %d/%d (%s, dx=%g) 完成, %.0f s\n', k, nj, jobs(k).bc, jobs(k).dx, wall(k));
end

% ---------- client 上后处理: 每个作业常规输出 + 每种 bc 的 dx 叠加图 ----------
metals = {'Cr','Fe','Ni','Si'};
rows = {};
for b = 1:2
    sel = find(strcmp({jobs.bc}, bcs{b}));
    prof = struct();  xs = struct();
    for k = sel
        S = load(fullfile(jobs(k).outdir, 'raw_timeseries.mat'));
        postprocess_onlyRIS(S.Y, S.t_out, S.p1, jobs(k).outdir);
        q = S.p1;  N = q.nx*q.ny;
        tag = sprintf('dx%g', jobs(k).dx);  tagf = matlab.lang.makeValidName(tag);
        xs.(tagf) = (0:q.nx-1) * q.dx;
        gb = zeros(1,4);
        for m = 1:4
            C2D = reshape(S.Y((m+1)*N+1:(m+2)*N, end), q.ny, q.nx);
            prof.(tagf).(metals{m}) = mean(C2D, 1);          % 沿 y 平均的 x 剖面
            gb(m) = prof.(tagf).(metals{m})(1);
        end
        rows(end+1,:) = {bcs{b}, jobs(k).dx, q.nx, (q.nx-1)*q.dx, gb(1), gb(2), gb(3), gb(4), wall(k)}; %#ok<AGROW>
    end
    outb = fullfile(root, bcdir{b});
    save(fullfile(outb, 'profiles_vs_dx.mat'), 'prof', 'xs', 'dose', 'Lx');
    tags = fieldnames(prof);  cols = lines(numel(tags));
    make_plots = isfield(p0,'make_plots') && ~isempty(p0.make_plots) && p0.make_plots;
    for m = 1:4
        if ~make_plots, break; end           % 出图关闭: 只留 profiles_vs_dx.mat 与 summary.csv
        fh = figure('Visible','off'); clf; hold on; box on;
        for i = 1:numel(tags)
            plot(xs.(tags{i}), 100*prof.(tags{i}).(metals{m}), '-o', 'LineWidth',2, 'MarkerSize',4, ...
                 'Color',cols(i,:), 'DisplayName',strrep(tags{i},'dx','dx = '));
        end
        xlabel('x (nm), 0 = GB','FontSize',18); ylabel([metals{m} ' (at.%)'],'FontSize',18);
        title(sprintf('%s at %g dpa, GB sink = %s', metals{m}, dose, bcs{b}),'FontSize',16);
        set(gca,'FontSize',14); legend('show','Location','best');
        drawnow; exportgraphics(fh, fullfile(outb, [metals{m} '_profile_vs_dx.png']), 'Resolution', 200);
        close(fh);
    end
end
T = cell2table(rows, 'VariableNames', {'bc','dx','nx','Lx','Cr_GB','Fe_GB','Ni_GB','Si_GB','wall_s'});
writetable(T, fullfile(root, 'summary.csv'));
disp(T);
fprintf('[scan_dx] 全部完成 -> %s\n', root);
end

function v = getf(s, name, dflt)
if isfield(s, name) && ~isempty(s.(name)), v = s.(name); else, v = dflt; end
end
