function doxi = reaction(CO,Ci,k,DCr2O3,DFe3O4,DNiO,DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2,Nden,mass,NA,density)
[ny,nx] = size(Ci);
for i = 1:ny
    k_eff = effectivek(Ci(i,1),k,DCr2O3,DFe3O4,DNiO,DSiO2,CCr2O3(i,1),CFe3O4(i,1),CNiO(i,1),CSiO2(i,1));
    doxi(i,1) = k_eff*CO(i,1)*Nden*mass/(NA*density);

end
end