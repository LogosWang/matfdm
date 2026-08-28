function metrics = extract_calibration_metrics(case_tag)
%EXTRACT_CALIBRATION_METRICS  从腿的结果里抽出前沿与氧化金属库存。
%
%   前沿 = 总氧化物厚度 >= cfg.front_thick 的最深位置(线性插值到亚网格)。
%   阈值、剂量、靶值全部来自 <run>/config.json, 源码里不写死。
%   读写路径全部在 run_root() 下, 代码目录只读。
%
%   原子比例的口径:
%     分母 = Cr + Fe + Ni。Ni 在本模型里不进氧化物, 恒为 0, 所以模型侧
%     等价于 Cr/(Cr+Fe); 之所以把 Ni 写进分母, 是为了和实验靶值同口径 ——
%     实验里 Ni 确实有 0.9~3.9 at%, 归一化掉就等于把模型缺 Ni 这件事抹掉了。
%     SiO2 不计: 实际中它会被溶解, 不该占氧化物金属的份额。
%     Si 仍然输出, 但只作诊断 (与同一分母比), 不参与标定。
%
%   取样位置 (2026-08-28 改):
%     成分在 cfg.composition_depth 指定的深度上就地取样 (每个剂量一个深度,
%     与实验取样位置一致), 不再沿整条 GB 积分 —— 全长积分等于把前沿以内所有
%     深度混在一起平均, 和实验在某个固定深度上测的根本不是一回事。
%     取样深度处没有氧化物 (前沿还没推到那里) 时 at% 全部记 0, 由目标函数重罚。
%     库存 (metal_atom_inventory) 仍然是全长积分 —— 它约束的是氧化物里 Cr 的
%     总量随剂量单调下降, 本来就该是个全局量。
%
%   密度与分子量一律从 build_p_decouple 读, 不在这里另抄一份 —— 抄一份就
%   会漂 (FeCr2O4 改过一次密度/分子量, 两处都得记得改)。

cfg   = read_run_config();
root0 = run_root();
doses  = cfg.doses(:)';
target = cfg.targets(:)';
TH     = cfg.front_thick;
depth  = cfg.composition_depth(:)';        % 成分取样深度 nm, 每个剂量一个
if numel(depth) < numel(doses)
    error('extract:depth', 'composition_depth 只有 %d 项, 剂量有 %d 个', ...
          numel(depth), numel(doses));
end
names  = {'Cr2O3','Fe3O4','FeCr2O4','SiO2'};
nD     = numel(doses);

% ρ/M 的唯一来源。dose 传 0 只是为了拿到常数字段, 与剂量无关。
p0 = build_p_decouple(0);
rho_over_M = [p0.Cr2O3den   / p0.Cr2O3mass, ...
              p0.Fe3O4den   / p0.Fe3O4mass, ...
              p0.FeCr2O4den / p0.FeCr2O4mass, ...
              p0.SiO2den    / p0.SiO2mass];

metrics = struct('dose',cell(1,nD),'front_nm',[],'residual_nm',[], ...
    'comp_depth_nm',[],'oxide_integrals_nm2',[],'metal_atom_inventory',[], ...
    'metal_atom_percent',[],'cr_atom_major',[]);

for i = 1:nD
    d = doses(i);
    root = fullfile(root0,'decouple',char(case_tag),sprintf('dose%g',d));
    first = readmatrix(fullfile(root,[names{1} '_final.csv']));
    profiles = zeros(numel(first),4);           % ny 由文件决定, 不写死
    profiles(:,1) = first(:);
    for j = 2:4
        col = readmatrix(fullfile(root,[names{j} '_final.csv']));
        profiles(:,j) = col(:);
    end

    total = sum(profiles,2);  above = find(total >= TH);
    if isempty(above)
        front = 0;
    else
        k = above(end);  front = k-1;
        if k < numel(total) && total(k+1) < TH && total(k) ~= total(k+1)
            front = (k-1) + (total(k)-TH)/(total(k)-total(k+1));
        end
    end

    % ---- 库存: 沿 GB 全长积分 (每 nm 深度), 单位 nm² ----
    % 只用于"Cr 总量随剂量单调下降"这个约束, 那本来就是全局量。
    oxint = trapz(0:size(profiles,1)-1, profiles, 1);
    fu    = oxint .* rho_over_M;          % 分子式单位的物质的量 = 体积 × ρ/M
    % Cr2O3->2Cr, FeCr2O4->2Cr+1Fe, Fe3O4->3Fe, SiO2->1Si; Ni 不进氧化物
    atoms = [2*fu(1)+2*fu(3), 3*fu(2)+fu(3), fu(4), 0];   % Cr, Fe, Si, Ni

    % ---- 成分: 在实验的取样深度上就地取样 ----
    zs = depth(i);
    zg = (0:size(profiles,1)-1)';         % GB 深度坐标 nm (dy = 1)
    local  = interp1(zg, profiles, zs, 'linear', 0);      % 越界给 0
    lfu    = local(:)' .* rho_over_M;
    latoms = [2*lfu(1)+2*lfu(3), 3*lfu(2)+lfu(3), lfu(4), 0];
    ldenom = latoms(1) + latoms(2) + latoms(4);
    if ldenom > 0
        atom_pct = 100*latoms/ldenom;    % Si 那一项是诊断比值, 不参与标定
    else
        atom_pct = zeros(1,4);           % 该深度没有氧化物 -> 目标函数重罚
    end

    metrics(i).dose = d;
    metrics(i).front_nm = front;
    metrics(i).residual_nm = front - target(i);
    metrics(i).comp_depth_nm = zs;
    metrics(i).oxide_integrals_nm2 = oxint;
    metrics(i).metal_atom_inventory = atoms;
    metrics(i).metal_atom_percent = atom_pct;
    metrics(i).cr_atom_major = latoms(1) > latoms(2); % 取样处 Cr 是否多于 Fe (诊断)
end

out = fullfile(root0,'calibration','metrics');
if ~exist(out,'dir'), mkdir(out); end
save(fullfile(out,[char(case_tag) '.mat']),'metrics');

% csv 是优化器的唯一输入, 必须原子写: 直写被硬杀会留下残行 -> fitness 污染
csvfile = fullfile(out,[char(case_tag) '.csv']);
tmpfile = [csvfile '.tmp'];
fid = fopen(tmpfile,'w');
fprintf(fid,['dose,front_nm,residual_nm,comp_depth_nm,' ...
             'Cr2O3_int,Fe3O4_int,FeCr2O4_int,SiO2_int,' ...
             'Cr_atom_inventory,Fe_atom_inventory,Si_atom_inventory,Ni_atom_inventory,' ...
             'Cr_atom_pct,Fe_atom_pct,Si_atom_pct,Ni_atom_pct,Cr_atom_major\n']);
for i = 1:nD
    fprintf(fid,['%.6g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,' ...
                 '%.12g,%.12g,%.12g,%.12g,%.9g,%.9g,%.9g,%.9g,%d\n'], ...
        metrics(i).dose,metrics(i).front_nm,metrics(i).residual_nm, ...
        metrics(i).comp_depth_nm, ...
        metrics(i).oxide_integrals_nm2,metrics(i).metal_atom_inventory, ...
        metrics(i).metal_atom_percent,metrics(i).cr_atom_major);
end
fclose(fid);
[ok,msg] = movefile(tmpfile, csvfile, 'f');
assert(ok, 'metrics csv atomic replace failed: %s', msg);
end
