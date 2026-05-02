
dim = 1
nx = 100
ny = 1
dt = 0.00001
GBrecovert=0.8*dt;
current_t = 0.0
current_tstep = 0

dx = 0.1
V_init = 1e-10
V_DBC = 1e-10
DCrV = 1e3;
DFeV = 2e2;
DNiV = 4e1;
dose_rate = 1e-6;
recomb_rate = 1e4;
DV = [DCrV, DFeV, DNiV]
Cr_init = 0.18;
Fe_init = 0.72;
Ni_init = 0.10;
CCr = ones(1,nx);
CCr = CCr*Cr_init;

CFe = ones(1,nx);
CFe = CFe*Fe_init;

CNi = ones(1,nx);
CNi = CNi*Ni_init;

Cr_DCB = 0.18;
Ni_DCB = 0.10;
Fe_DCB = 0.72;

V=ones(1,nx)
V=V*V_init
t_end = 100.0;
while current_t < t_end
    V(1) = V_DBC;
    CCr(nx) = Cr_DCB;
    CFe(nx) = Fe_DCB;
    CNi(nx) = Ni_DCB;
    J_CrCr_V = JCrCrV(CCr,V,DV,dx);
    J_FeFe_V = JFeFeV(CFe,V,DV,dx);
    J_NiNi_V = JNiNiV(CNi,V,DV,dx);
    J_V = JV(J_CrCr_V,J_FeFe_V,J_NiNi_V);
    dCr_dt = dCrdt(J_CrCr_V,dx,CCr,CFe,CNi,GBrecovert);
    dFe_dt = dFedt(J_FeFe_V,dx,CCr,CFe,CNi,GBrecovert);
    dNi_dt = dNidt(J_NiNi_V,dx,CCr,CFe,CNi,GBrecovert);
    dV_dt = dVdt(J_V,dx,V,dose_rate,recomb_rate);
    V = V+dV_dt*dt;
    CCr = CCr+dCr_dt*dt;
    CFe = CFe+dFe_dt*dt;
    CNi = CNi+dNi_dt*dt;
    current_t = current_t+dt;
    current_tstep = current_tstep + 1;
    if mod(current_tstep,10000) == 0

        writematrix(V, ['V', num2str(current_tstep), '.csv'])
        writematrix(CCr, ['Cr', num2str(current_tstep), '.csv'])
        writematrix(CFe, ['Fe', num2str(current_tstep), '.csv'])
        writematrix(CNi, ['Ni', num2str(current_tstep), '.csv'])
        

    end
end


x=linspace(0,9.9,100)
figure(1)
plot(x,V, 'LineWidth', 3)
xlabel('x (nm)', 'FontSize', 24)
ylabel('Vacancy Concentration (%)', 'FontSize', 24)
set(gca, 'FontSize', 20)
% title('Concentration Profile', 'FontSize', 18)
figure(2)
plot(x,CCr, 'LineWidth', 3)
xlabel('x (nm)', 'FontSize', 24)
ylabel('Cr Concentration (%)', 'FontSize', 24)
set(gca, 'FontSize', 20)
figure(3)
plot(x,CFe, 'LineWidth', 3)
xlabel('x (nm)', 'FontSize', 24)
ylabel('Cr Concentration (%)', 'FontSize', 24)
set(gca, 'FontSize', 20)
figure(4)
plot(x,CNi, 'LineWidth', 3)
xlabel('x (nm)', 'FontSize', 24)
ylabel('Ni Concentration (%)', 'FontSize', 24)
set(gca, 'FontSize', 20)