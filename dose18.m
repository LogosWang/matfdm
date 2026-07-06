%% 参数（全部挂在 p 下）
p.dim   = 2;
p.nx    = 50;
p.ny    = 50;

p.dt    = 1e-5;
p.GBrecovert  = 0.8 * p.dt;       % 显式 Euler 用；ode15s 也会用这个值
p.dx    = 0.4;
p.dy = 1;
p.t_end = 1e7;

p.V_init = 1e-13;
p.V_DBC  = 1e-13;
p.I_init = 1e-13;
p.I_DBC  = 1e-13;
p.Ks = 1e-3;
DCrV = 4.55e4;
DFeV = 3.21e4;
DNiV = 2.68e4;
DSiV = 5e4;
p.DV = [DCrV, DFeV, DNiV,DSiV];
DCrI = 1.5e4;
DFeI = 1.5e4;
DNiI = 1.5e4;
DSiI = 3e4;
p.DI = [DCrI,DFeI,DNiI,DSiI];
p.f0V = 0.8;
p.f0I = 0.7;
p.dose_rate   = 1e-8;
p.recomb_rate = 1e4;

p.Cr_init = 0.18;   p.Cr_DCB = 0.18;

p.Fe_init = 0.71;   p.Fe_DCB = 0.71;
p.Ni_init = 0.10;   p.Ni_DCB = 0.10;
p.Si_init = 0.01;   p.Si_DCB = 0.01;
p.O_init = 0.0; p.O_DCB = 1.0;
p.Cr2O3_init = 0.0;
p.Fe3O4_init = 0.0;
p.NiFe2O4_init = 0.0;
p.SiO2_init = 0.0;
% ---- 穿膜输运 (nm^2/s; 换算: 1e-17 cm2/s = 1e-3 nm2/s) ----

p.DCr2O3O  = 1e-5;              % 实测锚点: chromite晶界 D_O = 2e-18~1e-17 cm2/s @325C
                                %  (你现在的 1e-5 比实测低 20~100x, 标定内层生长速率时留意)
p.DCr2O3Fe = 2e-5;              % 与 O 同量级起步 (Robertson: Fe 晶界扩散限速)
p.DCr2O3Ni = 5e-6;              % = 1e-2 x DFe (OSPE/DFT + 573K放大; 区间 1e-2~1e-3)

p.DOout    = 2e-4;              % = 100 x DCr2O3O (外层疏松, 只需"足够大", 不敏感)
p.DCr2O3  = p.DCr2O3O;
p.DFe3O4 = p.DOout;
p.DNiFe2O4 = p.DOout;
p.DSiO2    = 0.01;  
% ---- 界面动力学 (nm/s) ----
p.kCr = 1e-3; p.kSi = 1e-4;     % 物理含义: 线性->抛物线交叉厚度 L* = D/k ≈ 2 nm
p.kFe = 1e-4; p.kNi = 1e-4;     %  L* 取 0.5~5 nm 都合理; 四个先取等值, 数据逼你再分
% ---- 热力学门控 (无量纲, C_O 归一化定义下) ----
p.E_Si = 0;  p.E_Cr = 0;        % Ellingham 定量证实为零
p.E_mag  = 0.0;                % Fe3O4 门控 (开启时用; 你要关就置 0)
p.E_trev = 0.0;                 % trevorite 门控, 区间 0.1~1 (开启时用)
% ---- 数值 ----
p.Lmin = 0.3;                   % nm, 单分子层正则化
p.epsP = 1e-5;                  % 必须 << 最小非零 E (E_mag=1e-4 时取 1e-5; E全零时 1e-3 即可)
p.epsC = 1e-12; p.tolNode = 1e-12;
% ---- 物性 ----
p.kdiss = 0;                    % SiO2 溶解, 先关
% ---- 删除: p.DNiO, p.NiOden, p.NiOmass (NiO 通道已废) ----
p.slab = 1;
p.DO0 = 0.1;
p.DOmax = 10;
p.alpha = 2.0;
p.oxide_character = 0.08;
p.NA=6.02e23;
p.Cr2O3den=5.22e-21;
p.Cr2O3mass = 151.99;

p.Fe3O4den = 5.17e-21;
p.Fe3O4mass = 231.53;

p.NiFe2O4den = 5.37e-21;
p.NiFe2O4mass = 234.38;

p.SiO2den = 2.2e-21;
p.SiO2mass = 60.08;
p.Nden = 87;
p.solver = 1;          % 0 = 显式 Euler；1 = ode15s

