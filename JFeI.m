function J_Fe_I = JFeI(CCr,CFe,CNi,CSi,I,DI,f0,dx)
[ny,nx]=size(CFe);
L_I_init=zeros(4,4);
log_CCr=log(CCr);
log_CFe=log(CFe);
log_CNi=log(CNi);
log_CSi=log(CSi);
log_I=log(I);
J_Fe_I = zeros(1,nx-1);
for i=1:nx-1
    L_I=L_I_init;
    L_I= Calc_L((I(i)+I(i+1))/2,(CCr(i)+CCr(i+1))/2,(CFe(i)+CFe(i+1))/2,(CNi(i)+CNi(i+1))/2,(CSi(i)+CSi(i+1))/2,DI,f0);
    grad_log_Cr = ((log_CCr(i+1)+log_I(i+1))-(log_CCr(i)+log_I(i)))/dx;
    grad_log_Fe = ((log_CFe(i+1)+log_I(i+1))-(log_CFe(i)+log_I(i)))/dx;
    grad_log_Ni = ((log_CNi(i+1)+log_I(i+1))-(log_CNi(i)+log_I(i)))/dx;
    grad_log_Si = ((log_CSi(i+1)+log_I(i+1))-(log_CSi(i)+log_I(i)))/dx;
    J_Fe_I(i) = -L_I(2,1)*grad_log_Cr-L_I(2,2)*grad_log_Fe-L_I(2,3)*grad_log_Ni-L_I(2,4)*grad_log_Si;
end