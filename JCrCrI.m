function J_CrCr_I = JCrCrI(CCr,I,DI,dx)
[ny,nx]=size(CCr);
L_I_init=zeros(4,4);
log_CCr=log(CCr);
log_I=log(I);
J_CrCr_I = zeros(1,nx-1);
for i=1:nx-1
    L_CrCr_I=L_I_init(1,1);
    L_CrCr_I=((CCr(i)+CCr(i+1))/2)*((I(i)+I(i+1))/2)*DI(1);
    grad_log = ((log_CCr(i+1)+log_I(i+1))-(log_CCr(i)+log_I(i)))/dx;
    J_CrCr_I(i) = -L_CrCr_I*grad_log;
end
end