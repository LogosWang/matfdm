%% 一个 parpool 同时跑全部作业, 见 run_batch。不想跑的行注释掉即可。
clearvars; clear rhs_aks;

nworkers = 6;

%        mode        value   flat  oxi_h  num_ckpt
jobs = {
        'decouple',  0.0,    '',   [],    []        % de0
        'decouple',  0.5,    '',   [],    []        % de05
        'decouple',  3.0,    '',   [],    []        % de30
        'decouple',  0.5,    'Cr', [],    []        % flat
        'decouple',  0.5,    'Si', [],    []
        'decouple',  3.0,    'Cr', [],    []
        'decouple',  3.0,    'Si', [],    []
        'decouple',  0.5,    '',   1500,  150       % de051500
        'decouple',  1.5,    '',   1500,  150       % de151500
        'couple',    0,      '',   [],    []        % 非 decouple: 三个典型剂量率 (dpa/s)
        'couple',    3e-7,   '',   [],    []
        'couple',    1e-6,   '',   [],    []
       };

run_batch(jobs, nworkers);
