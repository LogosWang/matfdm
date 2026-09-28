function dV_dt = dVdt(J_V_x,J_V_y,dx,dy,I,V,dose_rate,recom_rate,Veq,Ieq,Ks,lattice_velocity,J_gb)
% J_gb (可选, ny×1): GB 面 (x=0, 节点 i=1 左侧) 上 +x 方向的缺陷通量。
%   给出时 i=1 为 Robin 半控制体 (宽 dx/2):  dV/dt = -(J_x(1) - J_gb)/(dx/2) + 源项,
%   rhs 里 J_gb = -k_gb*(V(:,1) - V_eq), 即 J·n = k_gb*(C - C_eq), n 指向 GB (外法向)。
%   省略或为空: 旧行为, i=1 Dirichlet (导数置零)。
robin = nargin >= 13 && ~isempty(J_gb);
[ny,nx]=size(J_V_x);
nx = nx+1;
grad_J_x = zeros(ny,nx);
grad_J_y = zeros(ny,nx);
div_J = zeros(ny,nx);
for i = 1:nx
    for j = 1:ny
    if i == nx
        J_ghost = -J_V_x(j,i-1);
        grad_J_x(j,i) = (-J_V_x(j,i-1)+J_ghost)/dx+V(j,i)*lattice_velocity(j,i-1)/(0.5*dx);
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
if robin
    grad_J_x(:,1) = (J_V_x(:,1) - J_gb(:)) / (0.5*dx);   % Robin 半控制体
end
div_J= grad_J_y+grad_J_x;

    dV_dt = -div_J+dose_rate-recom_rate*(I.*V-Ieq*Veq)+Ks*(Veq-V);
    if ~robin, dV_dt(:,1) = 0.0; end                     % Dirichlet: 边界导数置零

end
