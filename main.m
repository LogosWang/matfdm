%% 参数（全部挂在 p 下）
p.dim   = 2;
p.nx    = 50;
p.ny    = 50;

p.dt    = 1e-5;
p.GBrecovert  = 0.8 * p.dt;       % 显式 Euler 用；ode15s 也会用这个值
p.dx    = 0.5;
p.dy = 1;
p.t_end = 100000000.0;

p.V_init = 1e-13;
p.V_DBC  = 1e-13;
p.I_init = 1e-13;
p.I_DBC  = 1e-13;

DCrV = 5e8;
DFeV = 1e8;
DNiV = 5e7;
DSiV = 1e8;
p.DV = [DCrV, DFeV, DNiV,DSiV];
DCrI = 2e7;
DFeI = 2e7;
DNiI = 2e7;
DSiI = 5e8;
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
p.NiO_init = 0.0;
p.SiO2_init = 0.0;
p.kCr = 1e-7;
p.kSi = 1e-7;
p.kNi = 1e-7;
p.DO0 = 1e-8;
p.DOmax = 10;
p.alpha = 2.0;
p.oxide_character = 0.1;
p.solver = 1;          % 0 = 显式 Euler；1 = ode15s

%% 初值（行向量，把 BC 值塞到端点）
if p.dim == 1
V    = ones(1, p.nx) * p.V_init;    V(1)      = p.V_DBC;
I     = ones(1, p.nx) * p.I_init;    I(1)      = p.I_DBC;
CCr  = ones(1, p.nx) * p.Cr_init;   CCr(p.nx) = p.Cr_DCB;
CFe  = ones(1, p.nx) * p.Fe_init;   CFe(p.nx) = p.Fe_DCB;
CNi  = ones(1, p.nx) * p.Ni_init;   CNi(p.nx) = p.Ni_DCB;
CSi  = ones(1, p.nx) * p.Si_init;   CSi(p.nx) = p.Si_DCB;
end
if p.dim ==2
    V    = ones(p.ny, p.nx) * p.V_init;    V(:,1)      = p.V_DBC;
    I     = ones(p.ny,p.nx) * p.I_init;    I(:,1)      = p.I_DBC;
    CCr  = ones(p.ny, p.nx) * p.Cr_init;   CCr(:,p.nx) = p.Cr_DCB;
    CFe  = ones(p.ny, p.nx) * p.Fe_init;   CFe(:,p.nx) = p.Fe_DCB;
    CNi  = ones(p.ny, p.nx) * p.Ni_init;   CNi(:,p.nx) = p.Ni_DCB;
    CSi  = ones(p.ny, p.nx) * p.Si_init;   CSi(:,p.nx) = p.Si_DCB;
    CO  = ones(p.ny, 1) * p.O_init;    CO(1,1) = p.O_DCB;
    CCr2O3  = ones(p.ny, 1) * p.Cr2O3_init;
    CNiO  = ones(p.ny, 1) * p.NiO_init;
    CSiO2  = ones(p.ny, 1) * p.SiO2_init;
