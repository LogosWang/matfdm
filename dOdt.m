function dO = dOdt(CO, J_O, Q_O, dy, slab)
% Q_O(j) = 节点 j 的总 O 消耗 = sum(q_all(j,:))  （守恒恒等式见 §4.2）
[ny, ~] = size(CO);
dO = zeros(ny, 1);
for i = 1:ny
    if i == 1
        grad = 0.0;
    elseif i == ny
        grad = (-J_O(i-1) - J_O(i-1)) / dy;
    else
        grad = (J_O(i) - J_O(i-1)) / dy;
    end
    dO(i) = -grad - Q_O(i)/slab;
end
dO(1) = 0.0;
end