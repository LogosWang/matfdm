function J_NiNi_V = JNiNiV(CNi,V,DV,dx)
[ny,nx]=size(CNi);
L_V_init=zeros(3,3);
log_CNi=log(CNi);
log_V=log(V);
J_NiNi_V = zeros(1,nx-1);
for i=1:nx-1
    L_NiNi_V=L_V_init(3,3);
    L_NiNi_V=((CNi(i)+CNi(i+1))/2)*((V(i)+V(i+1))/2)*DV(3);
    grad_log = ((log_CNi(i+1)-log_V(i+1))-(log_CNi(i)-log_V(i)))/dx;
    J_NiNi_V(i) = -L_NiNi_V*grad_log;
end


end