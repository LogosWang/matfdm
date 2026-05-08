function dNi_dt = dNidt(J_Ni,dx)
[ny,nJ]=size(J_Ni);
nx = nJ+1;
grad_J = zeros(1,nx);
for i = 1:nx
    if i == 1
        J_ghost = -J_Ni(i);
        grad_J(i) = (J_Ni(i)-J_ghost)/dx;
    elseif i == nx
        grad_J(i) = 0.0;
    else
        grad_J(i) = (J_Ni(i)-J_Ni(i-1))/dx;
    end
end

dNi_dt = -grad_J;
dNi_dt(nx) = 0.0;

end