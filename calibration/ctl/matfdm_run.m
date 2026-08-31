function matfdm_run(varargin)
%MATFDM_RUN  编译成 standalone 的统一入口 —— 跑在 MATLAB Runtime 上, 不签 license。
%
%   NERSC 全校只有 16 个 MATLAB / 4 个 PCT 席位, 多节点作业必须用编译版
%   (docs.nersc.gov/applications/matlab)。MCR 根本不连 license server, 所以
%   编译之后这套流程占用 0 个席位。
%
%   子命令 (命令行参数都是字符串, 这里负责解析和转类型):
%     leg      <rundir> <tag> <dose> <mult逗号分隔> [wallBudget秒]
%              跑一条标定腿。退出码: 0=完成  10=墙钟到点已存断点  20=出错
%     verify   <rundir> <tag> <dose> <mult逗号分隔> [氧化小时数] [采样点数]
%              用标定选出的一组乘子跑一条长时氧化曲线 (默认 1500 h / 150 点),
%              强制存 fields_timeseries.mat 供前沿-时间曲线用。
%              退出码: 0=完成  10=墙钟到点已存断点  20=出错
%     metrics  <rundir> <tag>
%              抽这个 case 的三行指标。退出码: 0=成功  20=失败
%     baseline <outfile.json>
%              导出 build_p_decouple 的十个基线值 + 构建戳, 供后处理对齐
%              (后处理原本靠正则读 .m 源码; 源码改了没重编就会对不上)
%     selftest <rundir>
%              MCR 起得来吗? config 读得到吗? 基线算得出吗?
%
%   计算内核 (run_leg_worker / run_calibration_case / extract_calibration_metrics)
%   一行未改 —— 这里只做命令行到函数调用的转接。

if isempty(varargin)
    print_usage(); exit(64);
end
cmd = lower(strtrim(varargin{1}));
args = varargin(2:end);

try
    switch cmd
        case 'leg',      code = do_leg(args);
        case 'verify',   code = do_verify(args);
        case 'metrics',  code = do_metrics(args);
        case 'baseline', code = do_baseline(args);
        case 'selftest', code = do_selftest(args);
        otherwise
            fprintf(2, '未知子命令: %s\n', cmd); print_usage(); code = 64;
    end
catch err
    fprintf(2, 'matfdm_run 未捕获异常: %s\n%s\n', err.message, getReport(err,'extended'));
    code = 20;
end
exit(code);
end

% ===================================================================
function code = do_leg(a)
if numel(a) < 4
    fprintf(2, '用法: matfdm_run leg <rundir> <tag> <dose> <mult> [budget]\n'); code = 64; return
end
rundir = a{1};
tag    = string(a{2});
dose   = str2double(a{3});
mult   = parse_vec(a{4});
if numel(a) >= 5 && ~isempty(strtrim(a{5}))
    budget = str2double(a{5});
else
    budget = inf;
end
if isnan(dose) || numel(mult) ~= 10
    fprintf(2, 'dose 或 mult 解析失败 (mult 要 10 个逗号分隔的数)\n'); code = 64; return
end

% 已经跑完的腿直接跳过 —— 编排器也会查一遍, 这里再兜一次, 保证幂等
if leg_is_complete(rundir, tag, dose)
    fprintf('STATUS=complete (已完成, 跳过)\n'); code = 0; return
end

% repo 参数在编译版里没有源码目录可指; 给 ctfroot (存在且可读), 让
% run_leg_worker 里的 addpath/cd 变成无害操作。函数本身不用改。
repo = app_root();
status = run_leg_worker(repo, rundir, tag, dose, mult, budget);
fprintf('STATUS=%s\n', status);

if strcmp(status, 'complete')
    code = 0;
elseif strcmp(status, 'wallclock')
    code = 10;
else
    code = 20;
end
end

% ===================================================================
function code = do_verify(a)
if numel(a) < 4
    fprintf(2, '用法: matfdm_run verify <rundir> <tag> <dose> <mult> [小时] [采样点]\n');
    code = 64; return
end
rundir = a{1};
tag    = string(a{2});
dose   = str2double(a{3});
mult   = parse_vec(a{4});
hours  = 1500;  nck = 150;
if numel(a) >= 5 && ~isempty(strtrim(a{5})), hours = str2double(a{5}); end
if numel(a) >= 6 && ~isempty(strtrim(a{6})), nck   = str2double(a{6}); end
if isnan(dose) || numel(mult) ~= 10 || isnan(hours) || isnan(nck)
    fprintf(2, 'dose/mult/小时/采样点 解析失败 (mult 要 10 个逗号分隔的数)\n');
    code = 64; return
end

