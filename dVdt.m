function dV_dt = dVdt(J_V,dx,I,V,dose_rate,recom_rate)
[ny,nJ]=size(J_V);
nx = nJ+1;
grad_J = zeros(1,nx);
for i = 1:nx
    if i == nx
        J_ghost = -J_V(i-1);
        grad_J(i) = (-J_V(i-1)+J_ghost)/dx;
    elseif i == 1
        grad_J(i) = 0.0;
    else
        grad_J(i) = (J_V(i)-J_V(i-1))/dx;
    end
    dV_dt = -grad_J+dose_rate-recom_rate*I.*V;
    dV_dt(1) = 0.0;

end
