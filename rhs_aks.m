function dydt = rhs_aks(t, y, p)
nx = p.nx;
ny = p.ny;
N  = nx * ny;          % 单场长度

% 拆包：列向量 -> ny×nx 矩阵
V   = reshape(y(      1 :   N), ny, nx);
I   = reshape(y(  N + 1 : 2*N), ny, nx);
CCr = reshape(y(2*N + 1 : 3*N), ny, nx);
CFe = reshape(y(3*N + 1 : 4*N), ny, nx);
CNi = reshape(y(4*N + 1 : 5*N), ny, nx);
CSi = reshape(y(5*N + 1 : 6*N), ny, nx);

base     = 6 * N;
CO       = y(base +        1 : base +   ny);
CCr2O3   = y(base +   ny + 1 : base + 2*ny);
CFe3O4   = y(base + 2*ny + 1 : base + 3*ny);
CFeCr2O4 = y(base + 3*ny + 1 : base + 4*ny);
CSiO2    = y(base + 4*ny + 1 : base + 5*ny);

% 强制 Dirichlet（按整条边）
% GB 缺陷汇 (i=1): p.gb_defect_bc = 'robin'  ->  J·n = k_gb*(C - C_eq), 见下面 J_gbV/J_gbI
%                                  'dirichlet' (缺省, 旧行为) -> V(:,1)=V_DBC, I(:,1)=I_DBC
if isfield(p,'gb_defect_bc') && ~isempty(p.gb_defect_bc), gb_bc = p.gb_defect_bc; else, gb_bc = 'dirichlet'; end
robin_def = strcmp(gb_bc, 'robin');
if ~robin_def
    V(:, 1)    = p.V_DBC;
    I(:, 1)    = p.I_DBC;
end
CCr(:, nx) = p.Cr_DCB;
CFe(:, nx) = p.Fe_DCB;
CNi(:, nx) = p.Ni_DCB;
CSi(:, nx) = p.Si_DCB;
% CO(1) 不强制 Dirichlet: 口部 Robin BC, 见 J_surf 与 dOdt

% ---------------- 缺陷介导通量 ----------------
% 金属浓度的 log 地板 (只防 log(0); 介质 V/I 不再进 log, 见 J_all_via_medium)
if isfield(p,'logfloor_C'), cFl = p.logfloor_C; else, cFl = 1e-12; end

[J_Cr_V_x,J_Fe_V_x,J_Ni_V_x,J_Si_V_x, ...
 J_Cr_V_y,J_Fe_V_y,J_Ni_V_y,J_Si_V_y] = ...
    J_all_via_medium(CCr,CFe,CNi,CSi,V,p.DV,p.f0V,p.dx,p.dy,-1,cFl);
[J_V_diff_x,J_V_diff_y] = JV(J_Cr_V_x,J_Cr_V_y, J_Fe_V_x, J_Fe_V_y, ...
                             J_Ni_V_x, J_Ni_V_y, J_Si_V_x, J_Si_V_y);

[J_Cr_I_x,J_Fe_I_x,J_Ni_I_x,J_Si_I_x, ...
 J_Cr_I_y,J_Fe_I_y,J_Ni_I_y,J_Si_I_y] = ...
    J_all_via_medium(CCr,CFe,CNi,CSi,I,p.DI,p.f0I,p.dx,p.dy,1,cFl);
[J_I_diff_x,J_I_diff_y] = JI(J_Cr_I_x,J_Cr_I_y, J_Fe_I_x, J_Fe_I_y, ...
                             J_Ni_I_x, J_Ni_I_y, J_Si_I_x, J_Si_I_y);

