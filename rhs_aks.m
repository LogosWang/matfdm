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
base   = 6 * N;
CO     = y(base +        1 : base +   ny);
CCr2O3 = y(base +   ny + 1 : base + 2*ny);
CFe3O4   = y(base + 2*ny + 1 : base + 3*ny);
CNiFe2O4   = y(base + 3*ny + 1 : base + 4*ny);
CSiO2  = y(base + 4*ny + 1 : base + 5*ny);
% 强制 Dirichlet（按整条边，不再是单点）
V(:, 1)    = p.V_DBC;
I(:, 1)    = p.I_DBC;
CCr(:, nx) = p.Cr_DCB;
CFe(:, nx) = p.Fe_DCB;
CNi(:, nx) = p.Ni_DCB;
CSi(:, nx) = p.Si_DCB;
CO(1,1) = p.O_DCB;
% 通量
% [J_Cr_V_x,J_Cr_V_y] = J_via_medium(1,CCr,CFe,CNi,CSi,V,p.DV,p.f0V,p.dx,p.dy,-1);
% [J_Fe_V_x,J_Fe_V_y] =  J_via_medium(2,CCr,CFe,CNi,CSi,V,p.DV,p.f0V,p.dx,p.dy,-1);
% [J_Ni_V_x,J_Ni_V_y] =  J_via_medium(3,CCr,CFe,CNi,CSi,V,p.DV,p.f0V,p.dx,p.dy,-1);
% [J_Si_V_x,J_Si_V_y] =  J_via_medium(4,CCr,CFe,CNi,CSi,V,p.DV,p.f0V,p.dx,p.dy,-1);
% [J_V_diff_x,J_V_diff_y]  = JV(J_Cr_V_x,J_Cr_V_y, J_Fe_V_x, J_Fe_V_y, J_Ni_V_x, J_Ni_V_y, J_Si_V_x, J_Si_V_y);
% 
% [J_Cr_I_x,J_Cr_I_y] = J_via_medium(1,CCr,CFe,CNi,CSi,I,p.DI,p.f0I,p.dx,p.dy,1);
% [J_Fe_I_x,J_Fe_I_y] = J_via_medium(2,CCr,CFe,CNi,CSi,I,p.DI,p.f0I,p.dx,p.dy,1);
% [J_Ni_I_x,J_Ni_I_y] = J_via_medium(3,CCr,CFe,CNi,CSi,I,p.DI,p.f0I,p.dx,p.dy,1);
% [J_Si_I_x,J_Si_I_y] = J_via_medium(4,CCr,CFe,CNi,CSi,I,p.DI,p.f0I,p.dx,p.dy,1);


% V mediated
[J_Cr_V_x,J_Fe_V_x,J_Ni_V_x,J_Si_V_x, ...
 J_Cr_V_y,J_Fe_V_y,J_Ni_V_y,J_Si_V_y] = ...
    J_all_via_medium(CCr,CFe,CNi,CSi,V,p.DV,p.f0V,p.dx,p.dy,-1);
[J_V_diff_x,J_V_diff_y]  = JV(J_Cr_V_x,J_Cr_V_y, J_Fe_V_x, J_Fe_V_y, J_Ni_V_x, J_Ni_V_y, J_Si_V_x, J_Si_V_y);

% I mediated
[J_Cr_I_x,J_Fe_I_x,J_Ni_I_x,J_Si_I_x, ...
 J_Cr_I_y,J_Fe_I_y,J_Ni_I_y,J_Si_I_y] = ...
    J_all_via_medium(CCr,CFe,CNi,CSi,I,p.DI,p.f0I,p.dx,p.dy,1);
[J_I_diff_x,J_I_diff_y]  = JI(J_Cr_I_x,J_Cr_I_y, J_Fe_I_x, J_Fe_I_y, J_Ni_I_x, J_Ni_I_y, J_Si_I_x, J_Si_I_y);


% ===== 双前沿界面代数（替代 Jreaction/Jcoreaction/effectivek）=====
% persistent UU
% if isempty(UU) || size(UU,2) ~= ny, UU = nan(4, ny); end
% q_all = zeros(ny, 4);   u2_all = zeros(ny,1);
% for j = 1:ny
%     [qj, uuj, okj] = solve_node(CO(j), CCr(j,1), CFe(j,1), CNi(j,1), CSi(j,1), ...
%                                 CCr2O3(j), CFe3O4(j), CNiFe2O4(j), p, UU(:,j));
%     if ~okj
%         [qj, uuj] = solve_node(CO(j), CCr(j,1), CFe(j,1), CNi(j,1), CSi(j,1), ...
%                                CCr2O3(j), CFe3O4(j), CNiFe2O4(j), p, []);
%     end
%     q_all(j,:) = qj';  UU(:,j) = uuj;  u2_all(j) = uuj(2);
% end
% qCr = q_all(:,1); qSi = q_all(:,2); qMag = q_all(:,3); qTr = q_all(:,4);

