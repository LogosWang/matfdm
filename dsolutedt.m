function dSdt = dsolutedt(J_S_x, J_S_y, dx, dy, J_r)
[ny, nx_face] = size(J_S_x);
nx = nx_face + 1;

% x 散度
grad_J_x = zeros(ny, nx);
grad_J_x(:, 2:nx-1) = (J_S_x(:, 2:end) - J_S_x(:, 1:end-1)) / dx;
grad_J_x(:, 1)  = 2*J_S_x(:, 1)/dx - J_r/(0.5*dx);   % i=1 镜像 + 反应
grad_J_x(:, nx) = 0;                                  % i=nx Dirichlet

% y 散度
grad_J_y = zeros(ny, nx);
grad_J_y(2:ny-1, :) = (J_S_y(2:end, :) - J_S_y(1:end-1, :)) / dy;
grad_J_y(1,  :) = 2*J_S_y(1,  :)/dy;
grad_J_y(ny, :) = -2*J_S_y(end, :)/dy;

dSdt = -(grad_J_x + grad_J_y);
dSdt(:, nx) = 0;
end