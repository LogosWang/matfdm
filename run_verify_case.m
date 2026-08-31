function run_verify_case(case_tag, dose, mult, oxi_hours, num_ckpt)
%RUN_VERIFY_CASE  用标定选出的一组乘子, 跑一条长时氧化曲线供与实验对照。
%
%   和 run_calibration_case 的区别只有三点:
%     - 氧化时长与采样点由参数给 (de051500/de151500 用的是 1500 h / 150 点),
%       不再用 build_p_decouple 里的 500 h / 50 点;
%     - keep_traj 强制打开 —— 前沿随时间的曲线要从 fields_timeseries.mat 里取,
%       不存轨迹就没有时间序列可比;
%     - 不判成功、不写指标, 结果留给 verify_fronts.py 去算前沿与实验的偏差。
%
%   物理参数的来源与标定完全一致: build_p_decouple 的基线, config.json 的
%   overrides, 再乘上这十个乘子 (绑定关系走 apply_mult, 两边共用一份)。
%
%   输出: <MATFDM_RUN>/decouple/<case_tag>/dose<dose>/
%   断点: <MATFDM_RUN>/checkpoint/<case_tag>/decouple_dose<dose>/

arguments
    case_tag  (1,1) string
    dose      (1,1) double
    mult      (1,10) double
    oxi_hours (1,1) double = 1500
    num_ckpt  (1,1) double = 150
end

root_run = run_root();
cfg      = read_run_config();
root     = fullfile(root_run, 'decouple', char(case_tag), sprintf('dose%g', dose));

p = build_p_decouple(dose);

% config.json 的 overrides: 与标定同一个入口, 保证验证跑的是同一套物理
ov = cfg.overrides;
if ~isempty(ov) && isstruct(ov)
    fn = fieldnames(ov);
    for i = 1:numel(fn)
        p.(fn{i}) = ov.(fn{i});
    end
end

[p, vals] = apply_mult(p, mult);
p.rundir    = root_run;
p.case_tag  = case_tag;
p.oxi_time  = oxi_hours * 3600;
p.num_ckpt  = num_ckpt;
p.keep_traj = true;            % 时间序列是这次的目的, 必须留

% ---- 参数指纹: 改了任何影响物理的东西, 旧结果自动作废重算 ----
extra = [getdef(p,'eff',1), getdef(p,'rOM',1), getdef(p,'slab',1), getdef(p,'DO0',NaN), ...
         getdef(p,'dose_rate',NaN), getdef(p,'irr_time',NaN), p.oxi_time, p.num_ckpt, ...
         getdef(p,'nx',NaN), getdef(p,'ny',NaN), getdef(p,'Ks',NaN), ...
         getdef(p,'recomb_rate',NaN), getdef(p,'Dgb',NaN), ...
         getdef(p,'FeCr2O4mass',NaN), getdef(p,'FeCr2O4den',NaN), ...
         getdef(p,'f0V',NaN), getdef(p,'f0I',NaN)];
want  = sprintf('%.17g\n', [mult(:); vals(:); extra(:)]);
stamp = fullfile(root, 'params.txt');
if isfile(stamp) && ~strcmp(strtrim(fileread(stamp)), strtrim(want))
    fprintf('[stale] %s dose=%g 参数指纹不符, 清掉旧结果与断点重算\n', case_tag, dose);
    ckptdir = fullfile(root_run, 'checkpoint', char(case_tag), sprintf('decouple_dose%g', dose));
    if exist(root,'dir'),    rmdir(root, 's');    end
    if exist(ckptdir,'dir'), rmdir(ckptdir, 's'); end
end
if ~exist(root,'dir'), mkdir(root); end
fid = fopen(stamp,'w');  fprintf(fid,'%s',want);  fclose(fid);

fprintf('[verify] %s dose=%g  %g h / %d 采样点  eff=%g rOM=%g\n', ...
        case_tag, dose, oxi_hours, num_ckpt, getdef(p,'eff',1), getdef(p,'rOM',1));
fprintf('[params] kCr=%.9g kFe=%.9g kSi=%.9g kspin=%.9g ', vals(1:4));
fprintf('DCr2O3O=%.9g DFe3O4=%.9g DFeCr2O4=%.9g DSiO2=%.9g kRobin=%.9g E_mag=%.9g\n', vals(5:10));

run_ckpt_decouple(p);
end

function v = getdef(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = double(s.(f)); else, v = d; end
end
