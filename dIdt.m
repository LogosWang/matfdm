function dI_dt = dIdt(J_I,dx,I,V,dose_rate,recom_rate)
[ny,nJ]=size(J_I);
nx = nJ+1;
grad_J = zeros(1,nx);
for i = 1:nx
    if i == nx
        J_ghost = -J_I(i-1);
        grad_J(i) = (-J_I(i-1)+J_ghost)/dx;
    elseif i == 1
        grad_J(i) = 0.0;
    else
        grad_J(i) = (J_I(i)-J_I(i-1))/dx;
    end
    dI_dt = -grad_J+dose_rate-recom_rate*I.*V;
    dI_dt(1) = 0.0;

end
