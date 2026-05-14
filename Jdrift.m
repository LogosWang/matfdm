function [J_drift_x,J_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,C)
[ny,nx]=size(C);
J_drift_x = zeros(ny,   nx-1);     % ← 加上
J_drift_y = zeros(ny-1, nx); 
for i=1:nx-1
    for j = 1:ny
    J_drift_x(j,i)=lattice_velocity_x(j,i)*(C(j,i)+C(j,i+1))/2;
    end
end
for i=1:nx
    for j = 1:ny-1
        J_drift_y(j,i)=lattice_velocity_y(j,i)*(C(j,i)+C(j+1,i))/2;
    end
end
end