if p.dim ==2
    V    = ones(p.ny, p.nx) * p.V_init;    V(:,1)      = p.V_DBC;
    I     = ones(p.ny,p.nx) * p.I_init;    I(:,1)      = p.I_DBC;
    CCr  = ones(p.ny, p.nx) * p.Cr_init;   CCr(:,p.nx) = p.Cr_DCB;
    CFe  = ones(p.ny, p.nx) * p.Fe_init;   CFe(:,p.nx) = p.Fe_DCB;
    CNi  = ones(p.ny, p.nx) * p.Ni_init;   CNi(:,p.nx) = p.Ni_DCB;
    CSi  = ones(p.ny, p.nx) * p.Si_init;   CSi(:,p.nx) = p.Si_DCB;
    CO  = ones(p.ny, 1) * p.O_init;    CO(1,1) = p.O_DCB;
    CCr2O3  = ones(p.ny, 1) * p.Cr2O3_init;
    CFe3O4  = ones(p.ny, 1) * p.Fe3O4_init;
    CNiFe2O4  = ones(p.ny, 1) * p.NiFe2O4_init;
    CSiO2  = ones(p.ny, 1) * p.SiO2_init;
end


%% ===== ode15s 分支 =====
%% ===== ode15s 分支 =====
N   = p.nx * p.ny;                                  % 2D 单场长度
M   = 6*N + 5*p.ny;                                 % y0 总长度

y0  = [V(:); I(:); CCr(:); CFe(:); CNi(:); CSi(:); ...
       CO(:); CCr2O3(:); CFe3O4(:); CNiFe2O4(:); CSiO2(:)];

assert(length(y0) == M, '初值向量长度不匹配');

% AbsTol 分场
absTol = zeros(M, 1);

% V / I: 跨 1e-13 → 3e-6 共 7 个量级
% 1e-16 太死, 但太松会让 (J_V - J_I) 噪声主导晶格速度
absTol(1 : 2*N)                = 1e-12;

% CCr/CFe/CNi/CSi: 满浓度 ~0.7, 但 GB 列会塌到 1e-10 量级
% 1e-4 在塌陷区相当于"随便走", 收紧到 1e-7
absTol(2*N + 1 : 6*N)          = 1e-7;

absTol(6*N + 1 : 6*N + p.ny)   = 1e-6;

absTol(6*N + p.ny + 1 : M)     = 1e-5;

% opts = odeset( ...
%     'RelTol',      1e-6, ...                       % 1e-4 → 1e-6, 杀晶格速度噪声
%     'AbsTol',      absTol, ...
%     'NonNegative', 1:M, ...                         % 覆盖所有 11 个场
%     'JPattern',    jpattern_aks(p.nx, p.ny), ...
%     'BDF',         'on', ...                        % 显式开 BDF, 对强刚性更稳
%     'MaxOrder',    2, ...                           % 限到 2 阶 → L-stable, 长时段不漂
%     'Stats',       'on', ...
%     'OutputFcn',   @(t,y,flag) myprogress(t,y,flag,p.t_end));
% 
% disp(opts.OutputFcn) 
% fprintf('Starting ode15s...\n');
% tic;
% sol = ode15s(@(t,y) rhs_aks(t,y,p), [0 p.t_end], y0, opts);
% toc;

opts = odeset( ...
    'RelTol',      1e-6, ...
    'AbsTol',      absTol, ...
    'NonNegative', 2*N+1:M, ...
    'JPattern',    jpattern_aks(p.nx, p.ny), ...
    'OutputFcn',   @(t,y,flag) myprogress(t,y,flag,p.t_end), ...
    'Stats',       'on');

% disp(opts.OutputFcn)
fprintf('Starting ode23tb...\n');
tic;
sol = ode23tb(@(t,y) rhs_aks(t,y,p), [0 p.t_end], y0, opts);
toc;


% --- 时间点采样 ---
t_out = linspace(0, p.t_end, 101);
Y     = deval(sol, t_out);
nt    = numel(t_out);
ny    = p.ny;
nx    = p.nx;

% --- 2D 场切片 + reshape 成 ny × nx × nt ---
V_t  = reshape(Y(        1 :   N, :), ny, nx, nt);
I_t  = reshape(Y(    N + 1 : 2*N, :), ny, nx, nt);
Cr_t = reshape(Y(  2*N + 1 : 3*N, :), ny, nx, nt);
Fe_t = reshape(Y(  3*N + 1 : 4*N, :), ny, nx, nt);
Ni_t = reshape(Y(  4*N + 1 : 5*N, :), ny, nx, nt);
Si_t = reshape(Y(  5*N + 1 : 6*N, :), ny, nx, nt);

% --- 1D 场（沿 y）：直接 ny × nt，无需 reshape ---
base       = 6 * N;
O_t        = Y(base +         1 : base +    ny, :);
Cr2O3_t    = Y(base +    ny + 1 : base +  2*ny, :);
Fe3O4_t      = Y(base +  2*ny + 1 : base +  3*ny, :);
NiFe2O4_t      = Y(base +  3*ny + 1 : base +  4*ny, :);
SiO2_t     = Y(base +  4*ny + 1 : base +  5*ny, :);


