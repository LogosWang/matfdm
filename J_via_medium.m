function [Jx,Jy] =  J_via_medium(idx, CCr, CFe, CNi, CSi, media, D, f0, dx, dy, sign_media)
[ny,nx]=size(CCr);
L_init=zeros(4,4);
log_CCr=log(CCr);
log_CFe=log(CFe);
log_CNi=log(CNi);
log_CSi=log(CSi);
log_m=log(media);
Jx = zeros(ny,nx-1);
Jy = zeros(ny-1,nx);
for i=1:nx-1
    for j = 1:ny
        L=L_init;
        L= Calc_L((media(j,i)+media(j,i+1))/2,(CCr(j,i)+CCr(j,i+1))/2,(CFe(j,i)+CFe(j,i+1))/2,(CNi(j,i)+CNi(j,i+1))/2,(CSi(j,i)+CSi(j,i+1))/2,D,f0);
        grad_log_Cr = ((log_CCr(j,i+1)+sign_media*log_m(j,i+1))-(log_CCr(j,i)+sign_media*log_m(j,i)))/dx;
        grad_log_Fe = ((log_CFe(j,i+1)+sign_media*log_m(j,i+1))-(log_CFe(j,i)+sign_media*log_m(j,i)))/dx;
        grad_log_Ni = ((log_CNi(j,i+1)+sign_media*log_m(j,i+1))-(log_CNi(j,i)+sign_media*log_m(j,i)))/dx;
        grad_log_Si = ((log_CSi(j,i+1)+sign_media*log_m(j,i+1))-(log_CSi(j,i)+sign_media*log_m(j,i)))/dx;
        Jx(j,i) = -L(idx,1)*grad_log_Cr-L(idx,2)*grad_log_Fe-L(idx,3)*grad_log_Ni-L(idx,4)*grad_log_Si;
    end
end
for i=1:nx
    for j = 1:ny-1
        L=L_init;
        L= Calc_L((media(j,i)+media(j+1,i))/2,(CCr(j,i)+CCr(j+1,i))/2,(CFe(j,i)+CFe(j+1,i))/2,(CNi(j,i)+CNi(j+1,i))/2,(CSi(j,i)+CSi(j+1,i))/2,D,f0);
        grad_log_Cr = ((log_CCr(j+1,i)+sign_media*log_m(j+1,i))-(log_CCr(j,i)+sign_media*log_m(j,i)))/dy;
        grad_log_Fe = ((log_CFe(j+1,i)+sign_media*log_m(j+1,i))-(log_CFe(j,i)+sign_media*log_m(j,i)))/dy;
        grad_log_Ni = ((log_CNi(j+1,i)+sign_media*log_m(j+1,i))-(log_CNi(j,i)+sign_media*log_m(j,i)))/dy;
        grad_log_Si = ((log_CSi(j+1,i)+sign_media*log_m(j+1,i))-(log_CSi(j,i)+sign_media*log_m(j,i)))/dy;
        Jy(j,i) = -L(idx,1)*grad_log_Cr-L(idx,2)*grad_log_Fe-L(idx,3)*grad_log_Ni-L(idx,4)*grad_log_Si;
    end
end
end