function dV_dt = dVdt(J_V_x,J_V_y,dx,dy,I,V,dose_rate,recom_rate,Veq,Ieq,Ks)
[ny,nx]=size(J_V_x);
nx = nx+1;
grad_J_x = zeros(ny,nx);
grad_J_y = zeros(ny,nx);
div_J = zeros(ny,nx);
for i = 1:nx
    for j = 1:ny
    if i == nx
        J_ghost = -J_V_x(j,i-1);
        grad_J_x(j,i) = (-J_V_x(j,i-1)+J_ghost)/dx;
    elseif i == 1
        grad_J_x(j,i) = 0.0;
    else
        grad_J_x(j,i) = (J_V_x(j,i)-J_V_x(j,i-1))/dx;
    end
    if j == ny
        J_ghost = -J_V_y(j-1,i);
        grad_J_y(j,i) = (-J_V_y(j-1,i)+J_ghost)/dy;
    elseif j == 1
         J_ghost = -J_V_y(j,i);
        grad_J_y(j,i) = (J_V_y(j,i)-J_ghost)/dy;
    else
        grad_J_y(j,i) = (J_V_y(j,i)-J_V_y(j-1,i))/dy;
    end
    end
end
div_J= grad_J_y+grad_J_x;

    dV_dt = -div_J+dose_rate-recom_rate*(I.*V-Ieq*Veq)+Ks*(Veq-V);
    dV_dt(:,1) = 0.0;

end
