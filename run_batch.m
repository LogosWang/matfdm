function run_batch(jobs, nworkers)
% 一个 parpool 同时跑 decouple 与非 decouple 作业。入口脚本见 main_all.m。
%
% jobs: cell 表, 每行 {mode, value, flat, oxi_h, num_ckpt}
%   mode     'decouple' (run_ckpt_decouple) / 'couple' (run_ckpt)
%   value    decouple: dose (dpa);  couple: dose rate (dpa/s)
%   flat     decouple 的 Cr/Si 解耦测试: 'Cr' / 'Si' / '' (不重置); couple 不用
%   oxi_h    氧化时长 (h), [] = build_p_decouple 默认
%   num_ckpt 窗数, [] = build_p_decouple 默认
% 输出目录由 run_ckpt_decouple / run_ckpt 决定, 作业之间互不覆盖。
%
% 单个作业报错不影响其他作业, 最后统一汇报。worker 上的 fprintf 要等该作业结束才显示,
% 运行中的进度看 checkpoint.mat 的修改时间。

nj = size(jobs, 1);
ps = cell(nj, 1);  names = cell(nj, 1);  iscouple = false(nj, 1);
for k = 1:nj
    [mode, value, flat, oxi_h, nck] = jobs{k, :};
    switch mode
        case 'decouple'
            p = build_p_decouple(value);
            p.handoff_flat_solute = flat;
            names{k} = sprintf('decouple dose=%g flat=%s', value, flat);
        case 'couple'
            p = build_p(value);
            iscouple(k) = true;
            names{k} = sprintf('couple rate=%g', value);
        otherwise
            error('run_batch:mode', '第 %d 行 mode 必须是 ''decouple'' / ''couple'', 现在是 ''%s''', k, mode);
    end
    if ~isempty(oxi_h)
        p.oxi_time = oxi_h * 3600;
        if iscouple(k), p.t_end = p.oxi_time; end
        names{k} = sprintf('%s %gh', names{k}, oxi_h);
    end
    if ~isempty(nck), p.num_ckpt = nck; end
    p.no_exit = true;                   % 不让 run_ckpt* 在 batch 模式下 exit 掉 worker
    ps{k} = p;
    fprintf('[batch] %2d  %s\n', k, names{k});
end

% ---------- parpool ----------
pool = gcp('nocreate');
if isempty(pool) || pool.NumWorkers ~= nworkers
    delete(pool);  pool = parpool('local', nworkers);
end
% 每个作业单独派发: 默认分组会把长作业绑在同一个 worker 上排队, 空闲 worker 却拿不到活
popts = parforOptions(pool, 'RangePartitionMethod','fixed', 'SubrangeSize',1);

wall = zeros(nj, 1);  err = cell(nj, 1);
parfor (k = 1:nj, popts)
    tw = tic;
    try
        if iscouple(k), run_ckpt(ps{k}); else, run_ckpt_decouple(ps{k}); end
    catch ME
        err{k} = sprintf('%s: %s', ME.identifier, ME.message);
    end
    wall(k) = toc(tw);
    fprintf('[batch] 结束 %d/%d (%s), %.0f s\n', k, nj, names{k}, wall(k));
end

% ---------- 汇总 ----------
nfail = 0;
for k = 1:nj
    if isempty(err{k})
        fprintf('[batch] 完成  %-40s %8.0f s\n', names{k}, wall(k));
    else
        nfail = nfail + 1;
        fprintf(2, '[batch] 失败  %-40s %8.0f s\n    %s\n', names{k}, wall(k), err{k});
    end
end
if nfail > 0
    error('run_batch:failed', '%d/%d 个作业失败, 见上面的汇总; 已完成的窗在各自 checkpoint 里, 重跑会续算', nfail, nj);
end
end
