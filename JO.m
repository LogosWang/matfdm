function J_O = JO(CO,CCr2O3,CFe3O4,CNiFe2O4,CSiO2,DO0,slab,DCr2O3,DFe3O4,DNiFe2O4,DSiO2,dy)
[ny,nx] = size(CO);
ny = ny-1;
J_O= zeros(ny,1);
for i = 1:ny
    DO = calc_DO((CCr2O3(i,1)+CCr2O3(i+1,1))/2,(CFe3O4(i,1)+CFe3O4(i+1,1))/2,(CNiFe2O4(i,1)+CNiFe2O4(i+1,1))/2,(CSiO2(i,1)+CSiO2(i+1,1))/2,DO0,slab,DCr2O3,DFe3O4,DNiFe2O4,DSiO2);
    grad = (CO(i+1,1)-CO(i,1))/dy;
    J_O(i,1)=-DO*grad;
end
end