setenv('MATFDM_RUN', rundir);
% 已经跑完的直接跳过 (幂等): 有时间序列且有末态剖面就算完成
outdir = fullfile(rundir, 'decouple', char(tag), sprintf('dose%g', dose));
if isfile(fullfile(outdir,'fields_timeseries.mat')) && ...
   isfile(fullfile(outdir,'Cr2O3_final.csv')) && ...
   isfile(fullfile(outdir,'_COMPLETE'))
    fprintf('STATUS=complete (已完成, 跳过)\n'); code = 0; return
end

try
    run_verify_case(tag, dose, mult, hours, nck);
catch err
    fprintf(2, 'VERIFY=fail %s\n%s\n', err.message, getReport(err,'extended'));
    code = 20; return
end

if isfile(fullfile(outdir,'fields_timeseries.mat')) && isfile(fullfile(outdir,'_COMPLETE'))
    fprintf('STATUS=complete\n'); code = 0;
else
    fprintf('STATUS=wallclock\n'); code = 10;   % 墙钟到点, 已存断点等续投
end
end

% ===================================================================
function code = do_metrics(a)
if numel(a) < 2
    fprintf(2, '用法: matfdm_run metrics <rundir> <tag>\n'); code = 64; return
end
setenv('MATFDM_RUN', a{1});
try
    extract_calibration_metrics(string(a{2}));
    fprintf('METRICS=ok\n'); code = 0;
catch err
    fprintf(2, 'METRICS=fail %s\n', err.message); code = 20;
end
end

% ===================================================================
function code = do_baseline(a)
% 十个基线的快照。后处理 (show_best/export_best) 拿它来算"绝对值", 而不是
% 用正则去读 build_p_decouple.m 源码 —— 源码和二进制不同步时能当场看出来。
if isempty(a)
    fprintf(2, '用法: matfdm_run baseline <outfile.json>\n'); code = 64; return
end
names = {'kCr','kFe','kSi','kspin','DCr2O3O','DFe3O4','DFeCr2O4','DSiO2','kRobin','E_mag'};
p = build_p_decouple(0);
s = struct();
for i = 1:numel(names)
    s.(names{i}) = p.(names{i});
end
out = struct('baseline', s, 'build_commit', build_commit(), ...
             'matlab_version', version(), ...
             'generated', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fid = fopen(a{1}, 'w');
if fid < 0, fprintf(2, '写不了 %s\n', a{1}); code = 20; return; end
fprintf(fid, '%s\n', jsonencode(out, 'PrettyPrint', true));
fclose(fid);
fprintf('BASELINE=%s\n', a{1});
code = 0;
end

% ===================================================================
function code = do_selftest(a)
fprintf('=== matfdm_run selftest ===\n');
fprintf('MATLAB Runtime : %s\n', version());
fprintf('isdeployed     : %d\n', isdeployed());
fprintf('ctfroot        : %s\n', app_root());
fprintf('build commit   : %s\n', build_commit());
fprintf('MCR_CACHE_ROOT : %s\n', getenv('MCR_CACHE_ROOT'));
fprintf('maxNumCompThreads : %d\n', maxNumCompThreads());

p = build_p_decouple(0);
fprintf('build_p_decouple 通过: kCr=%.4g DSiO2=%.4g eff=%.4g\n', p.kCr, p.DSiO2, p.eff);

if ~isempty(a)
    setenv('MATFDM_RUN', a{1});
    fprintf('run_root()     : %s\n', run_root());
    cfg = read_run_config();
    fprintf('config 读到     : front_thick=%g population=%d doses=[%s]\n', ...
            cfg.front_thick, cfg.population, num2str(cfg.doses(:)'));
end
fprintf('=== selftest OK ===\n');
code = 0;
end

% ===================================================================
function v = parse_vec(s)
v = str2double(strsplit(strtrim(s), ','));
v = v(:)';
end

function r = app_root()
% 编译版给 ctfroot, 未编译(调试)时给源码目录
if isdeployed()
    r = ctfroot();
else
    r = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
end

function c = build_commit()
% 构建戳: 优先环境变量 (matfdm_mcr.sh 从产物目录的 BUILD_COMMIT 读了传进来),
% 其次产物目录里的文件。不塞进 CTF —— -a 进去的文件在 ctfroot 下路径不确定。
c = getenv('MATFDM_BUILD_COMMIT');
if ~isempty(c), c = strtrim(c); return; end
c = 'unknown';
try
    d = getenv('MATFDM_BUILD_DIR');
    if ~isempty(d)
        f = fullfile(d, 'BUILD_COMMIT');
        if isfile(f), c = strtrim(fileread(f)); end
    end
catch
end
end

function print_usage()
fprintf(2, [ ...
 'matfdm_run leg      <rundir> <tag> <dose> <mult逗号分隔> [budget]\n' ...
 'matfdm_run verify   <rundir> <tag> <dose> <mult> [小时] [采样点]\n' ...
 'matfdm_run metrics  <rundir> <tag>\n' ...
 'matfdm_run baseline <outfile.json>\n' ...
 'matfdm_run selftest [rundir]\n']);
end