% ---------------- 界面代数 ----------------
% p.closure = 'laplace': 整个氧化物截面为 O 通道, 半宽 L = chan_width(ΣL_k, slab),
%                        侧向闭合为 Laplace 基模 (solve_mu, 未知量 mu)。
%             'node'   : 旧模型, 固定 slab 通道 + 膜电导闭合 (solve_node, 未知量 u)。
% 缺省 'node', 使旧 checkpoint 里的 p 行为不变。
if isfield(p,'closure') && ~isempty(p.closure), closure = p.closure; else, closure = 'node'; end
use_mu = strcmp(closure, 'laplace');
q_all = zeros(ny, 4);   u2_all = zeros(ny,1);   nbad = 0;
for j = 1:ny
    if use_mu
        [qj, uuj, okj] = solve_mu(CO(j), CCr(j,1), CFe(j,1), CNi(j,1), CSi(j,1), ...
                                  CCr2O3(j), CSiO2(j), CFe3O4(j), CFeCr2O4(j), p, []);
    else
        % okj 只用于计数, solve_node 的行为完全没动 (E 未修)
        [qj, uuj, okj] = solve_node(CO(j), CCr(j,1), CFe(j,1), CNi(j,1), CSi(j,1), ...
                                    CCr2O3(j), CSiO2(j), CFe3O4(j), CFeCr2O4(j), p, []);
    end
    q_all(j,:) = qj';   u2_all(j) = uuj(2);
    if ~okj, nbad = nbad + 1; end
end
qCr = q_all(:,1); qSi = q_all(:,2); qMag = q_all(:,3); qSpin = q_all(:,4);

% 溶质 sink（q 的货币 = O 场(水归一)单位; 金属侧 site fraction, 乘 p.rOM 换算）
v_ox   = p.rOM * ((2/3)*qCr + 0.5*qSi + 0.75*qMag + 0.75*qSpin);
J_r_Cr = -p.rOM * ((2/3)*qCr + (1/2)*qSpin);
J_r_Si = -p.rOM * (1/2)*qSi;
J_r_Fe = -p.rOM * (0.75*qMag + 0.25*qSpin);
J_r_Ni = zeros(ny, 1);

% ---------------- 界面扫掠与俘获 (rearrange 旋钮) ----------------
% 第一步 氧化速率照旧: solve_mu / q_k 不动, R_i = -J_r_i >= 0 是各元素的氧化消耗
%        (site fraction × nm/s)。
% 第二步 扫掠速率由氧化需求反推:  s = max_i R_i / c_i  (nm/s), c_i = 界面处金属浓度 (j,1)。
%        界面必须扫过这么厚的金属才能供上氧化最快的元素 (实际是 Cr: s = R_Cr/c_Cr)。
%        扫进来的金属 s*c_i 中未被氧化的部分 s*c_i - R_i >= 0 (Fe/Ni 为主) 是"游离物"。
% 第三步 rearrange 旋钮:  λ = s/(s + v_r),  v_r = p.v_rearr (nm/s)。
%        游离物的 λ 份被俘获 (一并从金属场消耗), (1-λ) 份被界面 rearrange 推回金属。
%        v_r >> s: λ→0 不俘获 (= 旧行为, p.v_rearr = Inf 完全还原);  v_r << s: λ→1 全俘获。
% 俘获量与 J_r 同货币加进各元素的汇, 于是 dsolutedt 与 lattice_velocity_x 自动带上,
% 质量守恒机制与氧化消耗相同。俘获的金属只从金属场移除, 不进入氧化物厚度 (未追踪)。
if isfield(p,'v_rearr') && ~isempty(p.v_rearr), v_r = p.v_rearr; else, v_r = Inf; end
if isfinite(v_r)
    c_int = [CCr(:,1), CFe(:,1), CNi(:,1), CSi(:,1)];           % ny×4
    R_ox  = max(-[J_r_Cr, J_r_Fe, J_r_Ni, J_r_Si], 0);          % ny×4, 氧化消耗
    s_sw  = max(R_ox ./ max(c_int, p.epsC), [], 2);             % ny×1, 扫掠速率
    lam   = s_sw ./ max(s_sw + v_r, realmin);                   % ny×1, s=0 时 λ=0
    capt  = lam .* max(s_sw .* c_int - R_ox, 0);                % ny×4, 被俘获的游离物
    J_r_Cr = J_r_Cr - capt(:,1);
    J_r_Fe = J_r_Fe - capt(:,2);
    J_r_Ni = J_r_Ni - capt(:,3);
    J_r_Si = J_r_Si - capt(:,4);
