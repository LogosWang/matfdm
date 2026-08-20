function ok = leg_is_complete(run_dir, case_tag, dose)
%LEG_IS_COMPLETE  一条腿是否真正跑完 —— 全流程唯一的完成判据。
%
%   判据 = 目录里有 _COMPLETE 标记 且 四个氧化物 final csv 都非空。
%   标记由 run_ckpt_decouple 在后处理全部落盘之后最后写入, 所以硬杀在
%   postprocess 中途只会留下半截 csv 而没有标记 -> 判为未完成, 重跑。
%   (只看 "csv 存在且非空" 会把写了一半的文件当成结果喂给优化器。)
%
%   run_dir 省略时取 run_root()。参数一致性由 run_calibration_case 的
%   params.txt 指纹另行保证。

if nargin < 1 || isempty(run_dir), run_dir = run_root(); end
ok = false;
root = fullfile(run_dir, 'decouple', char(case_tag), sprintf('dose%g', dose));
if ~isfile(fullfile(root, '_COMPLETE')), return; end
names = {'Cr2O3','Fe3O4','FeCr2O4','SiO2'};
for i = 1:numel(names)
    d = dir(fullfile(root, [names{i} '_final.csv']));
    if isempty(d) || d.bytes == 0, return; end
end
ok = true;
end
