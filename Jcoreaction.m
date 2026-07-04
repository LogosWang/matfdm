function [J_r_1,J_r_2] = Jcoreaction(Ci,CO,k,consume1,consume2,DCr2O3,DFe3O4,DNiFe2O4,DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2)
[ny,nx]=size(Ci);
J_r_1 = zeros(ny,1);
J_r_2 = zeros(ny,1);
for i=1:ny
    k_eff = effectivek(k,DCr2O3,DFe3O4,DNiFe2O4,DSiO2,CCr2O3(i,1),CFe3O4(i,1),CNiFe2O4(i,1),CSiO2(i,1));
    J_r_1(i,1) = -k_eff * consume1 * CO(i,1)*Ci(i,1);
    J_r_2(i,1) = -k_eff * consume2 * CO(i,1)*Ci(i,1);
end
end