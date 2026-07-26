function J_O = JO(CO,CCr2O3,CFe3O4,CNiFe2O4,CSiO2,DO0,slab,DCr2O3,DFe3O4,DNiFe2O4,DSiO2,dy)
[ny,nx] = size(CO);
ny = ny-1;
J_O= zeros(ny,1);
% for i = 1:ny
%     DO = calc_DO((CCr2O3(i,1)+CCr2O3(i+1,1))/2,(CFe3O4(i,1)+CFe3O4(i+1,1))/2,(CNiFe2O4(i,1)+CNiFe2O4(i+1,1))/2,(CSiO2(i,1)+CSiO2(i+1,1))/2,DO0,slab,DCr2O3,DFe3O4,DNiFe2O4,DSiO2);
%     grad = (CO(i+1,1)-CO(i,1))/dy;
%     J_O(i,1)=-DO*grad;
% end
% 改后：节点 D 用 calc_DO（并联 EMT 不变），面值取两节点调和
D_n = calc_DO(CCr2O3(:,1),CFe3O4(:,1),CNiFe2O4(:,1),CSiO2(:,1), ...
              DO0,slab,DCr2O3,DFe3O4,DNiFe2O4,DSiO2);      % ny×1 节点值
Dl  = D_n(1:end-1);   Dr = D_n(2:end);
% Df  = 2*Dl.*Dr ./ (Dl + Dr + 1e-300);                      % (ny-1)×1 面值
Df  = (Dl + Dr)/2;  
J_O = -Df .* diff(CO(:,1)) / dy;    
end