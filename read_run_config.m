function cfg = read_run_config()
%READ_RUN_CONFIG  读取本次运行的 config.json (带默认值填充与缓存)。
%
%   配置是唯一的真相来源: 想改阈值、级联效率、靶值、population, 改 config.json,
%   不改任何源码。config.json 里的 overrides 字段会在 build_p_decouple 之后
%   逐字段覆盖到 p 上, 所以物性/数值参数也不需要动 build_p。
%
%   缓存在 persistent 里, 每个 worker 进程只读一次盘。

persistent CACHED CACHED_PATH
root = run_root();
f = fullfile(root, 'config.json');
if ~isempty(CACHED) && strcmp(CACHED_PATH, f)
    cfg = CACHED;  return
end

cfg = struct();
if isfile(f)
    try
        cfg = jsondecode(fileread(f));
    catch err
        error('read_run_config:bad', 'config.json 解析失败 (%s): %s', f, err.message);
    end
end

% ---- 默认值 ----
cfg = setdef(cfg, 'run_id',        'default');
cfg = setdef(cfg, 'doses',         [0; 0.5; 3]);
cfg = setdef(cfg, 'targets',       [40; 60; 100]);
cfg = setdef(cfg, 'front_thick',   1.0);      % 前沿判据: 总氧化物厚度 nm
cfg = setdef(cfg, 'population',    40);
cfg = setdef(cfg, 'workers',       120);
cfg = setdef(cfg, 'middle_max',    70);       % 0.5 dpa 软带上限 nm
cfg = setdef(cfg, 'endpoint_band', 5);        % 端点硬约束 nm
cfg = setdef(cfg, 'endpoint_tol',  3);        % 成功判据端点容差 nm
cfg = setdef(cfg, 'max_attempts',  3);
cfg = setdef(cfg, 'keep_traj',     false);
cfg = setdef(cfg, 'seed',          20260804);
cfg = setdef(cfg, 'overrides',     struct());

CACHED = cfg;  CACHED_PATH = f;
end

function s = setdef(s, name, value)
if ~isfield(s, name) || isempty(s.(name)), s.(name) = value; end
end
