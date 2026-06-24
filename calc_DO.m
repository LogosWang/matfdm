function DO = calc_DO(CCr2O3,CFe3O4,CNiO,CSiO2,DO0,slab,DCr2O3,DFe3O4,DNiO,DSiO2)
% 与原分段函数三个极限一致 (S=0 -> DO0, S=slab -> W/slab, S>>slab -> W/S)
% 全程 C^infinity 光滑, 雅可比无跳变
eps_s = 1e-2 * slab;             % 过渡圆滑宽度, 越小越接近原函数

S    = CCr2O3 + CFe3O4 + CNiO + CSiO2;
smax = 0.5*(slab + S + sqrt((slab - S).^2 + eps_s^2));   % 光滑 max(slab, S)

DO = DO0 + ( CCr2O3*(DCr2O3 - DO0) ...
           + CFe3O4*(DFe3O4 - DO0) ...
           + CNiO  *(DNiO   - DO0) ...
           + CSiO2 *(DSiO2  - DO0) ) / smax;
end

