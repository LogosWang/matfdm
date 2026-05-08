function J_SiSi_V = JSiSiV(CSi,V,DV,dx)
[ny,nx]=size(CSi);
L_V_init=zeros(4,4);
log_CSi=log(CSi);
log_V=log(V);
J_SiSi_V = zeros(1,nx-1);
for i=1:nx-1
    L_SiSi_V=L_V_init(4,4);
    L_SiSi_V=((CSi(i)+CSi(i+1))/2)*((V(i)+V(i+1))/2)*DV(4);
    grad_log = ((log_CSi(i+1)-log_V(i+1))-(log_CSi(i)-log_V(i)))/dx;
    J_SiSi_V(i) = -L_SiSi_V*grad_log;
end


end