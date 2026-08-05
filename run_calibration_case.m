function run_calibration_case(case_tag, dose, mult)
% Run one isolated decoupled calibration leg.
% mult order: [kCr kFe kSi kspin DCr2O3O DFe3O4 DFeCr2O4 DSiO2 kRobin E_mag].
arguments
    case_tag (1,1) string
    dose (1,1) double
    mult (1,10) double = ones(1,10)
end

repo = fileparts(mfilename('fullpath'));
root = fullfile(repo, 'decouple', char(case_tag), sprintf('dose%g', dose));
stamp = fullfile(root, 'params.txt');
want  = sprintf('%.17g\n', mult);          % 参数指纹, 精确到二进制可复现

% ---- 参数指纹校验: 同名 case 换了参数, 必须清掉旧结果与旧 checkpoint ----
% 触发场景: cma_state.pkl 丢失后 CMA 重新 ask, 同名 case 拿到不同乘子。
% 不校验的话, 旧参数算出的结果/半路 checkpoint 会被当成新参数的结果, 污染 fitness。
if isfile(stamp)
    got = fileread(stamp);
    if ~strcmp(strtrim(got), strtrim(want))
        ckptdir = fullfile(repo, 'checkpoint', char(case_tag), ...
                           sprintf('decouple_dose%g', dose));
        fprintf('[stale] %s dose=%g 参数指纹不符, 清除旧结果与 checkpoint 后重算\n', ...
                case_tag, dose);
        stale = fullfile(repo, 'decouple', char(case_tag), ...
                         sprintf('dose%g_stale_%s', dose, datestr(now,'yyyymmdd_HHMMSS')));
        try, movefile(root, stale, 'f'); catch, rmdir(root,'s'); end
        if exist(ckptdir,'dir'), rmdir(ckptdir,'s'); end
    end
end

% ---- 幂等守卫: 参数一致且真正跑完 (含 _COMPLETE 标记) 则跳过 ----
if isfile(stamp) && leg_is_complete(repo, case_tag, dose)
    fprintf('[skip] %s dose=%g 已完成\n', case_tag, dose);
    return
end

if ~exist(root,'dir'), mkdir(root); end
fid = fopen(stamp, 'w');  fprintf(fid, '%s', want);  fclose(fid);

p = build_p_decouple(dose);
base = [p.kCr p.kFe p.kSi p.kspin p.DCr2O3O p.DFe3O4 ...
        p.DFeCr2O4 p.DSiO2 p.kRobin p.E_mag];
vals = base .* mult;
p.kCr = vals(1); p.kFe = vals(2); p.kSi = vals(3); p.kspin = vals(4);
p.DCr2O3O = vals(5); p.DCr2O3 = p.DCr2O3O;
p.DFe3O4 = vals(6); p.DFeCr2O4 = vals(7); p.DSiO2 = vals(8);
p.kRobin = vals(9); p.E_mag = vals(10); p.case_tag = case_tag;

fprintf('[case] %s dose=%g\n', case_tag, dose);
fprintf('[base] kCr=%.9g kFe=%.9g kSi=%.9g kspin=%.9g ', base(1:4));
fprintf('DCr2O3O=%.9g DFe3O4=%.9g DFeCr2O4=%.9g DSiO2=%.9g kRobin=%.9g E_mag=%.9g\n', base(5:10));
fprintf('[params] kCr=%.9g kFe=%.9g kSi=%.9g kspin=%.9g ', vals(1:4));
fprintf('DCr2O3O=%.9g DFe3O4=%.9g DFeCr2O4=%.9g DSiO2=%.9g kRobin=%.9g E_mag=%.9g\n', vals(5:10));
run_ckpt_decouple(p);
end
