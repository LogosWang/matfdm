function dSdt = dsolutedt(J_S_x,J_S_y,dx,dy)
[ny,nx]=size(J_S_x);
nx = nx+1;
div_J = zeros(ny,nx);
grad_J_x = zeros(ny,nx);
grad_J_y = zeros(ny,nx);
for i = 1:nx
    for j = 1:ny
    if i == 1
        J_ghost = -J_S_x(j,i);
        grad_J_x(j,i) = (J_S_x(j,i)-J_ghost)/dx;
    elseif i == nx
        grad_J_x(j,i) = 0.0;
    else
        grad_J_x(j,i) = (J_S_x(j,i)-J_S_x(j,i-1))/dx;
    end
    if j == 1
        J_ghost = -J_S_y(j,i);
        grad_J_y(j,i) = (J_S_y(j,i)-J_ghost)/dy;
    elseif j == ny
        J_ghost = -J_S_y(j-1,i);
        grad_J_y(j,i) = (J_ghost-J_S_y(j-1,i))/dy;
    else
        grad_J_y(j,i) = (J_S_y(j,i)-J_S_y(j-1,i))/dy;
    end
    end
    end
 div_J = grad_J_y+grad_J_x;    
dSdt = -div_J;
dSdt(:,nx) = 0.0;
end