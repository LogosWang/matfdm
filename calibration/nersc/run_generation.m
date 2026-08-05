function run_generation()
%RUN_GENERATION  作业期间常驻的标定驱动 (NERSC 单节点 + parpool)。
%
%   一个 MATLAB 进程持有一个 parpool, 跨代复用 (不反复拉起 MATLAB)。
%   每代: 读 state.json 的 batchNN_cases -> parfeval 提交 nCase*3 条腿 ->
%         全部回收后逐 case 抽指标 -> 判成功 -> 调 CMA-ES 出下一代 -> 继续。
%
%   环境变量:
%     CALIB_REPO_DIR     仓库根 (默认 = 本文件上上层)
%     CALIB_WORKERS      pool worker 数 (默认 90 = 30 case x 3 dose)
%     CALIB_POPULATION   每代 case 数 (默认 30; 同时传给 CMA-ES)
%     CALIB_WALL_BUDGET  本作业可用秒数 (submit.sh 设为 walltime - 余量)
%     CALIB_GEN_RESERVE  开新一代所需的最少剩余秒数 (默认 5400)
%     CALIB_ENDPOINT_TOL 成功判据的端点容差 nm (默认 3)
%     CALIB_PYTHON       python3 可执行文件 (默认 python3)
%
%   墙钟耗尽: 腿自己按 WALL_BUDGET 存 checkpoint 退出, 本函数干净返回,
%   submit.sh 续投下一个作业, 未完成的腿从 checkpoint 续算 (幂等)。

here = fileparts(mfilename('fullpath'));
repo = getenv('CALIB_REPO_DIR');
if isempty(repo), repo = fileparts(fileparts(here)); end
addpath(repo);  addpath(here);

calib   = fullfile(repo, 'calibration');
statef  = fullfile(calib, 'state.json');
logdir  = fullfile(calib, 'logs');
if ~exist(logdir, 'dir'), mkdir(logdir); end

budget   = envnum('CALIB_WALL_BUDGET',  inf);
reserve  = envnum('CALIB_GEN_RESERVE',  5400);
workers  = envnum('CALIB_WORKERS',      90);
popsize  = envnum('CALIB_POPULATION',   30);
tol      = envnum('CALIB_ENDPOINT_TOL', 3);
python   = getenv('CALIB_PYTHON');
if isempty(python), python = 'python3'; end
gentool  = fullfile(here, 'gen_tool.py');

tStart = tic;
if isfinite(budget)
    say('[boot] repo=%s workers=%d pop=%d budget=%.0f s', repo, workers, popsize, budget);
else
    say('[boot] repo=%s workers=%d pop=%d 无代码侧时限 (跑到 SLURM 杀)', ...
        repo, workers, popsize);
end

% ---------- parpool: 整个作业只开一次 ----------
pool = gcp('nocreate');
if isempty(pool)
    cl = parcluster('Processes');
    store = fullfile(scratchdir(), 'matlab_jobstore', ...
                     sprintf('job%s_pid%d', jobid(), feature('getpid')));
    if ~exist(store, 'dir'), mkdir(store); end
    cl.JobStorageLocation = store;
    cl.NumWorkers = workers;
    pool = parpool(cl, workers, 'IdleTimeout', inf);
end
say('[pool] %d workers 就绪, 耗时 %.0f s', pool.NumWorkers, toc(tStart));

