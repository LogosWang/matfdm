function ok = leg_is_complete(repo, case_tag, dose)
%LEG_IS_COMPLETE  一条腿是否真正跑完 —— 全流程唯一的完成判据。
%
%   判据 = 目录里有 _COMPLETE 标记 且 四个氧化物 final csv 都非空。
%   标记由 run_ckpt_decouple 在后处理全部落盘之后最后写入, 所以:
%     * 硬杀在 postprocess 中途 -> 有半截 csv 但没标记 -> 判为未完成, 重跑
%       (若只看 "csv 存在且非空", 被杀在最后一个 csv 写一半时会误判完成,
%        把截断数据当结果喂给 CMA)
%   参数一致性由 run_calibration_case 的 params.txt 戳另行保证。

ok = false;
root = fullfile(repo, 'decouple', char(case_tag), sprintf('dose%g', dose));
if ~isfile(fullfile(root, '_COMPLETE')), return; end
names = {'Cr2O3','Fe3O4','FeCr2O4','SiO2'};
for i = 1:numel(names)
    d = dir(fullfile(root, [names{i} '_final.csv']));
    if isempty(d) || d.bytes == 0, return; end
end
ok = true;
end
