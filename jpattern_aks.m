function JP = jpattern_aks(nx, ny)
N = nx * ny;
% --- 2D 场自耦合：5 点模板 ---
e2D = ones(N, 1);
B2D = double(spdiags([e2D e2D e2D e2D e2D], [-ny, -1, 0, 1, ny], N, N) ~= 0);
% --- 1D 场自耦合：三对角 ---
e1D = ones(ny, 1);
B1D = double(spdiags([e1D e1D e1D], -1:1, ny, ny) ~= 0);

% --- 1D -> 2D 的耦合 (N × ny)：必须整行声明，不能只声明 GB 列 ---
% rhs_aks.m 里
%     lattice_velocity_x = lattice_velocity_x + (J_r_Cr+J_r_Fe+J_r_Ni+J_r_Si);
% 是 ny×(nx-1) 加 ny×1 的【隐式广播】：节点 j 的界面反应速率 q(j) 被加到 j 行
% 的每一个 x 面上。经 Jdrift 传播后，任意列 i 的 d(2D 场)/dt 都依赖节点 j 的
% CO 与 4 个氧化物厚度，而不只是 GB 列 i=1。
% 旧版这里写的是 [speye(ny); sparse(N-ny,ny)]（只有 i=1），把大量真实非零声明
% 成了结构零。numjac 按声明的模式做列分组并成组扰动（numjac.m:159 colgroup），
% 未声明的条目不仅算不出来，其差分贡献还会被摊到同组已声明的条目上 —— Jacobian
% 既缺项又被污染，ode15s 的简化 Newton 因此收敛不良、反复重分解并砍步长。
row_all = repmat(speye(ny), nx, 1);              % (j,i) 行 -> 1D 变量 j，对所有 i

% --- 2D -> 1D 的耦合 (ny × N)：保持只声明 GB 列 ---
% d(O)/dt 与 d(氧化物)/dt 只经 solve_node 依赖 i=1 列的金属，声明宽了只会增加
% numjac 对 2D 列的分组数（更多次 RHS 求值），不会更正确。
col_gb  = [speye(ny), sparse(ny, N - ny)];       % 1D 变量 j -> (j,1) 列

% --- 四块拼装 ---
% 2D-2D: 6×6 全耦合 (V, I, Cr, Fe, Ni, Si)，每块 N×N
JP_22 = kron(ones(6, 6), B2D);                   % 6N  × 6N
% 1D-1D: 5×5 全耦合 (O + 4 氧化物)，每块 ny×ny
JP_11 = kron(ones(5, 5), B1D);                   % 5ny × 5ny
% 2D-1D / 1D-2D: 不再互为转置，两个方向的物理依赖本来就不对称
JP_21 = kron(ones(6, 5), row_all);               % 6N  × 5ny   ∂(2D)/∂(1D)
JP_12 = kron(ones(5, 6), col_gb);                % 5ny × 6N    ∂(1D)/∂(2D)
% 拼总
JP = [JP_22, JP_21;
      JP_12, JP_11];
end