% ---------- 代循环 ----------
while true
    % 哨兵: 命中或人工停止 (另一个作业写的 DONE, 或你 touch 的 STOP)
    if exist(fullfile(calib,'DONE'),'file') || exist(fullfile(calib,'STOP'),'file')
        say('[sentinel] 见到 DONE/STOP, 退出');
        break
    end
    % 默认 budget=inf: 不自我限时, 跑到 SLURM 杀为止。
    % 只有显式设了 CALIB_WALL_BUDGET 才会提前收手。
    if isfinite(budget) && toc(tStart) > budget - reserve
        say('[wall] 剩余不足一代 (%.0f s), 干净退出', budget - toc(tStart));
        break
    end

    batch = next_batch(statef);

    % 续跑摘要: 打印 CMA 持久状态 + 全历史 fitness (作业重启后一眼看出从哪捡起)
    [~, hist] = sh(sprintf('%s %s history %d', python, q(gentool), batch), ...
                   repo, popsize, python);
    fprintf('%s', hist);

    % 提议本代 (幂等: pending_batch 命中则原样重发, 不推进 CMA)
    rc = sh(sprintf('%s %s propose %d', python, q(gentool), batch), ...
            repo, popsize, python);
    if rc ~= 0 && batch > 1
        % 常见死锁: 上一代有 case 既没指标也没被熔断 -> CMA 拒绝 tell。
        % 一次性惩罚这些 case 后重试, 避免续投链无限重复同一个失败。
        say('[propose] 失败, 尝试惩罚上一代缺指标的 case 后重试');
        sh(sprintf('%s %s penalize-missing %d', python, q(gentool), batch-1), ...
           repo, popsize, python);
        rc = sh(sprintf('%s %s propose %d', python, q(gentool), batch), ...
                repo, popsize, python);
    end
    if rc ~= 0
        error('run_generation:propose', 'CMA-ES 提议失败, batch %d', batch);
    end
    cases = read_cases(statef, batch);
    say('[gen %02d] %d cases x 3 dose = %d legs', batch, numel(cases), 3*numel(cases));

    % ---- 撒腿 ----
    doses = [0, 0.5, 3];
    if isfinite(budget)
        legBudget = max(600, budget - toc(tStart) - 300);   % 腿自留 5 min 存盘
    else
        legBudget = inf;                                   % 不限时
    end
    F = parallel.FevalFuture.empty(0,1);
    meta = {};
    for i = 1:numel(cases)
        tag  = cases(i).case_tag;
        mult = cases(i).mult(:)';
        for d = doses
            if leg_is_complete(repo,tag, d), continue; end
            F(end+1,1) = parfeval(pool, @run_leg_worker, 1, ...
                                  repo, tag, d, mult, legBudget); %#ok<AGROW>
            meta{end+1} = sprintf('%s/dose%g', tag, d);            %#ok<AGROW>
        end
    end
    nTotal = numel(F);
    if nTotal == 0
        say('[gen %02d] 所有腿已完成 (续投恢复), 直接进入抽指标', batch);
    end

    % ---- 回收 (worker 内部已 try/catch, fetchNext 不会抛) ----
    attemptsFile = fullfile(here, 'attempts.json');
    A = load_attempts(attemptsFile);
    maxAttempts = envnum('CALIB_MAX_ATTEMPTS', 3);
    nDone = 0;  tGen = tic;
    while nDone < nTotal
        [idx, status] = fetchNext(F, 120);
        if isempty(idx)
            say('[gen %02d] 进行中 %d/%d, 本代已用 %.0f min', ...
                batch, nDone, nTotal, toc(tGen)/60);
            continue
        end
        nDone = nDone + 1;
        if startsWith(status, 'error')
            k = keyof(meta{idx});
            A.(k) = getfielddef(A, k, 0) + 1;
            save_attempts(attemptsFile, A);
            say('[leg] %-24s %s  (第 %d 次失败)', meta{idx}, status, A.(k));
        else
            say('[leg] %-24s %-10s (%d/%d, 本代 %.0f min)', ...
                meta{idx}, status, nDone, nTotal, toc(tGen)/60);
        end
    end

    % ---- 熔断: 反复失败的 case 写惩罚指标, 让 CMA 判它不可行并前进 ----
    dead = {};
    for i = 1:numel(cases)
        tag = cases(i).case_tag;
        for d = doses
            k = keyof(sprintf('%s/dose%g', tag, d));
            if ~leg_is_complete(repo,tag, d) && getfielddef(A, k, 0) >= maxAttempts
                dead{end+1} = tag; %#ok<AGROW>
                break
            end
        end
    end
    dead = unique(dead);
    for i = 1:numel(dead)
        sh(sprintf('%s %s penalize %d --tag %s', python, q(gentool), batch, dead{i}), ...
           repo, popsize, python);
        say('[dead] %s 连续失败 >=%d 次, 已写惩罚指标', dead{i}, maxAttempts);
    end

    % ---- 完整性: 有腿没跑完且未熔断 = 墙钟耗尽, 交给续投 ----
    incomplete = 0;
    for i = 1:numel(cases)
        if any(strcmp(cases(i).case_tag, dead)), continue; end
        for d = doses
            if ~leg_is_complete(repo,cases(i).case_tag, d), incomplete = incomplete + 1; end
        end
    end
    if incomplete > 0
        say('[gen %02d] %d 条腿未完成 (墙钟), 存盘退出等续投', batch, incomplete);
        break
    end

    % ---- 抽指标 ----
    for i = 1:numel(cases)
        tag = cases(i).case_tag;
        if exist(fullfile(calib,'metrics',[tag '.csv']), 'file'), continue; end
        try
            extract_calibration_metrics(tag);
        catch err
            say('[metrics] %s 失败: %s', tag, err.message);
            sh(sprintf('%s %s penalize %d --tag %s', python, q(gentool), batch, tag), ...
               repo, popsize, python);
        end
    end

    % ---- 判成功 ----
    [rc, out] = sh(sprintf('%s %s success %d --tol %g', ...
                           python, q(gentool), batch, tol), repo, popsize, python);
    say('[gen %02d] %s', batch, strtrim(out));
    w = regexp(out, 'WINNERS=(\S+)', 'tokens', 'once');
    if rc == 0 && ~isempty(w) && ~isempty(strtrim(w{1}))
        fid = fopen(fullfile(calib, 'DONE'), 'w');
        fprintf(fid, '%s\n', strtrim(w{1}));  fclose(fid);
        say('[done] 命中: %s', strtrim(w{1}));
        break
    end
    sh(sprintf('%s %s report %d', python, q(gentool), batch), repo, popsize, python);
