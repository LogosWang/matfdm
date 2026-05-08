function J_SiSi_I = JSiSiI(CSi,I,DI,dx)
[ny,nx]=size(CSi);
L_I_init=zeros(4,4);
log_CSi=log(CSi);
log_I=log(I);
J_SiSi_I = zeros(1,nx-1);
for i=1:nx-1
    L_SiSi_I=L_I_init(4,4);
    L_SiSi_I=((CSi(i)+CSi(i+1))/2)*((I(i)+I(i+1))/2)*DI(4);
    grad_log = ((log_CSi(i+1)+log_I(i+1))-(log_CSi(i)+log_I(i)))/dx;
    J_SiSi_I(i) = -L_SiSi_I*grad_log;
end


end