% ===== 双前沿界面代数（冷启动: RHS 成为 y 的确定性纯函数, 供 numjac）=====
q_all = zeros(ny, 4);   u2_all = zeros(ny,1);
for j = 1:ny
    [qj, uuj, ~] = solve_node(CO(j), CCr(j,1), CFe(j,1), CNi(j,1), CSi(j,1), ...
                              CCr2O3(j), CFe3O4(j), CNiFe2O4(j), p, []);
    q_all(j,:) = qj';   u2_all(j) = uuj(2);
end
qCr = q_all(:,1); qSi = q_all(:,2); qMag = q_all(:,3); qTr = q_all(:,4);



% 溶质 sink（保持 J_r 负号约定，直接喂 dsolutedt / lattice velocity）
v_ox  = (2/3)*qCr + 0.5*qSi + 0.75*qMag + 0.75*qTr;
J_r_Cr = -(2/3)*qCr;
J_r_Si = -(1/2)*qSi;
J_r_Fe = -(0.75*qMag + 0.5*qTr);   
J_r_Ni = -(0.25*qTr);



% portion=1./(1+exp(-7*(CNi(:,1)-p.bypass_threshold)));
% if p.bypass==1
%     s_exp = portion .* CNi(:,1) .* v_ox;                 % 排出通量, 去向不追踪
%     J_r_Ni = -(0.25*qTr) - s_exp;
%     s_exp = portion .* CCr(:,1) .* v_ox;                 % 排出通量, 去向不追踪
%     J_r_Cr = -(2/3)*qCr - s_exp;
%     s_exp = portion .* CFe(:,1) .* v_ox;                 % 排出通量, 去向不追踪
%     J_r_Fe = -(0.75*qMag + 0.5*qTr) - s_exp;
%     s_exp = portion .* CSi(:,1) .* v_ox;                 % 排出通量, 去向不追踪
%     J_r_Si = -(1/2)*qSi - s_exp;
% end

% velocity_local = (J_r_Cr1+J_r_Fe1+J_r_Si1)./(CCr(:,1)+CFe(:,1)+CSi(:,1));
% gate = 1./(1+exp((p.vc-abs(velocity_local))/p.vw));
% J_r_Ni = J_r_Ni1+velocity_local.*gate.*CNi(:,1);
% 
% velocity_local = (J_r_Cr1+J_r_Ni1+J_r_Si1)./(CCr(:,1)+CNi(:,1)+CSi(:,1));
% gate = 1./(1+exp((p.vc-abs(velocity_local))/p.vw));
% J_r_Fe = J_r_Fe1+velocity_local.*gate.*CFe(:,1);
% 
% velocity_local = (J_r_Ni1+J_r_Fe1+J_r_Si1)./(CNi(:,1)+CFe(:,1)+CSi(:,1));
% gate = 1./(1+exp((p.vc-abs(velocity_local))/p.vw));
% J_r_Cr = J_r_Cr1+velocity_local.*gate.*CCr(:,1);
% 
% velocity_local = (J_r_Cr1+J_r_Fe1+J_r_Ni1)./(CCr(:,1)+CFe(:,1)+CNi(:,1));
% gate = 1./(1+exp((p.vc-abs(velocity_local))/p.vw));
% J_r_Si = J_r_Si1+velocity_local.*gate.*CSi(:,1);


% J_r_Cr = Jreaction(CCr,CO,p.kCr,2/3,p.DCr2O3O,p.DFe3O4,p.DNiFe2O4,p.DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2);
% J_r_Fe_1 = Jreaction(CFe,CO,p.kFe,3/4,p.DCr2O3Fe,p.DFe3O4,p.DNiFe2O4,p.DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2);
% [J_r_Ni,J_r_Fe_2] = Jcoreaction(CNi,CO,p.kNi,0.25,0.5,p.DCr2O3Ni,p.DFe3O4,p.DNiFe2O4,p.DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2);
% J_r_Fe = J_r_Fe_1+J_r_Fe_2;
% J_r_Si = Jreaction(CSi,CO,p.kSi,1/2,p.DCr2O3O,p.DFe3O4,p.DNiFe2O4,p.DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2);

