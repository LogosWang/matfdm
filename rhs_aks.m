function dydt = rhs_aks(t, y, p)
nx = p.nx;

% 拆包：列向量 -> 行向量
V   = y(        1 :   nx).';
I    = y(nx + 1 : 2* nx).';
CCr = y(2* nx + 1 : 3*nx).';
CFe = y(3*nx + 1 : 4*nx).';
CNi = y(4*nx + 1 : 5*nx).';
CSi = y(5*nx + 1 : 6*nx).';
% 强制 Dirichlet
V(1)    = p.V_DBC;
I(1)     = p.I_DBC;
CCr(nx) = p.Cr_DCB;
CFe(nx) = p.Fe_DCB;
CNi(nx) = p.Ni_DCB;
CSi(nx) = p.Si_DCB;
% 通量
J_Cr_V = JCrV(CCr,CFe,CNi,CSi,V,p.DV,p.f0V, p.dx);
J_Fe_V = JFeV(CCr,CFe,CNi,CSi,V,p.DV,p.f0V, p.dx);
J_Ni_V = JNiV(CCr,CFe,CNi,CSi,V,p.DV,p.f0V, p.dx);
J_Si_V = JSiV(CCr,CFe,CNi,CSi,V,p.DV,p.f0V, p.dx);
J_V_diff  = JV(J_Cr_V, J_Fe_V, J_Ni_V, J_Si_V);

J_Cr_I = JCrI(CCr,CFe,CNi,CSi,I,p.DI,p.f0I, p.dx);
J_Fe_I = JFeI(CCr,CFe,CNi,CSi,I,p.DI,p.f0I, p.dx);
J_Ni_I = JNiI(CCr,CFe,CNi,CSi,I,p.DI,p.f0I, p.dx);
J_Si_I = JSiI(CCr,CFe,CNi,CSi,I,p.DI,p.f0I, p.dx);
J_I_diff  = JI(J_Cr_I, J_Fe_I, J_Ni_I, J_Si_I);

lattice_velocity = J_V_diff-J_I_diff;

J_Cr_drift = JCrdrift(lattice_velocity,CCr);
J_Fe_drift = JFedrift(lattice_velocity,CFe);
J_Ni_drift = JNidrift(lattice_velocity,CNi);
J_Si_drift = JSidrift(lattice_velocity,CSi);
% J_V_drift = JVdrift(lattice_velocity,V);
J_Cr = J_Cr_V+J_Cr_I+J_Cr_drift;
J_Ni = J_Ni_V+J_Ni_I+J_Ni_drift;
J_Fe = J_Fe_V+J_Fe_I+J_Fe_drift;
J_Si = J_Si_V+J_Si_I+J_Si_drift;
J_V=J_V_diff;
J_I=J_I_diff;
% 时间导数
dCr = dCrdt(J_Cr, p.dx);
dFe = dFedt(J_Fe, p.dx);
dNi = dNidt(J_Ni, p.dx);
dSi = dSidt(J_Si, p.dx);
dV  = dVdt (J_V,      p.dx,I, V,   p.dose_rate, p.recomb_rate);
dI  = dIdt (J_I,      p.dx,I, V,   p.dose_rate, p.recomb_rate);
% Dirichlet 导数置零
dV(1)    = 0;
dI(1)      = 0;
dCr(nx)  = 0;
dFe(nx)  = 0;
dNi(nx)  = 0;
dSi(nx)  = 0;
% 打包：行 -> 列
dydt = [dV(:); dI(:);dCr(:); dFe(:); dNi(:); dSi(:)];
end