end
%% ===== 显式 Euler 分支 =====
if p.solver == 0
    current_t     = 0.0;
    current_tstep = 0;
    while current_t < p.t_end
        % 强制 BC（保险）
        V(1)      = p.V_DBC;
        CCr(p.nx) = p.Cr_DCB;
        CFe(p.nx) = p.Fe_DCB;
        CNi(p.nx) = p.Ni_DCB;

        % 通量
        J_CrCr_V = JCrCrV(CCr, V, p.DV, p.dx);
        J_FeFe_V = JFeFeV(CFe, V, p.DV, p.dx);
        J_NiNi_V = JNiNiV(CNi, V, p.DV, p.dx);
        J_V      = JV(J_CrCr_V, J_FeFe_V, J_NiNi_V);

        % 时间导数
        dCr_dt = dCrdt(J_CrCr_V, p.dx, CCr, CFe, CNi, p.GBrecovert);
        dFe_dt = dFedt(J_FeFe_V, p.dx, CCr, CFe, CNi, p.GBrecovert);
        dNi_dt = dNidt(J_NiNi_V, p.dx, CCr, CFe, CNi, p.GBrecovert);
        dV_dt  = dVdt (J_V,      p.dx, V,   p.dose_rate, p.recomb_rate);

        % 步进
        V   = V   + dV_dt  * p.dt;
        CCr = CCr + dCr_dt * p.dt;
        CFe = CFe + dFe_dt * p.dt;
        CNi = CNi + dNi_dt * p.dt;

        current_t     = current_t + p.dt;
        current_tstep = current_tstep + 1;

        if mod(current_tstep, 10000) == 0
            writematrix(V,   ['V',  num2str(current_tstep), '.csv']);
            writematrix(CCr, ['Cr', num2str(current_tstep), '.csv']);
            writematrix(CFe, ['Fe', num2str(current_tstep), '.csv']);
            writematrix(CNi, ['Ni', num2str(current_tstep), '.csv']);
        end
    end
end

%% ===== ode15s 分支 =====
%% ===== ode15s 分支 =====
N   = p.nx * p.ny;                                  % 2D 单场长度
M   = 6*N + 4*p.ny;                                 % y0 总长度

y0  = [V(:); I(:); CCr(:); CFe(:); CNi(:); CSi(:); ...
       CO(:); CCr2O3(:); CNiO(:); CSiO2(:)];

assert(length(y0) == M, '初值向量长度不匹配');

% AbsTol 分场
absTol = zeros(M, 1);
absTol(      1 :  2*N)              = 1e-16;       % V / I
absTol(2*N + 1 :  6*N)              = 1e-8;        % CCr / CFe / CNi / CSi
absTol(6*N + 1 :  6*N + p.ny)       = 1e-12;       % CO
absTol(6*N + p.ny + 1 : M)          = 1e-12;       % 三个氧化物

opts = odeset( ...
    'RelTol',      1e-6, ...
    'AbsTol',      absTol, ...
    'NonNegative', 1:M, ...
    'JPattern',    jpattern_aks(p.nx, p.ny), ...
    'Stats',       'on');

fprintf('Starting ode15s...\n');
tic;
sol = ode15s(@(t,y) rhs_aks(t,y,p), [0 p.t_end], y0, opts);
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
NiO_t      = Y(base +  2*ny + 1 : base +  3*ny, :);
SiO2_t     = Y(base +  3*ny + 1 : base +  4*ny, :);

% --- 落盘：最终时刻快照 ---
writematrix(V_t  (:,:,end),  'V_final.csv');
writematrix(I_t  (:,:,end),  'I_final.csv');
writematrix(Cr_t (:,:,end),  'Cr_final.csv');
writematrix(Fe_t (:,:,end),  'Fe_final.csv');
writematrix(Ni_t (:,:,end),  'Ni_final.csv');
writematrix(Si_t (:,:,end),  'Si_final.csv');
writematrix(O_t    (:, end), 'O_final.csv');
writematrix(Cr2O3_t(:, end), 'Cr2O3_final.csv');
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
CNiO   = NiO_t   (:, end);
CSiO2  = SiO2_t  (:, end);

%% ===== 绘图 =====
x = (0:nx-1) * p.dx;
y = (0:ny-1) * p.dy;
j_mid  = round(ny/2);
idx    = 1:10:nt;
colors = parula(numel(idx));

%% --- 图 1-6：2D 场沿 x 的 profile（y=中线），不同 dose ---
fields_2D = {V_t,  I_t,  Cr_t, Fe_t, Ni_t, Si_t};
labels_2D = {'Vacancy','Interstitial','Cr','Fe','Ni','Si'};

