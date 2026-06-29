%% 参数（全部挂在 p 下）
p.dim   = 2;
p.nx    = 10;
p.ny    = 10;

p.dt    = 1e-5;
p.GBrecovert  = 0.8 * p.dt;       % 显式 Euler 用；ode15s 也会用这个值
p.dx    = 5;
p.dy = 20;
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
p.dose_rate   = 0;
p.recomb_rate = 1e4;

p.Cr_init = 0.18;   p.Cr_DCB = 0.18;
p.Fe_init = 0.71;   p.Fe_DCB = 0.71;
p.Ni_init = 0.10;   p.Ni_DCB = 0.10;
p.Si_init = 0.01;   p.Si_DCB = 0.01;
p.O_init = 0.0; p.O_DCB = 1.0;
p.Cr2O3_init = 0.0;
p.Fe3O4_init = 0.0;
p.NiO_init = 0.0;
p.SiO2_init = 0.0;
p.kCr = 1e-4;
p.kSi = 1e-4;
p.kNi = 1e-4;
p.kFe = 1e-4;
p.DCr2O3 = 1e-5;
p.DFe3O4 = 0.003;
p.DNiO = 0.002;
p.DSiO2 = 0.01;
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

p.NiOden = 6.67e-21;
p.NiOmass = 74.69;

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
    CNiO  = ones(p.ny, 1) * p.NiO_init;
    CSiO2  = ones(p.ny, 1) * p.SiO2_init;
end


%% ===== ode15s 分支 =====
%% ===== ode15s 分支 =====
N   = p.nx * p.ny;                                  % 2D 单场长度
M   = 6*N + 5*p.ny;                                 % y0 总长度

y0  = [V(:); I(:); CCr(:); CFe(:); CNi(:); CSi(:); ...
       CO(:); CCr2O3(:); CFe3O4(:); CNiO(:); CSiO2(:)];

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
    'Stats',       'on', ...
    'OutputFcn',   @(t,y,flag) myprogress(t,y,flag,p.t_end));

disp(opts.OutputFcn)
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
NiO_t      = Y(base +  3*ny + 1 : base +  4*ny, :);
SiO2_t     = Y(base +  4*ny + 1 : base +  5*ny, :);


% --- 落盘：完整时间轨迹 ---
save('fields_timeseries.mat', ...
     'V_t','I_t','Cr_t','Fe_t','Ni_t','Si_t', ...
     'O_t','Cr2O3_t','Fe3O4_t','NiO_t','SiO2_t', 'p',...
     '-v7.3');

% --- 落盘：最终时刻快照 ---
writematrix(V_t  (:,:,end),  'V_final.csv');
writematrix(I_t  (:,:,end),  'I_final.csv');
writematrix(Cr_t (:,:,end),  'Cr_final.csv');
writematrix(Fe_t (:,:,end),  'Fe_final.csv');
writematrix(Ni_t (:,:,end),  'Ni_final.csv');
writematrix(Si_t (:,:,end),  'Si_final.csv');
writematrix(O_t    (:, end), 'O_final.csv');
writematrix(Cr2O3_t(:, end), 'Cr2O3_final.csv');
writematrix(Fe3O4_t  (:, end), 'Fe3O4_final.csv');
writematrix(NiO_t  (:, end), 'NiO_final.csv');
writematrix(SiO2_t (:, end), 'SiO2_final.csv');

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
CNiO   = NiO_t   (:, end);
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

% --- 氧化物厚度：Cr2O3 / Fe3O4 / NiO / SiO2 ---
oxides_1D = {Cr2O3_t, Fe3O4_t, NiO_t, SiO2_t};
oxide_lbl = {'Cr_2O_3', 'Fe_3O_4', 'NiO', 'SiO_2'};
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
end

%% --- 图 17：所有氧化物在最终时刻叠加（直接看占比）---
figure(19); clf; hold on; box on;
plot(y, Cr2O3_t(:, end), 'LineWidth', 3, 'DisplayName', 'Cr_2O_3');
plot(y, Fe3O4_t(:, end),   'LineWidth', 3, 'DisplayName', 'Fe3O4');
plot(y, NiO_t(:, end),   'LineWidth', 3, 'DisplayName', 'NiO');
plot(y, SiO2_t(:, end),  'LineWidth', 3, 'DisplayName', 'SiO_2');
plot(y, Cr2O3_t(:,end) + Fe3O4_t(:,end) + NiO_t(:,end) + SiO2_t(:,end), ...
     'LineWidth', 3, 'LineStyle', '--', 'DisplayName', 'Total oxide');
xlabel('y (nm) — along GB', 'FontSize', 24)
ylabel(sprintf('Oxide Concentration at t = %.2e s', t_out(end)), 'FontSize', 24)
title(sprintf('Oxide composition at end, dose rate = %.2g dpa/s', p.dose_rate), 'FontSize', 18)
set(gca, 'FontSize', 20)
legend('show', 'Location', 'best', 'FontSize', 14);

%% --- 图 18：氧化前沿可视化（O 浓度的 log 热图，时间 vs y）---
figure(20); clf;
imagesc(t_out, y, log10(max(O_t, 1e-20)));    % log scale，钳零防 -Inf
set(gca, 'YDir', 'normal');
colorbar;
xlabel('t (s)',              'FontSize', 20)
ylabel('y (nm) — along GB',  'FontSize', 20)
title(sprintf('log_{10}(C_O) over time, dose rate = %.2g dpa/s', p.dose_rate), 'FontSize', 18)
set(gca, 'FontSize', 16)

%% --- 图 19：Cr_2O_3 累积的时间-空间图（看前沿推进）---
figure(21); clf;
imagesc(t_out, y, Cr2O3_t);
set(gca, 'YDir', 'normal');
colorbar;
xlabel('t (s)',              'FontSize', 20)
ylabel('y (nm) — along GB',  'FontSize', 20)
title(sprintf('C_{Cr_2O_3} over time, dose rate = %.2g dpa/s', p.dose_rate), 'FontSize', 18)
set(gca, 'FontSize', 16)