end

% 氧化物体积换算 (下面 dCr2O3 等要用)
convCr2O3   = p.Nden*p.Cr2O3mass   /(p.NA*p.Cr2O3den);
convSiO2    = p.Nden*p.SiO2mass    /(p.NA*p.SiO2den);
convFe3O4   = p.Nden*p.Fe3O4mass   /(p.NA*p.Fe3O4den);
convFeCr2O4 = p.Nden*p.FeCr2O4mass /(p.NA*p.FeCr2O4den);

% ---------------- 晶格速度 ----------------
lattice_velocity_x = J_V_diff_x - J_I_diff_x;
lattice_velocity_x = lattice_velocity_x + (J_r_Cr + J_r_Fe + J_r_Ni + J_r_Si);
lattice_velocity_y = J_V_diff_y - J_I_diff_y;

[J_Cr_drift_x,J_Cr_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CCr);
[J_Fe_drift_x,J_Fe_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CFe);
[J_Ni_drift_x,J_Ni_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CNi);
[J_Si_drift_x,J_Si_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CSi);
[J_V_drift_x, J_V_drift_y]  = Jdrift(lattice_velocity_x,lattice_velocity_y,V);
[J_I_drift_x, J_I_drift_y]  = Jdrift(lattice_velocity_x,lattice_velocity_y,I);

J_Cr_x = J_Cr_V_x + J_Cr_I_x + J_Cr_drift_x;
J_Ni_x = J_Ni_V_x + J_Ni_I_x + J_Ni_drift_x;
J_Fe_x = J_Fe_V_x + J_Fe_I_x + J_Fe_drift_x;
J_Si_x = J_Si_V_x + J_Si_I_x + J_Si_drift_x;
J_V_x  = J_V_diff_x + J_V_drift_x;
J_I_x  = J_I_diff_x + J_I_drift_x;

J_Cr_y = J_Cr_V_y + J_Cr_I_y + J_Cr_drift_y;
J_Ni_y = J_Ni_V_y + J_Ni_I_y + J_Ni_drift_y;
J_Fe_y = J_Fe_V_y + J_Fe_I_y + J_Fe_drift_y;
J_Si_y = J_Si_V_y + J_Si_I_y + J_Si_drift_y;
J_V_y  = J_V_diff_y + J_V_drift_y;
J_I_y  = J_I_diff_y + J_I_drift_y;

% ---------------- 沿 GB 的 O 输运 (式 (13)) ----------------
% 通道半宽 L 与有效扩散系数 D_eff 用同一个宽度 chan_width(S, slab) (见 calc_DO)。
S_ox = CCr2O3 + CFe3O4 + CFeCr2O4 + CSiO2;
if use_mu
    [L_n, dLdS] = chan_width(S_ox, p.slab);
else
    L_n = p.slab * ones(ny,1);   dLdS = zeros(ny,1);   % 旧模型: 通道宽度固定, 无稀释
end
D_n = calc_DO(CCr2O3, CFe3O4, CFeCr2O4, CSiO2, ...
              p.DO0, p.slab, p.DCr2O3, p.DFe3O4, p.DFeCr2O4, p.DSiO2);
J_O = JO(CO, D_n, L_n, p.dy);

% ---------------- 时间导数 ----------------
dCr = dsolutedt(J_Cr_x, J_Cr_y, p.dx, p.dy, J_r_Cr);
dFe = dsolutedt(J_Fe_x, J_Fe_y, p.dx, p.dy, J_r_Fe);
dNi = dsolutedt(J_Ni_x, J_Ni_y, p.dx, p.dy, J_r_Ni);
dSi = dsolutedt(J_Si_x, J_Si_y, p.dx, p.dy, J_r_Si);

