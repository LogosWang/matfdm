function dSi_dt = dSidt(J_Si,dx)
[ny,nJ]=size(J_Si);
nx = nJ+1;
grad_J = zeros(1,nx);
for i = 1:nx
    if i == 1
        J_ghost = -J_Si(i);
        grad_J(i) = (J_Si(i)-J_ghost)/dx;
    elseif i == nx
        grad_J(i) = 0.0;
    else
        grad_J(i) = (J_Si(i)-J_Si(i-1))/dx;
    end
end
dSi_dt = -grad_J;
dSi_dt(nx) = 0.0;
end