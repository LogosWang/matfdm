function status = run_leg_worker(repo, rundir, tag, dose, mult, wallBudget)
%RUN_LEG_WORKER  parpool worker 上跑一条标定腿, 永不抛异常。
%   隔离: 每个 process worker 是独立进程 (persistent/工作区/句柄互不可见);
%         结果与 checkpoint 按 case_tag 分目录; 参数指纹由 run_calibration_case 校验。
%   返回: 'complete' | 'wallclock' | 'error:<msg>'

status = 'error:unset';
logf = '';
try
    maxNumCompThreads(1);                       % 防止 90 腿互相抢线程
    addpath(repo);
    cd(repo);
    % parfeval worker 不继承客户端环境变量, 必须显式设
    setenv('MATFDM_RUN', rundir);
    % worker 会被复用跑多条腿: 清掉上一条腿可能留下的 persistent 状态
    clear rhs_aks solve_node
    if isfinite(wallBudget)
        setenv('WALL_BUDGET', sprintf('%d', round(wallBudget)));
    else
        setenv('WALL_BUDGET', '');              % 不限时: 跑到自然结束或被 SLURM 杀
    end
    setenv('CALIB_NO_EXIT', '1');               % 禁止 run_ckpt_decouple 调 exit
    setenv('CALIB_ENABLE_PLOTS', getenv_default('CALIB_ENABLE_PLOTS','0'));
    setenv('CALIB_KEEP_TRAJ',    getenv_default('CALIB_KEEP_TRAJ','0'));

    % 每条腿独立日志 (worker 的 stdout 会和别的腿交错, 单独存一份便于排错)
    logdir = fullfile(rundir,'calibration','logs');
    if ~exist(logdir,'dir'), mkdir(logdir); end
    logf = fullfile(logdir, sprintf('%s_dose%g.log', tag, dose));
    diary(logf);  diary on;

    run_calibration_case(tag, dose, mult);

    if leg_is_complete(rundir, tag, dose)
        status = 'complete';
    else
        status = 'wallclock';                   % 已存 checkpoint, 等下一个作业续
    end
catch err
    status = ['error:' err.identifier ':' err.message];
    try
        f = fullfile(rundir,'calibration','logs', sprintf('%s_dose%g_error.log', tag, dose));
        fid = fopen(f,'a');
        fprintf(fid, '%s %s\n%s\n', datestr(now), err.message, getReport(err,'extended'));
        fclose(fid);
    catch
    end
end
try, diary off; catch, end
end

function v = getenv_default(name, default)
v = getenv(name);
if isempty(v), v = default; end
end