% GB 缺陷汇 Robin BC:  J_V·n = kgbV*(C_V - C_V^eq),  J_I·n = kgbI*(C_I - C_I^eq),
% n = 外法向 (指向 GB, 即 -x), 所以 GB 面上 +x 方向的通量是 J_gb = -k_gb*(C - C_eq)。
% C_eq 沿用 V_DBC / I_DBC 字段 (= 热平衡值)。Dirichlet 模式传空, dVdt/dIdt 走旧路径。
if robin_def
    J_gbV = -p.kgbV * (V(:,1) - p.V_DBC);
    J_gbI = -p.kgbI * (I(:,1) - p.I_DBC);
else
    J_gbV = [];  J_gbI = [];
end
dV = dVdt(J_V_x,J_V_y,p.dx,p.dy,I,V, p.eff*p.dose_rate, p.recomb_rate, ...
          p.V_init,p.I_init,p.Ks,lattice_velocity_x, J_gbV);
dI = dIdt(J_I_x,J_I_y,p.dx,p.dy,I,V, p.eff*p.dose_rate, p.recomb_rate, ...
          p.I_init,p.V_init,p.Ks,lattice_velocity_x, J_gbI);

% 氧化物厚度 (先算, dO 的稀释项要用 dL/dt)
dCr2O3   = p.rOM*(1/3)*qCr  .* convCr2O3;
dSiO2    = p.rOM*(1/2)*qSi  .* convSiO2;
dFe3O4   = p.rOM*(1/4)*qMag .* convFe3O4;
dFeCr2O4 = p.rOM*(1/4)*qSpin.* convFeCr2O4;
dLdt = dLdS .* (dCr2O3 + dSiO2 + dFe3O4 + dFeCr2O4);   % 通道变宽速率 (链式法则)

Q_O = sum(q_all, 2);                                   % 界面总消耗 Jr = Σ_k q_k
% Robin BC: J·n = kRobin/(sqrt(t)+10)*(O_DCB - CO(1)), +y(入通道)为正, 单位截面积
J_surf = p.kRobin/(sqrt(t) + 10) * (p.O_DCB - CO(1));
% L dC̄/dt = -div(D L dC̄/dy) - Jr - C̄ dL/dt   (旧闭合: L=slab, dLdt=0, 与原式相同)
dO = dOdt(CO, J_O, Q_O, L_n, dLdt, p.dy, J_surf);

% Dirichlet 导数置零 (Robin 模式下 i=1 的 V/I 是活的)
if ~robin_def
    dV(:,1)   = 0;
    dI(:,1)   = 0;
end
dCr(:,nx) = 0;
dFe(:,nx) = 0;
dNi(:,nx) = 0;
dSi(:,nx) = 0;

% 打包
dydt = [dV(:); dI(:); dCr(:); dFe(:); dNi(:); dSi(:); dO(:); ...
        dCr2O3(:); dFe3O4(:); dFeCr2O4(:); dSiO2(:)];

if any(~isfinite(dydt))
    % 原来这里只 fprintf 然后把 NaN 原样返回给 ode15s。那是最坏的处理:
    % ode15s 的失败判据是 `if err > rtol` (ode15s.m:688), 而 NaN > rtol 求值为
    % false —— 坏步会被【静默接受】, NaN 直接污染状态; 同时每次 RHS 求值刷 4 行,
    % numjac 每算一次 Jacobian 要调几百次 RHS, 刷屏本身也在吃时间和内存。
    % 现在直接报错: 求解中止, checkpoint 保持在上一个完成窗, 且信息可定位。
    bad = find(~isfinite(dydt));
    error('rhs_aks:nonfinite', ...
        ['t=%.6e: dydt 出现 %d 个 NaN/Inf, 首个索引 %d\n' ...
         '  min  Cr=%g Fe=%g Ni=%g Si=%g O=%g\n' ...
         '  min  V=%g  I=%g\n' ...
         '  若 V/I/金属 的 min 为 0 或负: 检查 AbsTol 与地板值是否自洽\n' ...
         '  (AbsTol/RelTol = ode15s 的 threshold, 必须 <= 该场的地板值)'], ...
        t, numel(bad), bad(1), ...
        min(CCr(:)), min(CFe(:)), min(CNi(:)), min(CSi(:)), min(CO(:)), ...
        min(V(:)), min(I(:)));
end
end