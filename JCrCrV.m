function J_CrCr_V = JCrCrV(CCr,V,DV,dx)
[ny,nx]=size(CCr);
L_V_init=zeros(4,4);
log_CCr=log(CCr);
log_V=log(V);
J_CrCr_V = zeros(1,nx-1);
for i=1:nx-1
    L_CrCr_V=L_V_init(1,1);
    L_CrCr_V=((CCr(i)+CCr(i+1))/2)*((V(i)+V(i+1))/2)*DV(1);
    grad_log = ((log_CCr(i+1)-log_V(i+1))-(log_CCr(i)-log_V(i)))/dx;
    J_CrCr_V(i) = -L_CrCr_V*grad_log;
end


end