function J_r = Jreaction(Ci,CO,k,consume,DCr2O3,DFe3O4,DNiFe2O4,DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2)
[ny,nx]=size(Ci);
J_r = zeros(ny,1);
for i=1:ny
    k_eff = effectivek(k,DCr2O3,DFe3O4,DNiFe2O4,DSiO2,CCr2O3(i,1),CFe3O4(i,1),CNiFe2O4(i,1),CSiO2(i,1));
    J_r(i,1) = -k_eff * consume * CO(i,1)*Ci(i,1);
end
end