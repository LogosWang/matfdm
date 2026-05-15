function JP = jpattern_aks(nx, ny)
N = nx * ny;

% --- 2D 场自耦合：5 点模板 ---
e2D = ones(N, 1);
B2D = double(spdiags([e2D e2D e2D e2D e2D], [-ny, -1, 0, 1, ny], N, N) ~= 0);

% --- 1D 场自耦合：三对角 ---
e1D = ones(ny, 1);
B1D = double(spdiags([e1D e1D e1D], -1:1, ny, ny) ~= 0);

% --- GB 列与 1D 场的耦合矩阵（N × ny）---
% 2D 场线性索引 1..ny 对应 (y=1..ny, x=1) = GB 列
% 1D 场 at j 与 2D 场 at GB(y=j) 双向耦合 → 单位对角块
GB_to_1D = [speye(ny); sparse(N - ny, ny)];     % N × ny

% --- 四块拼装 ---
% 2D-2D: 6×6 全耦合，每块 N×N
JP_22 = kron(ones(6, 6), B2D);                  % 6N × 6N

% 1D-1D: 4×4 全耦合，每块 ny×ny  
JP_11 = kron(ones(4, 4), B1D);                  % 4ny × 4ny

% 2D-1D: 6×4 块，每块 N×ny，1D(j) ↔ 2D 的 (j, x=1)
JP_21 = kron(ones(6, 4), GB_to_1D);             % 6N × 4ny

% 1D-2D: 转置
JP_12 = JP_21';                                  % 4ny × 6N

% 拼总
JP = [JP_22, JP_21;
      JP_12, JP_11];

end