function dCr_dt = dCrdt(J_CrCr_V,dx,CCr,CFe,CNi,GBrecovert)
[ny,nJ]=size(J_CrCr_V);
nx = nJ+1;
grad_J = zeros(1,nx);
for i = 1:nx
    if i == 1
        J_ghost = -J_CrCr_V(i);
        grad_J(i) = (J_CrCr_V(i)-J_ghost)/dx;
    elseif i == nx
        grad_J(i) = 0.0;
    else
        grad_J(i) = (J_CrCr_V(i)-J_CrCr_V(i-1))/dx;
    end
end
XCr=CCr/(CCr+CFe+CNi);
r = (1.0-CCr-CFe-CNi).*XCr/(GBrecovert);
dCr_dt = -grad_J+r;
dCr_dt(nx) = 0.0;
end