function J_r = Jreaction(Ci,CO,k,consume,DCr2O3,DFe3O4,DNiO,DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2)
[ny,nx]=size(Ci);
J_r = zeros(ny,1);
for i=1:ny
    k_eff = effectivek(Ci(i,1),k,DCr2O3,DFe3O4,DNiO,DSiO2,CCr2O3(i,1),CFe3O4(i,1),CNiO(i,1),CSiO2(i,1));
    J_r(i,1) = -k_eff * consume * CO(i,1);
end
end