function doxi = reaction(CO,Ci,k,DCr2O3,DFe3O4,DNiFe2O4,DSiO2,CCr2O3,CFe3O4,CNiFe2O4,CSiO2,Nden,mass,NA,density,consume)
[ny,nx] = size(Ci);
for i = 1:ny
    k_eff = effectivek(k,DCr2O3,DFe3O4,DNiFe2O4,DSiO2,CCr2O3(i,1),CFe3O4(i,1),CNiFe2O4(i,1),CSiO2(i,1));
    doxi(i,1) = consume*k_eff*Ci(i,1)*CO(i,1)*Nden*mass/(NA*density);

end
end