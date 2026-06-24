function dO = dOdt(CCr,CFe,CNi,CSi,CO,J_O,kCr,kFe,kNi,kSi,dy,slab,DCr2O3,DFe3O4,DNiO,DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2)
[ny,nx]=size(CO);
dO = zeros(ny,1);
grad = zeros(ny,1);
for i = 1:ny
    if i ==1
        grad(i,1)=0.0;
    elseif i == ny
        jghost=-J_O(i-1,1);
        grad(i,1)=(jghost-J_O(i-1,1))/dy;
    else
        grad(i,1) = (J_O(i,1)-J_O(i-1,1))/dy;
    end
end
for i = 1:ny
    kCr_eff = effectivek(CCr(i,1),kCr,DCr2O3,DFe3O4,DNiO,DSiO2,CCr2O3(i,1),CFe3O4(i,1),CNiO(i,1),CSiO2(i,1));
    kFe_eff = effectivek(CFe(i,1),kFe,DCr2O3,DFe3O4,DNiO,DSiO2,CCr2O3(i,1),CFe3O4(i,1),CNiO(i,1),CSiO2(i,1));
    kNi_eff = effectivek(CNi(i,1),kNi,DCr2O3,DFe3O4,DNiO,DSiO2,CCr2O3(i,1),CFe3O4(i,1),CNiO(i,1),CSiO2(i,1));
    kSi_eff = effectivek(CSi(i,1),kSi,DCr2O3,DFe3O4,DNiO,DSiO2,CCr2O3(i,1),CFe3O4(i,1),CNiO(i,1),CSiO2(i,1));
    dO(i,1) = -grad(i,1)+(-3*kCr_eff*CO(i,1)-4*kFe_eff*CO(i,1)-kNi_eff*CO(i,1)-2*kSi_eff*CO(i,1))/slab;
end
dO(1,1) = 0.0;

end