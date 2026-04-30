function dV_dt = dVdt(J_V,dx,V,dose_rate,recom_rate)
[ny,nJ]=size(J_V);
nx = nJ+1;
grad_J = zeros(1,nx);
for i = 1:nx
    if i == nx
        J_ghost = -J_V(i);
        grad_J(i) = (-J_V(i)+J_ghost)/dx;
    elseif i == 1
        grad_J = 0.0;
    else
        grad_J = (J_V(i)-J_V(i-1))/dx;
    end
    dV_dt = -grad_J+dose_rate-recom_rate*V.*V;
    dV_dt(nx) = 0.0;

end
