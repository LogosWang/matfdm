function k_eff = effectivek(C,k_i,DCr2O3,DFe3O4,DNiO,DSiO2,CCr2O3,CFe3O4,CNiO,CSiO2)
%UNTITLED 此处显示有关此函数的摘要
k_eff=k_i*C*DCr2O3*DFe3O4*DNiO*DSiO2/(DCr2O3*DFe3O4*DNiO*DSiO2+CCr2O3*k_i*DFe3O4*DNiO*DSiO2+CFe3O4*k_i*DCr2O3*DNiO*DSiO2+CNiO*k_i*DFe3O4*DCr2O3*DSiO2+CSiO2*k_i*DFe3O4*DNiO*DCr2O3);
end