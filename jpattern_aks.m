function JP = jpattern_aks(nx, ny)
N = nx * ny;
% --- 2D 场自耦合：5 点模板 ---
e2D = ones(N, 1);
B2D = double(spdiags([e2D e2D e2D e2D e2D], [-ny, -1, 0, 1, ny], N, N) ~= 0);
% --- 1D 场自耦合：三对角 ---
e1D = ones(ny, 1);
B1D = double(spdiags([e1D e1D e1D], -1:1, ny, ny) ~= 0);
% --- GB 列与 1D 场的耦合矩阵（N × ny）---
GB_to_1D = [speye(ny); sparse(N - ny, ny)];     % N × ny
% --- 四块拼装 ---
% 2D-2D: 6×6 全耦合 (Fe, Cr, Ni, Si, I, V)，每块 N×N
JP_22 = kron(ones(6, 6), B2D);                  % 6N × 6N
% 1D-1D: 5×5 全耦合 (O + 4 氧化物: Fe3O4, Cr2O3, NiO, SiO2)，每块 ny×ny
JP_11 = kron(ones(5, 5), B1D);                  % 5ny × 5ny   ← 原来 4×4
% 2D-1D: 6×5 块，每块 N×ny
JP_21 = kron(ones(6, 5), GB_to_1D);             % 6N × 5ny    ← 原来 6×4
% 1D-2D: 转置
JP_12 = JP_21';                                  % 5ny × 6N
% 拼总
JP = [JP_22, JP_21;
      JP_12, JP_11];
end