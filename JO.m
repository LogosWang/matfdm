function J_O = JO(CO, D_n, L_n, dy)
% 沿 GB 的截面积分 O 通量 (式 (13)):  J_O = -(D_eff*L) dC̄/dy
%   D_n, L_n: 节点的有效扩散系数与通道半宽 (ny×1), 由 rhs 用 calc_DO / chan_width 算好。
%   面电导 G = D*L 取两节点调和平均 (与原先对 D 的处理一致)。
%   旧闭合 (p.closure='node') 传 L_n = slab 常数, 结果与原来的 -D_f dC/dy 只差常数因子
%   slab, 在 dOdt 里再除回去, 逐位等价。
G_n = D_n(:) .* L_n(:);                                   % ny×1
Gl  = G_n(1:end-1);   Gr = G_n(2:end);
Gf  = 2*Gl.*Gr ./ (Gl + Gr + 1e-300);                     % (ny-1)×1 面值
J_O = -Gf .* diff(CO(:,1)) / dy;
end
