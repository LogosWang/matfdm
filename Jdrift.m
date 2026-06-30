function [J_drift_x, J_drift_y] = Jdrift(vx, vy, C)
% x 方向
C_left  = C(:, 1:end-1);
C_right = C(:, 2:end);
J_drift_x = vx .* ((vx >= 0).*C_left + (vx < 0).*C_right);

% y 方向
C_up   = C(1:end-1, :);
C_down = C(2:end, :);
J_drift_y = vy .* ((vy >= 0).*C_up + (vy < 0).*C_down);
end