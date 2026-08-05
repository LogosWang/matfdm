function metrics = extract_calibration_metrics(case_tag)
% Extract interpolated 1 nm total-oxide fronts and metal-atom inventories.
doses = [0 0.5 3]; target = [40 60 100];
names = {'Cr2O3','Fe3O4','FeCr2O4','SiO2'};
metrics = struct('dose',cell(1,3),'front_nm',[],'residual_nm',[], ...
    'oxide_integrals_nm2',[],'metal_atom_inventory',[], ...
    'metal_atom_percent',[],'cr_atom_major',[]);
for i = 1:3
    d = doses(i); tag = sprintf('%g',d);
    root = fullfile(fileparts(mfilename('fullpath')),'decouple',char(case_tag),['dose' tag]);
    first = readmatrix(fullfile(root,[names{1} '_final.csv']));
    profiles = zeros(numel(first),4);           % ny 由文件决定, 不写死
    profiles(:,1) = first(:);
    for j = 2:4
        col = readmatrix(fullfile(root,[names{j} '_final.csv']));
        profiles(:,j) = col(:);
    end
    total = sum(profiles,2); above = find(total >= 1.0);
    if isempty(above)
        front = 0;
    else
        k = above(end); front = k-1;
        if k < numel(total) && total(k+1) < 1 && total(k) ~= total(k+1)
            front = (k-1) + (total(k)-1)/(total(k)-total(k+1));
        end
    end
    oxint = trapz(0:size(profiles,1)-1, profiles, 1);
    fu = oxint .* [5.22e-21/151.99, 5.17e-21/231.53, ...
                  5.37e-21/234.38, 2.2e-21/60.08];
    atoms = [2*fu(1)+2*fu(3), 3*fu(2)+fu(3), fu(4)];
    atom_pct = 100*atoms/sum(atoms);
    metrics(i).dose = d; metrics(i).front_nm = front;
    metrics(i).residual_nm = front-target(i);
    metrics(i).oxide_integrals_nm2 = oxint;
    metrics(i).metal_atom_inventory = atoms;
    metrics(i).metal_atom_percent = atom_pct;
    metrics(i).cr_atom_major = atoms(1) == max(atoms);
end
out = fullfile(fileparts(mfilename('fullpath')),'calibration','metrics');
if ~exist(out,'dir'), mkdir(out); end
save(fullfile(out,[char(case_tag) '.mat']),'metrics');
% csv 是 CMA 的唯一输入, 必须原子写: 先写 .tmp 再改名。
% 直写的话被硬杀在中途会留下半截 csv, 优化器读到残缺行 -> fitness 污染。
csvfile = fullfile(out,[char(case_tag) '.csv']);
tmpfile = [csvfile '.tmp'];
fid=fopen(tmpfile,'w');
fprintf(fid,['dose,front_nm,residual_nm,Cr2O3_int,Fe3O4_int,FeCr2O4_int,SiO2_int,' ...
             'Cr_atom_inventory,Fe_atom_inventory,Si_atom_inventory,Cr_atom_pct,Fe_atom_pct,Si_atom_pct,Cr_atom_major\n']);
for i=1:3
    fprintf(fid,'%.6g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.12g,%.12g,%.12g,%.9g,%.9g,%.9g,%d\n', ...
        metrics(i).dose,metrics(i).front_nm,metrics(i).residual_nm, ...
        metrics(i).oxide_integrals_nm2,metrics(i).metal_atom_inventory, ...
        metrics(i).metal_atom_percent,metrics(i).cr_atom_major);
end
fclose(fid);
[ok,msg] = movefile(tmpfile, csvfile, 'f');
assert(ok, 'metrics csv atomic replace failed: %s', msg);
end
