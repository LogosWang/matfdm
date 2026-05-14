function JP = jpattern_aks(nx, ny)
N = nx * ny;
e = ones(N, 1);

% 5 点模板：自己 + y±1（偏移 ±1）+ x±1（偏移 ±ny）
B = spdiags([e e e e e], [-ny, -1, 0, 1, ny], N, N);
B = double(B ~= 0);             % 0/1 稀疏模式

coupling = ones(6, 6);          % 6 场两两耦合
JP = kron(coupling, B);         % (6N) × (6N) 的 0/1 稀疏矩阵
end