% F = [ -p.Dgb*(CNi(1,1)-p.Ni_init)/p.dy;      % F(0) 出口面: ghost 储库 Dirichlet
%       -p.Dgb*diff(CNi(:,1))/p.dy;            % 内部面 1..ny-1
%        0 ];                                  % 深端封闭
F = [ -p.Dgb*(CNi(1,1)-p.Ni_init)/p.dy;      % F(0) 出口面: ghost 储库 Dirichlet
      -p.Dgb*diff(CNi(:,1))/p.dy;            % 内部面 1..ny-1
      -p.Dgb*(p.Ni_init-CNi(p.ny,1))/p.dy;  ];                                  % 深端封闭

dNi_gb = -(F(2:end) - F(1:end-1)) / p.dy;    % ny×1 [1/s], 净失 Ni 时 <0

% (a) 站点补偿: 放在 lattice_velocity 求和处 (rhs 前段)
J_r_gb = 0.5*p.dx * dNi_gb;  


lattice_velocity_x = J_V_diff_x-J_I_diff_x;
[ny1,nx1]=size(lattice_velocity_x);
% for i = 1 : nx1
%     lattice_velocity_x(:,i) = lattice_velocity_x(:,i)+J_r_Cr+J_r_Fe+J_r_Ni+J_r_Si;
% end
lattice_velocity_x = lattice_velocity_x + (J_r_Cr+J_r_Fe+J_r_Ni+J_r_Si+J_r_gb);
% for i = 1 : nx1
%     lattice_velocity_x(:,i) = J_V_diff_x(:,1)-J_I_diff_x(:,1)+J_r_Cr+J_r_Fe+J_r_Ni+J_r_Si;
% end

% lattice_velocity_x(:,1) = lattice_velocity_x(:,1)+J_r_Cr+J_r_Fe+J_r_Ni+J_r_Si;

lattice_velocity_y = J_V_diff_y-J_I_diff_y;
[J_Cr_drift_x,J_Cr_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CCr);
[J_Fe_drift_x,J_Fe_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CFe);
[J_Ni_drift_x,J_Ni_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CNi);
[J_Si_drift_x,J_Si_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CSi);
[J_V_drift_x,J_V_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,V);
[J_I_drift_x,J_I_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,I);
J_Cr_x = J_Cr_V_x+J_Cr_I_x+J_Cr_drift_x;
J_Ni_x = J_Ni_V_x+J_Ni_I_x+J_Ni_drift_x;
J_Fe_x = J_Fe_V_x+J_Fe_I_x+J_Fe_drift_x;
J_Si_x = J_Si_V_x+J_Si_I_x+J_Si_drift_x;
J_V_x=J_V_diff_x+J_V_drift_x;
J_I_x=J_I_diff_x+J_I_drift_x;

J_Cr_y = J_Cr_V_y+J_Cr_I_y+J_Cr_drift_y;
J_Ni_y = J_Ni_V_y+J_Ni_I_y+J_Ni_drift_y;
J_Fe_y = J_Fe_V_y+J_Fe_I_y+J_Fe_drift_y;
J_Si_y  = J_Si_V_y+J_Si_I_y+J_Si_drift_y;

% J_Cr_y(:,1) = J_Cr_y(:,1) - p.Dgb * diff(CCr(:,1)) / p.dy;
% J_Fe_y(:,1) = J_Fe_y(:,1) - p.Dgb * diff(CFe(:,1)) / p.dy;
% J_Ni_y(:,1) = J_Ni_y(:,1) - p.Dgb * diff(CNi(:,1)) / p.dy;
% J_Si_y(:,1) = J_Si_y(:,1) - p.Dgb * diff(CSi(:,1)) / p.dy;


