function dFe_dt = dFedt(J_FeFe_V,dx,CCr,CFe,CNi,GBrecovert)
[ny,nJ]=size(J_FeFe_V);
nx = nJ+1;
grad_J = zeros(1,nx);
for i = 1:nx
    if i == 1
        J_ghost = -J_FeFe_V(i);
        grad_J(i) = (J_FeFe_V(i)-J_ghost)/dx;
    elseif i == nx
        grad_J = 0.0;
    else
        grad_J = (J_FeFe_V(i)-J_FeFe_V(i-1))/dx;
    end
    XFe=CFe/(CCr+CFe+CNi);
    r = (1.0-CCr-CFe-CNi).*XFe/(GBrecovert);
    dFe_dt = -grad_J+r;
    dFe_dt(nx)=0.0;
    
end

end