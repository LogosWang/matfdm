function JP = jpattern_aks(nx)
e = ones(nx, 1);
B = spdiags([e e e], -1:1, nx, nx);   % 三对角
coupling = ones(4, 4);                % 4 场两两耦合
JP = kron(coupling, B);               % 4nx × 4nx 的 0/1 稀疏矩阵
end