%% ===== 输出目录（本次 run 的所有文件都进这里）=====
outdir = fullfile(pwd, sprintf('results_dose%.0e', p.dose_rate));
% 同剂量重复跑会覆盖; 想保留历史就用带时间戳的版本:
% outdir = fullfile(pwd, sprintf('results_dose%.0e_%s', p.dose_rate, datestr(now,'mmdd_HHMM')));
if ~exist(outdir, 'dir'), mkdir(outdir); end
savepng = @(name) exportgraphics(gcf, fullfile(outdir, [name '.png']), 'Resolution', 300);
% R2020a 以前的版本用: savepng = @(name) print(gcf, fullfile(outdir,[name '.png']), '-dpng', '-r300');

% --- 落盘：完整时间轨迹 ---
save(fullfile(outdir, 'fields_timeseries.mat'), ...
     'V_t','I_t','Cr_t','Fe_t','Ni_t','Si_t', ...
     'O_t','Cr2O3_t','Fe3O4_t','NiFe2O4_t','SiO2_t', 'p',...
     '-v7.3');

% --- 落盘：最终时刻快照 ---
writematrix(V_t  (:,:,end),  fullfile(outdir, 'V_final.csv'));
writematrix(I_t  (:,:,end),  fullfile(outdir, 'I_final.csv'));
writematrix(Cr_t (:,:,end),  fullfile(outdir, 'Cr_final.csv'));
writematrix(Fe_t (:,:,end),  fullfile(outdir, 'Fe_final.csv'));
writematrix(Ni_t (:,:,end),  fullfile(outdir, 'Ni_final.csv'));
writematrix(Si_t (:,:,end),  fullfile(outdir, 'Si_final.csv'));
writematrix(O_t    (:, end), fullfile(outdir, 'O_final.csv'));
writematrix(Cr2O3_t(:, end), fullfile(outdir, 'Cr2O3_final.csv'));
writematrix(Fe3O4_t  (:, end), fullfile(outdir, 'Fe3O4_final.csv'));
writematrix(NiFe2O4_t(:, end), fullfile(outdir, 'NiFe2O4_final.csv'));
writematrix(SiO2_t (:, end), fullfile(outdir, 'SiO2_final.csv'));

% --- 最终时刻 2D / 1D 回填 ---
V     = V_t   (:, :, end);
I     = I_t   (:, :, end);
CCr   = Cr_t  (:, :, end);
CFe   = Fe_t  (:, :, end);
CNi   = Ni_t  (:, :, end);
CSi   = Si_t  (:, :, end);
CO     = O_t     (:, end);
CCr2O3 = Cr2O3_t (:, end);
CFe3O4   = Fe3O4_t   (:, end);
CNiFe2O4   = NiFe2O4_t   (:, end);
CSiO2  = SiO2_t  (:, end);

%% ===== 绘图 =====
x = (0:nx-1) * p.dx;
y = (0:ny-1) * p.dy;
j_mid  = round(ny/2);
idx    = 1:10:nt;
colors = parula(numel(idx));

%% --- 图 1-6：2D 场沿 x 的 profile（y=中线），不同时刻 ---
fields_2D = {V_t,  I_t,  Cr_t, Fe_t, Ni_t, Si_t};
labels_2D = {'Vacancy','Interstitial','Cr','Fe','Ni','Si'};
for f = 1:6
    figure(f); clf; hold on; box on;
    for k = 1:numel(idx)
        i = idx(k);
        profile = squeeze(fields_2D{f}(j_mid, :, i));
        plot(x, profile, 'LineWidth', 2.5, ...
             'Color', colors(k, :), ...
             'DisplayName', sprintf('t = %.2e s', t_out(i)));
    end
    xlabel('x (nm)',  'FontSize', 24)
    ylabel([labels_2D{f} ' Concentration'], 'FontSize', 24)
    title(sprintf('%s, dose rate = %.2g dpa/s', labels_2D{f}, p.dose_rate), 'FontSize', 18)
    set(gca, 'FontSize', 20)
    legend('show', 'Location', 'best', 'FontSize', 14);
    savepng(sprintf('%s_profile_x', labels_2D{f}));
end

% %% --- 图 7-12：最终时刻 2D 热图 ---
% for f = 1:6
%     figure(6+f); clf;
%     imagesc(x, y, fields_2D{f}(:,:,end));
%     set(gca, 'YDir', 'normal');
%     axis equal tight; colorbar;
%     xlabel('x (nm)', 'FontSize', 20)
%     ylabel('y (nm)', 'FontSize', 20)
%     title(sprintf('%s at t=%.2e s, dose rate = %.2g dpa/s', labels_2D{f}, t_out(end), p.dose_rate), 'FontSize', 18)
%     set(gca, 'FontSize', 16)
%     savepng(sprintf('%s_heatmap_final', labels_2D{f}));
% end

