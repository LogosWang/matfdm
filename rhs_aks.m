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
J_V      = JV(J_CrCr_V, J_FeFe_V, J_NiNi_V);

% 时间导数
dCr = dCrdt(J_CrCr_V, p.dx, CCr, CFe, CNi, p.GBrecovert);
dFe = dFedt(J_FeFe_V, p.dx, CCr, CFe, CNi, p.GBrecovert);
dNi = dNidt(J_NiNi_V, p.dx, CCr, CFe, CNi, p.GBrecovert);
dV  = dVdt (J_V,      p.dx, V,   p.dose_rate, p.recomb_rate);

% Dirichlet 导数置零
dV(1)    = 0;
dCr(nx)  = 0;
dFe(nx)  = 0;
dNi(nx)  = 0;

% 打包：行 -> 列
dydt = [dV(:); dCr(:); dFe(:); dNi(:)];
end