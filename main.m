%% 参数（全部挂在 p 下）
p.dim   = 1;
p.nx    = 100;
p.ny    = 1;
p.dt    = 1e-5;
p.GBrecovert  = 0.8 * p.dt;       % 显式 Euler 用；ode15s 也会用这个值
p.dx    = 0.1;
p.t_end = 100000000.0;

p.V_init = 1e-10;
p.V_DBC  = 1e-10;

DCrV = 5e4;
DFeV = 1e4;
DNiV = 2e3;
p.DV = [DCrV, DFeV, DNiV];

p.dose_rate   = 1e-8;
p.recomb_rate = 1e4;

p.Cr_init = 0.18;   p.Cr_DCB = 0.18;
p.Fe_init = 0.72;   p.Fe_DCB = 0.72;
p.Ni_init = 0.10;   p.Ni_DCB = 0.10;

p.solver = 1;          % 0 = 显式 Euler；1 = ode15s

%% 初值（行向量，把 BC 值塞到端点）
V    = ones(1, p.nx) * p.V_init;    V(1)      = p.V_DBC;
CCr  = ones(1, p.nx) * p.Cr_init;   CCr(p.nx) = p.Cr_DCB;
CFe  = ones(1, p.nx) * p.Fe_init;   CFe(p.nx) = p.Fe_DCB;
CNi  = ones(1, p.nx) * p.Ni_init;   CNi(p.nx) = p.Ni_DCB;

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
if p.solver == 1
    % 用当前的 V/CCr/CFe/CNi 作初值，拼成 4nx 列向量
    y0 = [V(:); CCr(:); CFe(:); CNi(:)];

    % AbsTol 分场设置
    absTol = zeros(4*p.nx, 1);
    absTol(         1 :   p.nx) = 1e-16;     % V
    absTol(p.nx + 1 : 4*p.nx)   = 1e-8;      % CCr/CFe/CNi

    opts = odeset( ...
        'RelTol',      1e-6, ...
        'AbsTol',      absTol, ...
        'NonNegative', 1:4*p.nx, ...
        'JPattern',    jpattern_aks(p.nx), ...
        'Stats',       'on');

    fprintf('Starting ode15s...\n');
    tic;
    sol = ode15s(@(t,y) rhs_aks(t,y,p), [0 p.t_end], y0, opts);
    toc;

    % 在均匀时间点上取解
    t_out = linspace(0, p.t_end, 101);
    Y     = deval(sol, t_out);

    V_t  = Y(           1 :   p.nx, :);
    Cr_t = Y(  p.nx + 1 : 2*p.nx, :);
    Fe_t = Y(2*p.nx + 1 : 3*p.nx, :);
    Ni_t = Y(3*p.nx + 1 : 4*p.nx, :);

    writematrix(V_t,  'V_history.csv');
    writematrix(Cr_t, 'Cr_history.csv');
    writematrix(Fe_t, 'Fe_history.csv');
    writematrix(Ni_t, 'Ni_history.csv');

    % 把"最终时刻"的解回填到 V / CCr / CFe / CNi 给后面绘图用
    V   = V_t (:, end).';
    CCr = Cr_t(:, end).';
    CFe = Fe_t(:, end).';
    CNi = Ni_t(:, end).';
end

%% ===== 绘图 =====
x = (0:p.nx-1) * p.dx;        % 0, 0.1, ..., 9.9 (nm)

figure(1); clf; hold on; box on;
idx = 1:10:101;
colors = parula(numel(idx));
for k = 1:numel(idx)
    i = idx(k);
    plot(x, V_t(:, i), 'LineWidth', 2.5, ...
         'Color', colors(k, :), ...
         'DisplayName', sprintf('dose = %.2g', (i-1)/100));    % ← 关键
end
xlabel('x (nm)', 'FontSize', 24)
ylabel('Vacancy Concentration (%)', 'FontSize', 24)
set(gca, 'FontSize', 20)
legend('show', 'Location', 'northwest', 'FontSize', 14);       % ← 直接 show



figure(2); clf; hold on; box on;
idx = 1:10:101;
colors = parula(numel(idx));
for k = 1:numel(idx)
    i = idx(k);
    plot(x, Cr_t(:, i), 'LineWidth', 2.5, ...
         'Color', colors(k, :), ...
         'DisplayName', sprintf('dose = %.2g', (i-1)/100));    % ← 关键
end
xlabel('x (nm)', 'FontSize', 24)
ylabel('Cr Concentration (%)', 'FontSize', 24)
set(gca, 'FontSize', 20)
legend('show', 'Location', 'northwest', 'FontSize', 14);       % ← 直接 show

figure(3); clf; hold on; box on;
idx = 1:10:101;
colors = parula(numel(idx));
for k = 1:numel(idx)
    i = idx(k);
    plot(x, Fe_t(:, i), 'LineWidth', 2.5, ...
         'Color', colors(k, :), ...
         'DisplayName', sprintf('dose = %.2g', (i-1)/100));    % ← 关键
end
xlabel('x (nm)', 'FontSize', 24)
ylabel('Fe Concentration (%)', 'FontSize', 24)
set(gca, 'FontSize', 20)
legend('show', 'Location', 'northwest', 'FontSize', 14);       % ← 直接 show

figure(4); clf; hold on; box on;
idx = 1:10:101;
colors = parula(numel(idx));
for k = 1:numel(idx)
    i = idx(k);
    plot(x, Ni_t(:, i), 'LineWidth', 2.5, ...
         'Color', colors(k, :), ...
         'DisplayName', sprintf('dose = %.2g', (i-1)/100));    % ← 关键
end
xlabel('x (nm)', 'FontSize', 24)
ylabel('Ni Concentration (%)', 'FontSize', 24)
set(gca, 'FontSize', 20)
legend('show', 'Location', 'northwest', 'FontSize', 14);       % ← 直接 show