%% --- 图 13-16：1D 场（O 和 4 个氧化物）沿 y 的 profile，不同时刻 ---
% --- 氧浓度 O：单独画 ---
figure(13); clf; hold on; box on;
for k = 1:numel(idx)
    i = idx(k);
    plot(y, O_t(:, i), 'LineWidth', 2.5, ...
         'Color', colors(k, :), ...
         'DisplayName', sprintf('t = %.2e s', t_out(i)));
end
xlabel('y (nm) — along GB', 'FontSize', 24)
ylabel('O Concentration', 'FontSize', 24)
title(sprintf('O along GB, dose rate = %.2g dpa/s', p.dose_rate), 'FontSize', 18)
set(gca, 'FontSize', 20)
legend('show', 'Location', 'best', 'FontSize', 14);
savepng('O_along_GB');

% --- 氧化物厚度：Cr2O3 / Fe3O4 / NiFe2O4 / SiO2 ---
oxides_1D   = {Cr2O3_t, Fe3O4_t, NiFe2O4_t, SiO2_t};
oxide_lbl   = {'Cr_2O_3', 'Fe_3O_4', 'NiFe_2O_4', 'SiO_2'};
oxide_fname = {'Cr2O3', 'Fe3O4', 'NiFe2O4', 'SiO2'};      % 文件名用纯文本
for f = 1:4
    figure(14+f); clf; hold on; box on;
    for k = 1:numel(idx)
        i = idx(k);
        plot(y, oxides_1D{f}(:, i), 'LineWidth', 2.5, ...
             'Color', colors(k, :), ...
             'DisplayName', sprintf('t = %.2e s', t_out(i)));
    end
    xlabel('y (nm) — along GB', 'FontSize', 24)
    ylabel([oxide_lbl{f} ' thickness (nm)'], 'FontSize', 24)
    title(sprintf('%s along GB, dose rate = %.2g dpa/s', oxide_lbl{f}, p.dose_rate), 'FontSize', 18)
    set(gca, 'FontSize', 20)
    legend('show', 'Location', 'best', 'FontSize', 14);
    savepng(sprintf('%s_along_GB', oxide_fname{f}));
end

%% --- 图 17：所有氧化物在最终时刻叠加（直接看占比）---
figure(19); clf; hold on; box on;
plot(y, Cr2O3_t(:, end), 'LineWidth', 3, 'DisplayName', 'Cr_2O_3');
plot(y, Fe3O4_t(:, end),   'LineWidth', 3, 'DisplayName', 'Fe_3O_4');
plot(y, NiFe2O4_t(:, end),   'LineWidth', 3, 'DisplayName', 'NiFe_2O_4');
plot(y, SiO2_t(:, end),  'LineWidth', 3, 'DisplayName', 'SiO_2');
plot(y, Cr2O3_t(:,end) + Fe3O4_t(:,end) + NiFe2O4_t(:,end) + SiO2_t(:,end), ...
     'LineWidth', 3, 'LineStyle', '--', 'DisplayName', 'Total oxide');
xlabel('y (nm) — along GB', 'FontSize', 24)
ylabel(sprintf('Oxide Concentration at t = %.2e s', t_out(end)), 'FontSize', 24)
title(sprintf('Oxide composition at end, dose rate = %.2g dpa/s', p.dose_rate), 'FontSize', 18)
set(gca, 'FontSize', 20)
legend('show', 'Location', 'best', 'FontSize', 14);
savepng('Oxide_composition_final');

%% --- 图 18：氧化前沿可视化（O 浓度的 log 热图，时间 vs y）---
figure(20); clf;
imagesc(t_out, y, log10(max(O_t, 1e-20)));    % log scale，钳零防 -Inf
set(gca, 'YDir', 'normal');
colorbar;
xlabel('t (s)',              'FontSize', 20)
ylabel('y (nm) — along GB',  'FontSize', 20)
title(sprintf('log_{10}(C_O) over time, dose rate = %.2g dpa/s', p.dose_rate), 'FontSize', 18)
set(gca, 'FontSize', 16)
savepng('O_spacetime_log');

%% --- 图 19：Cr_2O_3 累积的时间-空间图（看前沿推进）---
figure(21); clf;
imagesc(t_out, y, Cr2O3_t);
set(gca, 'YDir', 'normal');
colorbar;
xlabel('t (s)',              'FontSize', 20)
ylabel('y (nm) — along GB',  'FontSize', 20)
title(sprintf('C_{Cr_2O_3} over time, dose rate = %.2g dpa/s', p.dose_rate), 'FontSize', 18)
set(gca, 'FontSize', 16)
savepng('Cr2O3_spacetime');

fprintf('本次 run 全部输出已写入: %s\n', outdir);