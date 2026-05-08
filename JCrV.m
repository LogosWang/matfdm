function J_Cr_V = JCrV(CCr,CFe,CNi,CSi,V,DV,f0,dx)
[ny,nx]=size(CCr);
L_V_init=zeros(4,4);
log_CCr=log(CCr);
log_CFe=log(CFe);
log_CNi=log(CNi);
log_CSi=log(CSi);
log_V=log(V);
J_Cr_V = zeros(1,nx-1);
for i=1:nx-1
    L_V=L_V_init;
    L_V= Calc_L((V(i)+V(i+1))/2,(CCr(i)+CCr(i+1))/2,(CFe(i)+CFe(i+1))/2,(CNi(i)+CNi(i+1))/2,(CSi(i)+CSi(i+1))/2,DV,f0);
    grad_log_Cr = ((log_CCr(i+1)-log_V(i+1))-(log_CCr(i)-log_V(i)))/dx;
    grad_log_Fe = ((log_CFe(i+1)-log_V(i+1))-(log_CFe(i)-log_V(i)))/dx;
    grad_log_Ni = ((log_CNi(i+1)-log_V(i+1))-(log_CNi(i)-log_V(i)))/dx;
    grad_log_Si = ((log_CSi(i+1)-log_V(i+1))-(log_CSi(i)-log_V(i)))/dx;
    J_Cr_V(i) = -L_V(1,1)*grad_log_Cr-L_V(1,2)*grad_log_Fe-L_V(1,3)*grad_log_Ni-L_V(1,4)*grad_log_Si;
end


end