end

say('[exit] 总耗时 %.1f h', toc(tStart)/3600);
end

% ===================================================================
function b = next_batch(statef)
% 已有的最大 batch: 若其 cases 已全部抽完指标则 +1, 否则续跑它。
b = 1;
if ~exist(statef, 'file'), return; end
s = jsondecode(fileread(statef));
f = fieldnames(s);
nums = [];
for i = 1:numel(f)
    t = regexp(f{i}, '^batch(\d+)_cases$', 'tokens', 'once');
    if ~isempty(t), nums(end+1) = str2double(t{1}); end %#ok<AGROW>
end
if isempty(nums), return; end
b = max(nums);
calib = fileparts(statef);
cases = read_cases(statef, b);
for i = 1:numel(cases)
    if ~exist(fullfile(calib,'metrics',[cases(i).case_tag '.csv']), 'file')
        return                      % 本代还没做完, 续跑本代
    end
end
b = b + 1;                          % 本代已完结, 进下一代
end

function cases = read_cases(statef, batch)
s = jsondecode(fileread(statef));
key = sprintf('batch%02d_cases', batch);
if ~isfield(s, key)
    error('run_generation:nocases', 'state.json 缺 %s', key);
end
c = s.(key);
if iscell(c), c = [c{:}]; end
cases = c(:)';
end

% 完成判据统一走仓库根的 leg_is_complete.m (要求 _COMPLETE 标记), 此处不再本地实现

function [rc, out] = sh(cmd, repo, popsize, ~)
env = sprintf(['CALIB_REPO_DIR=%s CALIB_POPULATION=%d '], q(repo), popsize);
[rc, out] = system([env ' ' cmd]);
end

function A = load_attempts(f)
A = struct();
if exist(f, 'file')
    try, A = jsondecode(fileread(f)); catch, A = struct(); end
end
end

function save_attempts(f, A)
try
    fid = fopen([f '.tmp'], 'w');  fprintf(fid, '%s', jsonencode(A));  fclose(fid);
    movefile([f '.tmp'], f, 'f');
catch
end
end

function k = keyof(s)
k = regexprep(s, '[^A-Za-z0-9]', '_');   % 'b01_c01_cma/dose0.5' -> 合法字段名
end

function v = getfielddef(S, k, default)
if isfield(S, k), v = S.(k); else, v = default; end
end

function v = envnum(name, default)
v = str2double(getenv(name));
if isnan(v), v = default; end
end

function s = q(p), s = ['"' char(p) '"']; end

function d = scratchdir()
d = getenv('SCRATCH');
if isempty(d) || ~exist(d,'dir'), d = tempdir; end
end

function s = jobid()
s = getenv('SLURM_JOB_ID');
if isempty(s), s = 'local'; end
end

function say(fmt, varargin)
fprintf(['[%s] ' fmt '\n'], datestr(now,'HH:MM:SS'), varargin{:});
end
