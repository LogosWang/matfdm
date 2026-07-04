function [q, uu, ok] = solve_node(CO_gb, CCr, CFe_m, CNi_m, CSi, ...
                                  LCr2O3, Lmag, Ltrev, p, uu0)
% ---- 电导: Eq.1-3 的 g, L+Lmin 正则化 (§2) ----
Lin  = LCr2O3 + p.Lmin;
Lout = Lmag + Ltrev + p.Lmin;
g_out = p.DOout    / Lout;
g_in  = p.DCr2O3O  / Lin;
g_Fe  = p.DCr2O3Fe / Lin;
g_Ni  = p.DCr2O3Ni / Lin;

% ---- 初值: §9(c). 冷启动 = "膜不挡"极限 P3 ----
if nargin < 10 || isempty(uu0) || any(~isfinite(uu0))
    uu = [CO_gb; CO_gb; CFe_m; CNi_m];
else
    uu = uu0;                                  % 热启动: 上次 rhs 调用的解
end

% ---- 阻尼牛顿主循环: §8-9, Eq.15 ----
ok = false;
for it = 1:30
    R = res(uu);                               % 残差 = Eq.11-14 移项
    nR = norm(R, inf);
    if nR < p.tolNode, ok = true; break; end   % 四条守恒同时满足 => 收敛
    J = zeros(4);                              % 数值 Jacobian (§8)
    h = 1e-7 * max(abs(uu), 1e-6);
    for c = 1:4
        up = uu; up(c) = up(c) + h(c);
        J(:,c) = (res(up) - R) / h(c);         % 第 c 列 = dR/du_c
    end
    d = - J \ R;                               % 牛顿方向: 解 J d = -R
    if any(~isfinite(d)), break; end
    lam = 1.0;                                 % 回溯线搜索 (§9a)
    for ls = 1:6
        uun = max(uu + lam*d, 0);              % 非负投影 (§9b)
        if norm(res(uun), inf) <= (1 - 0.25*lam)*nR + p.tolNode
            uu = uun; break                    % Armijo 判据: 残差充分下降才接受
        end
        lam = lam/2;
        if ls == 6, uu = max(uu + lam*d, 0); end
    end
end
[~, q] = res(uu);                              % 收敛解代回 Eq.6-9 => 输出速率

% ---- 残差函数: 模型物理全部在此 ----
    function [R, qv] = res(v)
        u1 = v(1); u2 = v(2); f = v(3); n = v(4);
        % 混合闭合 (Eq.7-10): 共享物种(O,Fe)一级, 私有共消耗走调和 S — 见 §3.1 R1/R2
        qCr  = p.kCr * CCr * Ppos(u1,           p.epsP);   % Eq.7  (E_Cr=0)
        qSi  = p.kSi * CSi * Ppos(u1,           p.epsP);   % Eq.8  (E_Si=0)
        qMag = p.kFe * f   * Ppos(u2 - p.E_mag, p.epsP);   % Eq.9  供给是 f 不是 C_Fe,m
        S    = f*n / (f + 2*n + p.epsC);                   % Eq.10 的 S, epsC 防 0/0
        qTr  = p.kNi * S   * Ppos(u2 - p.E_trev, p.epsP);  % Eq.10
        R = [ g_out*(CO_gb - u2) - (qMag + qTr) - g_in*(u2 - u1);  % Eq.11
              g_in *(u2 - u1)    - (qCr + qSi);                    % Eq.12
              g_Fe *(CFe_m - f)  - (0.75*qMag + 0.5*qTr);          % Eq.13
              g_Ni *(CNi_m - n)  - 0.25*qTr ];                     % Eq.14
        qv = [qCr; qSi; qMag; qTr];
    end
end

function y = Ppos(x, epsP)                     % 平滑正部 (§7): (x)+ 的磨圆版
y = 0.5*(x + sqrt(x.^2 + epsP^2)) - 0.5*epsP; 
end