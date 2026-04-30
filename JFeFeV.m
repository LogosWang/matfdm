function J_FeFe_V = JFeFeV(CFe,V,DV,dx)
[ny,nx]=size(CFe);
L_V_init=zeros(3,3);
log_CFe=log(CFe);
log_V=log(V);
J_FeFe_V = zeros(1,nx-1);
for i=1:nx-1
    L_FeFe_V=L_V_init(3,3);
    L_FeFe_V=((CFe(i)+CFe(i+1))/2)*((V(i)+V(i+1))/2)*DV(2);
    grad_log = ((log_CFe(i+1)-log_V(i+1))-(log_CFe(i)-log_V(i)))/dx;
    J_FeFe_V(i) = -L_FeFe_V*grad_log;
end


end