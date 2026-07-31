function dO = dOdt(CO, J_O, Q_O, dy, slab, J_surf)
% Q_O(j) = 节点 j 的总 O 消耗 = sum(q_all(j,:))  （守恒恒等式见 §4.2）
% J_surf = 口部 Robin 面通量 (+y 入通道为正)。顶点中心网格: 节点 1 与 ny 为半控制体。
[ny, ~] = size(CO);
dO = zeros(ny, 1);
for i = 1:ny
    if i == 1
        grad = (J_O(i) - J_surf) / (dy/2);     % 半控制体: 上面 = Robin 面, 下面 = J_O(1)
    elseif i == ny
        grad = (-J_O(i-1) - J_O(i-1)) / dy;
    else
        grad = (J_O(i) - J_O(i-1)) / dy;
    end
    dO(i) = -grad - Q_O(i)/slab;
end
end