for f = 1:6
    figure(f); clf; hold on; box on;
    for k = 1:numel(idx)
        i = idx(k);
        profile = squeeze(fields_2D{f}(j_mid, :, i));
        plot(x, profile, 'LineWidth', 2.5, ...
             'Color', colors(k, :), ...
             'DisplayName', sprintf('dose = %.2g', (i-1)/100));
    end
    xlabel('x (nm)',  'FontSize', 24)
    ylabel([labels_2D{f} ' Concentration'], 'FontSize', 24)
    set(gca, 'FontSize', 20)
    legend('show', 'Location', 'best', 'FontSize', 14);
end

%% --- 图 7-12：最终时刻 2D 热图 ---
for f = 1:6
    figure(6+f); clf;
    imagesc(x, y, fields_2D{f}(:,:,end));
    set(gca, 'YDir', 'normal');
    axis equal tight; colorbar;
    xlabel('x (nm)', 'FontSize', 20)
    ylabel('y (nm)', 'FontSize', 20)
    title([labels_2D{f} ' at dose = 1'], 'FontSize', 20)
    set(gca, 'FontSize', 16)
end

%% --- 图 13-16：1D 场（O 和 3 个氧化物）沿 y 的 profile，不同 dose ---
fields_1D = {O_t,  Cr2O3_t, NiO_t, SiO2_t};
labels_1D = {'O', 'Cr_2O_3', 'NiO', 'SiO_2'};

for f = 1:4
    figure(12+f); clf; hold on; box on;
    for k = 1:numel(idx)
        i = idx(k);
        profile = fields_1D{f}(:, i);                  % ny × 1
        plot(y, profile, 'LineWidth', 2.5, ...
             'Color', colors(k, :), ...
             'DisplayName', sprintf('dose = %.2g', (i-1)/100));
    end
    xlabel('y (nm) — along GB', 'FontSize', 24)
    ylabel([labels_1D{f} ' Concentration'], 'FontSize', 24)
    set(gca, 'FontSize', 20)
    legend('show', 'Location', 'best', 'FontSize', 14);
end

%% --- 图 17：所有氧化物在最终时刻叠加（直接看占比）---
figure(17); clf; hold on; box on;
plot(y, Cr2O3_t(:, end), 'LineWidth', 3, 'DisplayName', 'Cr_2O_3');
plot(y, NiO_t(:, end),   'LineWidth', 3, 'DisplayName', 'NiO');
plot(y, SiO2_t(:, end),  'LineWidth', 3, 'DisplayName', 'SiO_2');
plot(y, Cr2O3_t(:,end) + NiO_t(:,end) + SiO2_t(:,end), ...
     'LineWidth', 3, 'LineStyle', '--', 'DisplayName', 'Total oxide');
xlabel('y (nm) — along GB', 'FontSize', 24)
ylabel('Oxide Concentration at t_{end}', 'FontSize', 24)
set(gca, 'FontSize', 20)
legend('show', 'Location', 'best', 'FontSize', 14);

%% --- 图 18：氧化前沿可视化（O 浓度的 log 热图，时间 vs y）---
figure(18); clf;
imagesc(t_out, y, log10(max(O_t, 1e-20)));    % log scale，钳零防 -Inf
set(gca, 'YDir', 'normal');
colorbar;
xlabel('t (time)',           'FontSize', 20)
ylabel('y (nm) — along GB',  'FontSize', 20)
title('log_{10}(C_O) over time', 'FontSize', 20)
set(gca, 'FontSize', 16)

%% --- 图 19：Cr_2O_3 累积的时间-空间图（看前沿推进）---
figure(19); clf;
imagesc(t_out, y, Cr2O3_t);
set(gca, 'YDir', 'normal');
colorbar;
xlabel('t (time)',           'FontSize', 20)
ylabel('y (nm) — along GB',  'FontSize', 20)
title('C_{Cr_2O_3} over time', 'FontSize', 20)
set(gca, 'FontSize', 16)