function dNi_dt = dNidt(J_NiNi_V,dx,CCr,CFe,CNi,GBrecovert)
[ny,nJ]=size(J_NiNi_V);
nx = nJ+1;
grad_J = zeros(1,nx);
for i = 1:nx
    if i == 1
        J_ghost = -J_NiNi_V(i);
        grad_J(i) = (J_NiNi_V(i)-J_ghost)/dx;
    elseif i == nx
        grad_J(i) = 0.0;
    else
        grad_J(i) = (J_NiNi_V(i)-J_NiNi_V(i-1))/dx;
    end
    XNi=CCr/(CCr+CFe+CNi);
    r = (1.0-CCr-CFe-CNi).*XNi/(GBrecovert);
    dNi_dt = -grad_J+r;
    dNi_dt(nx) = 0.0;

end

end