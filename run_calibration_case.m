function run_calibration_case(case_tag, dose, mult)
% 跑一条隔离的解耦标定腿。
% mult 顺序: [kCr kFe kSi kspin DCr2O3O DFe3O4 DFeCr2O4 DSiO2 kRobin E_mag]
%
% 数据全部写进 run_root() (= $MATFDM_RUN), 代码目录只读。
% 配置来自 <run>/config.json, 其中 overrides 字段在 build_p_decouple 之后
% 逐字段覆盖到 p —— 改物理参数不需要动源码。
arguments
    case_tag (1,1) string
    dose (1,1) double
    mult (1,10) double = ones(1,10)
end

root_run = run_root();
cfg  = read_run_config();
root = fullfile(root_run, 'decouple', char(case_tag), sprintf('dose%g', dose));

p = build_p_decouple(dose);

% ---- config.json 的 overrides: 唯一的物理参数改动入口 ----
ov = cfg.overrides;
if ~isempty(ov) && isstruct(ov)
    fn = fieldnames(ov);
    for i = 1:numel(fn)
        p.(fn{i}) = ov.(fn{i});
    end
end
p.rundir   = root_run;
p.keep_traj = logical(cfg.keep_traj);

base = [p.kCr p.kFe p.kSi p.kspin p.DCr2O3O p.DFe3O4 ...
        p.DFeCr2O4 p.DSiO2 p.kRobin p.E_mag];

% ---- 参数指纹 = 乘子 + 基线 + 影响物理的全部标量 ----
% 任何一处变动(基线值、级联效率、化学计量、网格、时长、覆盖项)都会让旧腿
% 自动作废重算, 不会出现"改了物理但旧结果被当成新结果"的静默污染。
extra = [getdef(p,'eff',1), getdef(p,'rOM',1), getdef(p,'slab',1), getdef(p,'DO0',NaN), ...
         getdef(p,'dose_rate',NaN), getdef(p,'irr_time',NaN), getdef(p,'oxi_time',NaN), ...
         getdef(p,'nx',NaN), getdef(p,'ny',NaN), getdef(p,'num_ckpt',NaN), ...
         getdef(p,'Ks',NaN), getdef(p,'recomb_rate',NaN), getdef(p,'Dgb',NaN), ...
         getdef(p,'FeCr2O4mass',NaN), getdef(p,'FeCr2O4den',NaN), ...
         getdef(p,'E_Cr',NaN), getdef(p,'E_Si',NaN), getdef(p,'E_spin',NaN), ...
         getdef(p,'f0V',NaN), getdef(p,'f0I',NaN)];
want  = sprintf('%.17g\n', [mult(:); base(:); extra(:)]);
stamp = fullfile(root, 'params.txt');

if isfile(stamp) && ~strcmp(strtrim(fileread(stamp)), strtrim(want))
    ckptdir = fullfile(root_run, 'checkpoint', char(case_tag), sprintf('decouple_dose%g', dose));
    fprintf('[stale] %s dose=%g 参数指纹不符, 归档旧结果与 checkpoint 后重算\n', case_tag, dose);
    stale = fullfile(root_run, 'decouple', char(case_tag), ...
                     sprintf('dose%g_stale_%s', dose, datestr(now,'yyyymmdd_HHMMSS')));
    try, movefile(root, stale, 'f'); catch, rmdir(root,'s'); end
    if exist(ckptdir,'dir'), rmdir(ckptdir,'s'); end
end

if isfile(stamp) && leg_is_complete(root_run, case_tag, dose)
    fprintf('[skip] %s dose=%g 已完成\n', case_tag, dose);
    return
end

if ~exist(root,'dir'), mkdir(root); end
fid = fopen(stamp, 'w');  fprintf(fid, '%s', want);  fclose(fid);

% 乘子施加与两处绑定走 apply_mult —— 验证入口 run_verify_case 用的是同一份,
% 免得改了一边忘了另一边。
[p, vals] = apply_mult(p, mult);
p.case_tag = case_tag;

fprintf('[case] %s dose=%g  run=%s  eff=%g rOM=%g front_thick=%g\n', ...
        case_tag, dose, cfg.run_id, getdef(p,'eff',1), getdef(p,'rOM',1), cfg.front_thick);
fprintf('[params] kCr=%.9g kFe=%.9g kSi=%.9g kspin=%.9g ', vals(1:4));
fprintf('DCr2O3O=%.9g DFe3O4=%.9g DFeCr2O4=%.9g DSiO2=%.9g kRobin=%.9g E_mag=%.9g\n', vals(5:10));
run_ckpt_decouple(p);
end

function v = getdef(p, name, default)
if isfield(p, name), v = double(p.(name)); else, v = default; end
end
