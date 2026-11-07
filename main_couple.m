%% couple / decouple 三组对照, 一个 parpool 六个 worker 同时跑, 见 run_batch。
% 每组同剂量率、同剂量、同氧化时长:
%   couple   辐照与氧化同时, 时长 t = dose/rate
%   decouple 先以同一 rate 预辐照到 dose (irr_time = dose/rate), 再零剂量氧化同样的 t
% 改 rate 两边一起变 (decouple 的剂量率由第 6 列覆盖, 不用 build_p_decouple 的默认值)。
% 结果存 couplecompare/rate<剂量率>_dose<剂量>/{couple,decouple}/
clearvars; clear rhs_aks;

nworkers = 6;
rate  = 6e-6;                 % dpa/s
doses = [0.5, 3.0, 5.0];      % dpa

%        mode        value   flat  oxi_h  num_ckpt  rate
jobs = cell(0, 6);
for d = doses
    t_h = d / rate / 3600;    % 暴露时长 (h)
    jobs(end+1, :) = {'couple',   rate, '', t_h, [], []  };   %#ok<SAGROW>
    jobs(end+1, :) = {'decouple', d,    '', t_h, [], rate};   %#ok<SAGROW>
end

run_batch(jobs, nworkers, 'couplecompare');
