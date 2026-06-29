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
CNiO   = y(base + 3*ny + 1 : base + 4*ny);
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
J_r_Cr = Jreaction(CCr,CO,p.kCr,2/3,p.DCr2O3,p.DFe3O4,p.DNiO,p.DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2);
J_r_Fe = Jreaction(CFe,CO,p.kFe,3/4,p.DCr2O3,p.DFe3O4,p.DNiO,p.DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2);
J_r_Ni = Jreaction(CNi,CO,p.kNi,1,p.DCr2O3,p.DFe3O4,p.DNiO,p.DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2);
J_r_Si = Jreaction(CSi,CO,p.kSi,1/2,p.DCr2O3,p.DFe3O4,p.DNiO,p.DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2);


lattice_velocity_x = J_V_diff_x-J_I_diff_x;
[ny1,nx1]=size(lattice_velocity_x);
for i = 1 : nx1
    lattice_velocity_x(:,i) = lattice_velocity_x(:,i)+J_r_Cr+J_r_Fe+J_r_Ni+J_r_Si;
end

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
J_V_y=J_V_diff_y+J_V_drift_y;
J_I_y=J_I_diff_y+J_I_drift_y;
J_O= JO(CO,CCr2O3,CFe3O4,CNiO,CSiO2,p.DO0,p.slab,p.DCr2O3,p.DFe3O4,p.DNiO,p.DSiO2,p.dy);
% 时间导数
dCr = dsolutedt(J_Cr_x, J_Cr_y, p.dx, p.dy,J_r_Cr);
dFe = dsolutedt(J_Fe_x, J_Fe_y, p.dx, p.dy,J_r_Fe);
dNi = dsolutedt(J_Ni_x, J_Ni_y, p.dx, p.dy,J_r_Ni);
dSi = dsolutedt(J_Si_x, J_Si_y, p.dx, p.dy,J_r_Si);
dV  = dVdt (J_V_x,J_V_y,p.dx,  p.dy,I, V,   p.dose_rate, p.recomb_rate, p.V_init,p.I_init,p.Ks,lattice_velocity_x);
dI  =  dIdt (J_I_x,J_I_y,p.dx,  p.dy,I, V,   p.dose_rate, p.recomb_rate, p.I_init, p.V_init,p.Ks,lattice_velocity_x);
dO = dOdt(CCr,CFe,CNi,CSi,CO,J_O,p.kCr,p.kFe,p.kNi,p.kSi,p.dy,p.slab,p.DCr2O3,p.DFe3O4,p.DNiO,p.DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2);
dCr2O3 = reaction(CO,CCr,p.kCr,p.DCr2O3,p.DFe3O4,p.DNiO,p.DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2,p.Nden,p.Cr2O3mass,p.NA,p.Cr2O3den,1/3);
dFe3O4 = reaction(CO,CFe,p.kFe,p.DCr2O3,p.DFe3O4,p.DNiO,p.DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2,p.Nden,p.Fe3O4mass,p.NA,p.Fe3O4den,1/4);
dNiO = reaction(CO,CNi,p.kNi,p.DCr2O3,p.DFe3O4,p.DNiO,p.DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2,p.Nden,p.NiOmass,p.NA,p.NiOden,1);
dSiO2 = reaction(CO,CSi,p.kSi,p.DCr2O3,p.DFe3O4,p.DNiO,p.DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2,p.Nden,p.SiO2mass,p.NA,p.SiO2den,1/2);
% Dirichlet 导数置零
dV(:,1)    = 0;
dI(:,1)      = 0;
dCr(:,nx)  = 0;
dFe(:,nx)  = 0;
dNi(:,nx)  = 0;
dSi(:,nx)  = 0;
dO(1,1) = 0;
% 打包：行 -> 列
dydt = [dV(:); dI(:);dCr(:); dFe(:); dNi(:); dSi(:); dO(:);dCr2O3(:);dFe3O4(:);dNiO(:);dSiO2(:)];


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