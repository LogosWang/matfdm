%% matfdm 本地入口
% 参数来自 build_p (与 run_ckpt/NERSC 共用同一份, 不漂移)。
% 保存 + 后处理来自 postprocess_matfdm (与 run_ckpt 共用, 与 checkpoint 版一模一样)。
% 想要 checkpoint / NERSC 版: 用 run_ckpt(p) 代替本脚本的求解段。
 
clearvars; clear rhs_aks;
 
p = build_p(5e-8);
run_ckpt(p); 