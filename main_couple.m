%% 一个 parpool 同时跑非 decouple 的三个典型剂量率 (dpa/s), 见 run_batch。不想跑的行注释掉即可。
clearvars; clear rhs_aks;

nworkers = 3;

%        mode        value   flat  oxi_h  num_ckpt
jobs = {
        'couple',    0,      '',   [],    []
        'couple',    3e-7,   '',   [],    []
        'couple',    1e-6,   '',   [],    []
       };

run_batch(jobs, nworkers);
