function dO = dOdt(CO, J_O, Jr, L, dLdt, dy, J_surf)
% 截面平均 O 浓度的时间导数, 式 (13) 展开:
%     L dC̄/dt = -d(J_O)/dy - Jr - C̄ dL/dt
%   J_O   : 面上的截面积分通量 -(D L) dC̄/dy, (ny-1)×1
%   Jr    : 节点的界面总消耗 sum(q), 单位 O场×nm/s
%   L     : 节点通道半宽 (nm); dLdt: 其时间导数 (稀释项; 旧闭合传 0)
%   J_surf: 口部 Robin 通量 (单位截面积, +y 入通道为正); 口部入流总量 = J_surf*L(1)
% 顶点中心网格: 节点 1 与 ny 为半控制体 (dy/2); 底端 ny 零通量。
ny = size(CO, 1);
divJ = zeros(ny, 1);
divJ(1)        = (J_O(1) - J_surf*L(1)) / (dy/2);
divJ(2:ny-1)   = (J_O(2:ny-1) - J_O(1:ny-2)) / dy;
divJ(ny)       = (0 - J_O(ny-1)) / (dy/2);
dO = (-divJ - Jr(:) - CO(:,1) .* dLdt(:)) ./ L(:);
end
