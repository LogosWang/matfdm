function run_flat_solute_test(dose_list, solutes, opts)
% Cr / Si 效果解耦测试: 正常 RIS 后, 把 Cr 或 Si 场重置为 initial 均匀场, 再做氧化。
% parpool 并行, 每个 (dose, solute) 一个 run_ckpt_decouple 作业。
%
% 用法:  run_flat_solute_test([0.5 1.5 3.0], {'Cr','Si'})
%        run_flat_solute_test([0.5 3.0], {'Cr','Si',''}, struct('nworkers',4))
%
% solutes: 'Cr' -> 交接时 Cr 全场 = p.Cr_init (保留 Si 的 RIS), 测 Si 单独的效果
%          'Si' -> 交接时 Si 全场 = p.Si_init (保留 Cr 的 RIS), 测 Cr 单独的效果
%          ''   -> 不重置 (对照组, 与 de*.m 的正常运行相同, 写进同一个正常目录)
%          差额由 Fe 补, 见 run_ckpt_decouple 交接段。
% 参数:   其余全部来自 build_p_decouple(dose), 不在这里改。
%
% 输出:   <codedir>/decouple/dose<x>_<closure>_flatCr/ 与 _flatSi/ (对照组用正常目录)
% checkpoint: <codedir>/checkpoint/decouple_dose<x>_<closure>_flatCr/ 等, 支持续算。
%            同一 dose 的各作业各自重跑一次辐照段 (互不共享)。
%
% opts (可选): nworkers (默认 min(作业数, 6))

if nargin < 3, opts = struct(); end
if ischar(solutes), solutes = {solutes}; end
bad = solutes(~ismember(solutes, {'Cr','Si',''}));
if ~isempty(bad)
    error('run_flat_solute_test:solute', 'solutes 只能是 ''Cr'' / ''Si'' / '''', 收到 %s', strjoin(bad, ', '));
end

% ---------- 作业列表 ----------
jobs = struct('dose',{},'solute',{},'p',{});
for dose = dose_list(:)'
    for s = 1:numel(solutes)
        p = build_p_decouple(dose);
        p.handoff_flat_solute = solutes{s};
        jobs(end+1) = struct('dose',dose,'solute',solutes{s},'p',p); %#ok<AGROW>
    end
end
nj = numel(jobs);
fprintf('[flat] %d 作业:\n', nj);
for k = 1:nj
    fprintf('    dose=%-5g reset=%s\n', jobs(k).dose, label(jobs(k).solute));
end

% ---------- parpool ----------
nw = getf(opts, 'nworkers', min(nj, 6));
pool = gcp('nocreate');
if isempty(pool) || pool.NumWorkers ~= nw
    delete(pool);  pool = parpool('local', nw);
end
wall = zeros(nj, 1);
parfor k = 1:nj
    tw = tic;
    run_ckpt_decouple(jobs(k).p);
    wall(k) = toc(tw);
    fprintf('[flat] 作业 %d/%d (dose=%g, reset=%s) 完成, %.0f s\n', ...
            k, nj, jobs(k).dose, label(jobs(k).solute), wall(k));
end
fprintf('[flat] 全部完成\n');
end

function s = label(solute)
if isempty(solute), s = 'none'; else, s = solute; end
end

function v = getf(s, name, dflt)
if isfield(s, name) && ~isempty(s.(name)), v = s.(name); else, v = dflt; end
end
