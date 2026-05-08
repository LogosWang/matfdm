function J_FeFe_I = JFeFeI(CFe,I,DI,dx)
[ny,nx]=size(CFe);
L_I_init=zeros(4,4);
log_CFe=log(CFe);
log_I=log(I);
J_FeFe_I = zeros(1,nx-1);
for i=1:nx-1
    L_FeFe_I=L_I_init(2,2);
    L_FeFe_I=((CFe(i)+CFe(i+1))/2)*((I(i)+I(i+1))/2)*DI(2);
    grad_log = ((log_CFe(i+1)+log_I(i+1))-(log_CFe(i)+log_I(i)))/dx;
    J_FeFe_I(i) = -L_FeFe_I*grad_log;
end
end