J_V_y=J_V_diff_y+J_V_drift_y;
J_I_y=J_I_diff_y+J_I_drift_y;
J_O= JO(CO,CCr2O3,CFe3O4,CNiFe2O4,CSiO2,p.DO0,p.slab,p.DCr2O3,p.DFe3O4,p.DNiFe2O4,p.DSiO2,p.dy);
% 时间导数
dCr = dsolutedt(J_Cr_x, J_Cr_y, p.dx, p.dy,J_r_Cr);
dFe = dsolutedt(J_Fe_x, J_Fe_y, p.dx, p.dy,J_r_Fe);
dNi = dsolutedt(J_Ni_x, J_Ni_y, p.dx, p.dy,J_r_Ni);
dNi(:,1) = dNi(:,1) + dNi_gb;
dSi = dsolutedt(J_Si_x, J_Si_y, p.dx, p.dy,J_r_Si);
dV  = dVdt (J_V_x,J_V_y,p.dx,  p.dy,I, V,   p.dose_rate, p.recomb_rate, p.V_init,p.I_init,p.Ks,lattice_velocity_x);
dI  =  dIdt (J_I_x,J_I_y,p.dx,  p.dy,I, V,   p.dose_rate, p.recomb_rate, p.I_init, p.V_init,p.Ks,lattice_velocity_x);

Q_O = sum(q_all, 2); 
dO = dOdt(CO, J_O, Q_O, p.dy, p.slab);

% dO = dOdt(CCr,CFe,CNi,CSi,CO,J_O,p.kCr,p.kFe,p.kNi,p.kSi,p.dy,p.slab,p.DCr2O3,p.DFe3O4,p.DNiFe2O4,p.DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2);


convCr2O3   = p.Nden*p.Cr2O3mass   /(p.NA*p.Cr2O3den);
convSiO2    = p.Nden*p.SiO2mass    /(p.NA*p.SiO2den);
convFe3O4   = p.Nden*p.Fe3O4mass   /(p.NA*p.Fe3O4den);
convNiFe2O4 = p.Nden*p.NiFe2O4mass /(p.NA*p.NiFe2O4den);

dCr2O3   = (1/3)*qCr .* convCr2O3;
dSiO2    = (1/2)*qSi .* convSiO2  - p.kdiss .* CO .* CSiO2;   % 溶解 sink
dFe3O4   = (1/4)*qMag.* convFe3O4;
dNiFe2O4 = (1/4)*qTr .* convNiFe2O4;


% dCr2O3 = reaction(CO,CCr,p.kCr,p.DCr2O3,p.DFe3O4,p.DNiFe2O4,p.DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2,p.Nden,p.Cr2O3mass,p.NA,p.Cr2O3den,1/3);
% dFe3O4 = reaction(CO,CFe,p.kFe,p.DCr2O3,p.DFe3O4,p.DNiFe2O4,p.DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2,p.Nden,p.Fe3O4mass,p.NA,p.Fe3O4den,1/4);
% dNiFe2O4 = reaction(CO,CNi,p.kNi,p.DCr2O3,p.DFe3O4,p.DNiFe2O4,p.DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2,p.Nden,p.NiFe2O4mass,p.NA,p.NiFe2O4den,1/4);
% dSiO2 = reaction(CO,CSi,p.kSi,p.DCr2O3,p.DFe3O4,p.DNiFe2O4,p.DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2,p.Nden,p.SiO2mass,p.NA,p.SiO2den,1/2);
% Dirichlet 导数置零
dV(:,1)    = 0;
dI(:,1)      = 0;
dCr(:,nx)  = 0;
dFe(:,nx)  = 0;
dNi(:,nx)  = 0;
dSi(:,nx)  = 0;
dO(1,1) = 0;
% 打包：行 -> 列
dydt = [dV(:); dI(:);dCr(:); dFe(:); dNi(:); dSi(:); dO(:);dCr2O3(:);dFe3O4(:);dNiFe2O4(:);dSiO2(:)];


% rhs_aks.m 最后, return 之前
if any(~isfinite(dydt))
    bad = find(~isfinite(dydt));
    fprintf('t=%.4e  NaN/Inf at %d indices, first few: ', t, numel(bad));
    fprintf('%d ', bad(1:min(5,end)));
    fprintf('\n');
    fprintf('  min C: Cr=%g Fe=%g Ni=%g Si=%g O=%g\n', ...
        min(CCr(:)), min(CFe(:)), min(CNi(:)), min(CSi(:)), min(CO(:)));
    fprintf('  min V=%g I=%g\n', min(V(:)), min(I(:)));
end

% [mx, kx] = max(abs(dydt));
% [Cmn_Cr, iCr] = min(CCr(:));
% [Cmn_Si, iSi] = min(CSi(:));
% fprintf('t=%.4e  max|dydt|=%.3e at idx %d   minCr=%.3e@%d  minSi=%.3e@%d  minV=%.3e  minI=%.3e\n', ...
%         t, mx, kx, Cmn_Cr, iCr, Cmn_Si, iSi, min(V(:)), min(I(:)));
end