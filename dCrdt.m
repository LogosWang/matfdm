function dCr_dt = dCrdt(J_Cr,dx)
[ny,nJ]=size(J_Cr);
nx = nJ+1;
grad_J = zeros(1,nx);
for i = 1:nx
    if i == 1
        J_ghost = -J_Cr(i);
        grad_J(i) = (J_Cr(i)-J_ghost)/dx;
    elseif i == nx
        grad_J(i) = 0.0;
    else
        grad_J(i) = (J_Cr(i)-J_Cr(i-1))/dx;
    end
end
dCr_dt = -grad_J;
dCr_dt(nx) = 0.0;
end