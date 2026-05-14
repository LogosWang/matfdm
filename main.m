%% 参数（全部挂在 p 下）
p.dim   = 2;
p.nx    = 500;
p.ny    = 10;

p.dt    = 1e-5;
p.GBrecovert  = 0.8 * p.dt;       % 显式 Euler 用；ode15s 也会用这个值
p.dx    = 0.1;
p.dy = 1;
p.t_end = 100000000.0;

p.V_init = 1e-13;
p.V_DBC  = 1e-13;
p.I_init = 1e-13;
p.I_DBC  = 1e-13;

DCrV = 5e8;
DFeV = 1e8;
DNiV = 5e7;
DSiV = 5e8;
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
N = p.nx * p.ny;     % 单场长度
%% ===== ode15s 分支 =====
y0 = [V(:); I(:); CCr(:); CFe(:); CNi(:); CSi(:)];     % ← 加这一行

absTol = zeros(6*N, 1);
absTol(      1 : 2*N) = 1e-16;     % V/I
absTol(2*N + 1 : 6*N) = 1e-8;      % CCr/CFe/CNi/CSi

%% 求解器选项
opts = odeset( ...
    'RelTol',      1e-6, ...
    'AbsTol',      absTol, ...
    'NonNegative', 1:6*N, ...
    'JPattern',    jpattern_aks(p.nx, p.ny), ...   % ← 2D 版本
    'Stats',       'on');

    fprintf('Starting ode15s...\n');
    tic;
    sol = ode15s(@(t,y) rhs_aks(t,y,p), [0 p.t_end], y0, opts);
    toc;

    % 在均匀时间点上取解
    t_out = linspace(0, p.t_end, 101);
    Y     = deval(sol, t_out);

% 在均匀时间点上取解
t_out = linspace(0, p.t_end, 101);
Y     = deval(sol, t_out);
N     = p.nx * p.ny;
nt    = numel(t_out);

% 每个场切出来再 reshape 成 ny × nx × nt
V_t  = reshape(Y(        1 :   N, :), p.ny, p.nx, nt);
I_t  = reshape(Y(    N + 1 : 2*N, :), p.ny, p.nx, nt);
Cr_t = reshape(Y(  2*N + 1 : 3*N, :), p.ny, p.nx, nt);
Fe_t = reshape(Y(  3*N + 1 : 4*N, :), p.ny, p.nx, nt);
Ni_t = reshape(Y(  4*N + 1 : 5*N, :), p.ny, p.nx, nt);
Si_t = reshape(Y(  5*N + 1 : 6*N, :), p.ny, p.nx, nt);

% 落盘：写 t_end 时刻的 2D 快照（ny × nx）
writematrix(V_t (:,:,end), 'V_final.csv');
writematrix(I_t (:,:,end), 'I_final.csv');
writematrix(Cr_t(:,:,end), 'Cr_final.csv');
writematrix(Fe_t(:,:,end), 'Fe_final.csv');
writematrix(Ni_t(:,:,end), 'Ni_final.csv');
writematrix(Si_t(:,:,end), 'Si_final.csv');

% 最终时刻 2D 回填（供后续操作）
V   = V_t (:, :, end);
I   = I_t (:, :, end);
CCr = Cr_t(:, :, end);
CFe = Fe_t(:, :, end);
CNi = Ni_t(:, :, end);
CSi = Si_t(:, :, end);


%% ===== 绘图 =====
x = (0:p.nx-1) * p.dx;
y = (0:p.ny-1) * p.dy;
j_mid = round(p.ny/2);     % 取中间 y 切片画 1D-like profile

idx    = 1:10:nt;
colors = parula(numel(idx));

%% --- 图 1-6：沿 x 方向 profile（y=中线），不同 dose ---
fields = {V_t,  I_t,  Cr_t, Fe_t, Ni_t, Si_t};
labels = {'Vacancy','Interstitial','Cr','Fe','Ni','Si'};

for f = 1:6
    figure(f); clf; hold on; box on;
    for k = 1:numel(idx)
        i = idx(k);
        profile = squeeze(fields{f}(j_mid, :, i));    % 1 × nx
        plot(x, profile, 'LineWidth', 2.5, ...
             'Color', colors(k, :), ...
             'DisplayName', sprintf('dose = %.2g', (i-1)/100));
    end
    xlabel('x (nm)',  'FontSize', 24)
    ylabel([labels{f} ' Concentration'], 'FontSize', 24)
    set(gca, 'FontSize', 20)
    legend('show', 'Location', 'northwest', 'FontSize', 14);
end

%% --- 图 7-12：最终时刻的 2D 浓度场（imagesc 热图）---
for f = 1:6
    figure(6+f); clf;
    imagesc(x, y, fields{f}(:,:,end));
    set(gca, 'YDir', 'normal');           % y 轴正方向朝上
    axis equal tight; colorbar;
    xlabel('x (nm)', 'FontSize', 20)
    ylabel('y (nm)', 'FontSize', 20)
    title([labels{f} ' at dose = 1'], 'FontSize', 20)
    set(gca, 'FontSize', 16)
end