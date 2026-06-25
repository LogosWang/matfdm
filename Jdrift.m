function [J_drift_x,J_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,C)
[ny,nx]=size(C);
J_drift_x = zeros(ny,   nx-1);     % ← 加上
J_drift_y = zeros(ny-1, nx); for i = 1:nx-1
    for j = 1:ny
        v = lattice_velocity_x(j, i);
        if v >= 0
            C_face = C(j, i);          % v 朝 +x → 上风是当前格 i
        else
            C_face = C(j, i+1);        % v 朝 -x → 上风是右邻 i+1
        end
        J_drift_x(j, i) = v * C_face;
    end
end
for i=1:nx
    for j = 1:ny-1
        v = lattice_velocity_y(j, i);
    if v >= 0
        C_face = C(j, i);          % v 朝 +y 走 → 上风是当前 j
    else
        C_face = C(j+1, i);        % v 朝 -y 走 → 上风是 j+1
    end
        J_drift_y(j, i) = v * C_face;
    end
end
end