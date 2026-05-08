function J_NiNi_I = JNiNiI(CNi,I,DI,dx)
[ny,nx]=size(CNi);
L_I_init=zeros(4,4);
log_CNi=log(CNi);
log_I=log(I);
J_NiNi_I = zeros(1,nx-1);
for i=1:nx-1
    L_NiNi_I=L_I_init(3,3);
    L_NiNi_I=((CNi(i)+CNi(i+1))/2)*((I(i)+I(i+1))/2)*DI(3);
    grad_log = ((log_CNi(i+1)+log_I(i+1))-(log_CNi(i)+log_I(i)))/dx;
    J_NiNi_I(i) = -L_NiNi_I*grad_log;
end


end