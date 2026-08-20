function r = run_root()
%RUN_ROOT  本次运行的数据根目录 —— 全部结果/断点/指标/状态都写在这里。
%
%   由环境变量 MATFDM_RUN 指定。未设置时回退到代码目录, 以兼容
%   maincp/de0 这类直接调用的旧用法。
%
%   代码目录始终只读、只有一份; 想跑多套配置就建多个运行目录, 天然隔离:
%   路径不重叠, 互相看不见对方的 checkpoint、指标和 CMA 状态。

r = getenv('MATFDM_RUN');
if isempty(r)
    r = fileparts(mfilename('fullpath'));
    return
end
if ~exist(r, 'dir')
    error('run_root:missing', 'MATFDM_RUN 指向的目录不存在: %s', r);
end
end
