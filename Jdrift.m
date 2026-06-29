function [J_drift_x,J_drift_y] = Jdrift(lattice_velocity_x,lattice_velocity_y,C)
[ny,nx]=size(C);
J_drift_x = zeros(ny,   nx-1);     % ← 加上
J_drift_y = zeros(ny-1, nx); 
for i = 1:nx-1
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

% for i = 1:nx-1
%     for j = 1:ny
%         J_drift_x(j, i) = lattice_velocity_x(j, i) * (C(j, i) + C(j, i+1)) / 2;
%     end
% end
% for i = 1:nx
%     for j = 1:ny-1
%         J_drift_y(j, i) = lattice_velocity_y(j, i) * (C(j, i) + C(j+1, i)) / 2;
%     end
% end


% v0 = 1e-5; 
% 
% % 2. 最大迎风权重 (0.0 = 纯中心, 1.0 = 纯迎风)
% % 这个参数最关键！纯迎风是 1.0，会导致 Ni 变成负数。
% % 我们只需要一点点迎风权重来压制数值震荡，建议从 0.1 到 0.2 开始尝试。
% max_upwind_weight = 0.7; 
% 
% %% --- X 方向漂移计算 ---
% for i = 1:nx-1
%     for j = 1:ny
%         v = lattice_velocity_x(j, i);
% 
%         % 1. 获取纯迎风浓度 (Upwind)
%         if v >= 0
%             C_upwind = C(j, i);          % v 朝 +x → 上游是左格 i
%         else
%             C_upwind = C(j, i+1);        % v 朝 -x → 上游是右格 i+1
%         end
% 
%         % 2. 获取纯中心浓度 (Central)
%         C_central = 0.5 * (C(j, i) + C(j, i+1));
% 
%         % 3. 计算平滑权重 (w)
%         % 当 |v| 远小于 v0 时，w 趋近于 0 (使用中心差分，保留物理)
%         % 当 |v| 远大于 v0 时，w 趋近于 max_upwind_weight (启用部分迎风，压制震荡)
%         w = tanh(abs(v) / v0) * max_upwind_weight;
% 
%         % 4. 混合浓度估算
%         C_face = (1 - w) * C_central + w * C_upwind;
% 
%         % 5. 计算最终通量
%         J_drift_x(j, i) = v * C_face;
%     end
% end
% 
% %% --- Y 方向漂移计算 ---
% for i = 1:nx
%     for j = 1:ny-1
%         v = lattice_velocity_y(j, i);
% 
%         % 1. 获取纯迎风浓度 (Upwind)
%         if v >= 0
%             C_upwind = C(j, i);          % v 朝 +y → 上游是当前 j
%         else
%             C_upwind = C(j+1, i);        % v 朝 -y → 上游是 j+1
%         end
% 
%         % 2. 获取纯中心浓度 (Central)
%         C_central = 0.5 * (C(j, i) + C(j+1, i));
% 
%         % 3. 计算平滑权重 (w)
%         w = tanh(abs(v) / v0) * max_upwind_weight;
% 
%         % 4. 混合浓度估算
%         C_face = (1 - w) * C_central + w * C_upwind;
% 
%         % 5. 计算最终通量
%         J_drift_y(j, i) = v * C_face;
%     end
% end
end