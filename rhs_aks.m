function dydt = rhs_aks(t, y, p)
nx = p.nx;

% 拆包：列向量 -> 行向量
V   = y(        1 :   nx).';
CCr = y(  nx + 1 : 2*nx).';
CFe = y(2*nx + 1 : 3*nx).';
CNi = y(3*nx + 1 : 4*nx).';

% 强制 Dirichlet
V(1)    = p.V_DBC;
CCr(nx) = p.Cr_DCB;
CFe(nx) = p.Fe_DCB;
CNi(nx) = p.Ni_DCB;

% 通量
J_CrCr_V = JCrCrV(CCr, V, p.DV, p.dx);
J_FeFe_V = JFeFeV(CFe, V, p.DV, p.dx);
J_NiNi_V = JNiNiV(CNi, V, p.DV, p.dx);
J_V_diff      = JV(J_CrCr_V, J_FeFe_V, J_NiNi_V);
lattice_velocity = J_V_diff;
J_Cr_drift = JCrdrift(lattice_velocity,CCr);
J_Fe_drift = JFedrift(lattice_velocity,CFe);
J_Ni_drift = JNidrift(lattice_velocity,CNi);
J_V_drift = JVdrift(lattice_velocity,V);
J_Cr = J_CrCr_V+J_Cr_drift;
J_Ni = J_NiNi_V+J_Ni_drift;
J_Fe = J_FeFe_V+J_Fe_drift;
J_V=J_V_diff;
% 时间导数
dCr = dCrdt(J_Cr, p.dx, CCr, CFe, CNi, p.GBrecovert);
dFe = dFedt(J_Fe, p.dx, CCr, CFe, CNi, p.GBrecovert);
dNi = dNidt(J_Ni, p.dx, CCr, CFe, CNi, p.GBrecovert);
dV  = dVdt (J_V,      p.dx, V,   p.dose_rate, p.recomb_rate);

% Dirichlet 导数置零
dV(1)    = 0;
dCr(nx)  = 0;
dFe(nx)  = 0;
dNi(nx)  = 0;

% 打包：行 -> 列
dydt = [dV(:); dCr(:); dFe(:); dNi(:)];
end