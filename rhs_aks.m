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
CNiO   = y(base + 2*ny + 1 : base + 3*ny);
CSiO2  = y(base + 3*ny + 1 : base + 4*ny);
% 强制 Dirichlet（按整条边，不再是单点）
V(:, 1)    = p.V_DBC;
I(:, 1)    = p.I_DBC;
CCr(:, nx) = p.Cr_DCB;
CFe(:, nx) = p.Fe_DCB;
CNi(:, nx) = p.Ni_DCB;
CSi(:, nx) = p.Si_DCB;
CO(1,1) = p.O_DCB;
% 通量
[J_Cr_V_x,J_Cr_V_y] = J_via_medium(1,CCr,CFe,CNi,CSi,V,p.DV,p.f0V,p.dx,p.dy,-1);
[J_Fe_V_x,J_Fe_V_y] =  J_via_medium(2,CCr,CFe,CNi,CSi,V,p.DV,p.f0V,p.dx,p.dy,-1);
[J_Ni_V_x,J_Ni_V_y] =  J_via_medium(3,CCr,CFe,CNi,CSi,V,p.DV,p.f0V,p.dx,p.dy,-1);
[J_Si_V_x,J_Si_V_y] =  J_via_medium(4,CCr,CFe,CNi,CSi,V,p.DV,p.f0V,p.dx,p.dy,-1);
[J_V_diff_x,J_V_diff_y]  = JV(J_Cr_V_x,J_Cr_V_y, J_Fe_V_x, J_Fe_V_y, J_Ni_V_x, J_Ni_V_y, J_Si_V_x, J_Si_V_y);

[J_Cr_I_x,J_Cr_I_y] = J_via_medium(1,CCr,CFe,CNi,CSi,I,p.DI,p.f0I,p.dx,p.dy,1);
[J_Fe_I_x,J_Fe_I_y] = J_via_medium(2,CCr,CFe,CNi,CSi,I,p.DI,p.f0I,p.dx,p.dy,1);
[J_Ni_I_x,J_Ni_I_y] = J_via_medium(3,CCr,CFe,CNi,CSi,I,p.DI,p.f0I,p.dx,p.dy,1);
[J_Si_I_x,J_Si_I_y] = J_via_medium(4,CCr,CFe,CNi,CSi,I,p.DI,p.f0I,p.dx,p.dy,1);
[J_I_diff_x,J_I_diff_y]  = JI(J_Cr_I_x,J_Cr_I_y, J_Fe_I_x, J_Fe_I_y, J_Ni_I_x, J_Ni_I_y, J_Si_I_x, J_Si_I_y);

lattice_velocity_x = J_V_diff_x-J_I_diff_x;
lattice_velocity_y = J_V_diff_y-J_I_diff_y;
[J_Cr_drift_x,J_Cr_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CCr);
[J_Fe_drift_x,J_Fe_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CFe);
[J_Ni_drift_x,J_Ni_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CNi);
[J_Si_drift_x,J_Si_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,CSi);
% J_V_drift = JVdrift(lattice_velocity,V);
J_Cr_x = J_Cr_V_x+J_Cr_I_x+J_Cr_drift_x;
J_Ni_x = J_Ni_V_x+J_Ni_I_x+J_Ni_drift_x;
J_Fe_x = J_Fe_V_x+J_Fe_I_x+J_Fe_drift_x;
J_Si_x = J_Si_V_x+J_Si_I_x+J_Si_drift_x;
J_V_x=J_V_diff_x;
J_I_x=J_I_diff_x;

J_Cr_y = J_Cr_V_y+J_Cr_I_y+J_Cr_drift_y;
J_Ni_y = J_Ni_V_y+J_Ni_I_y+J_Ni_drift_y;
J_Fe_y = J_Fe_V_y+J_Fe_I_y+J_Fe_drift_y;
J_Si_y  = J_Si_V_y+J_Si_I_y+J_Si_drift_y;
J_V_y=J_V_diff_y;
J_I_y=J_I_diff_y;
J_O= JO(CO,CCr2O3,CNiO,CSiO2,p.alpha,p.DO0,p.DOmax,p.oxide_character,p.dy);
% 时间导数
dCr = dsolutedt(J_Cr_x, J_Cr_y, p.dx, p.dy,CCr,CO,p.kCr,2);
dFe = dsolutedt(J_Fe_x, J_Fe_y, p.dx, p.dy,CFe,CO,0.0,0);
dNi = dsolutedt(J_Ni_x, J_Ni_y, p.dx, p.dy,CNi,CO,p.kNi,1);
dSi = dsolutedt(J_Si_x, J_Si_y, p.dx, p.dy,CSi,CO,p.kSi,1);
dV  = dVdt (J_V_x,J_V_y,p.dx,  p.dy,I, V,   p.dose_rate, p.recomb_rate);
dI  =  dIdt (J_I_x,J_I_y,p.dx,  p.dy,I, V,   p.dose_rate, p.recomb_rate);
dO = dOdt(CCr,CFe,CNi,CSi,CO,J_O,p.kCr,p.kNi,p.kSi,p.dy);
dCr2O3 = reaction(CO,CCr,p.kCr);
dNiO = reaction(CO,CNi,p.kNi);
dSiO2 = reaction(CO,CSi,p.kSi);
% Dirichlet 导数置零
dV(:,1)    = 0;
dI(:,1)      = 0;
dCr(:,nx)  = 0;
dFe(:,nx)  = 0;
dNi(:,nx)  = 0;
dSi(:,nx)  = 0;
dO(1,1) = 0;
% 打包：行 -> 列
dydt = [dV(:); dI(:);dCr(:); dFe(:); dNi(:); dSi(:); dO(:);dCr2O3(:);dNiO(:);dSiO2(:)];
end