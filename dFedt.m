function dFe_dt = dFedt(J_Fe,dx)
[ny,nJ]=size(J_Fe);
nx = nJ+1;
grad_J = zeros(1,nx);
for i = 1:nx
    if i == 1
        J_ghost = -J_Fe(i);
        grad_J(i) = (J_Fe(i)-J_ghost)/dx;
    elseif i == nx
        grad_J(i) = 0.0;
    else
        grad_J(i) = (J_Fe(i)-J_Fe(i-1))/dx;
    end
end

dFe_dt = -grad_J;
dFe_dt(nx)=0.0;
end