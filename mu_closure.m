function [mu, Jr, u, q, ok, it] = mu_closure(CO_bar, D, L, aCr, aSi, aMag, aSpin, p, mu0)
% 侧向闭合 (gb_channel_closure_derivation.pdf 式 (24)): 求基模本征值 mu ∈ (0, pi/2)
%     g(mu) = D*mu^2*CO_bar/L - Q(CO_bar*mu*cot(mu)) = 0,
%     Q(u)  = aCr*Ppos(u) + aSi*Ppos(u) + aMag*Ppos(u-E_mag) + aSpin*Ppos(u-E_spin)
% 然后 Jr = D*mu^2*CO_bar/L, 界面 O 活度 u = CO_bar*mu*cot(mu)。
%
% 输入: CO_bar 截面平均 O; D 有效扩散系数 (nm^2/s); L 通道半宽 (nm);
%       aCr..aSpin = k_i*C_i 速率前因子 (nm/s, 与 solve_node 相同, 与 u 无关);
%       mu0 热启动初值 (可空)。
% 输出: q = [qCr;qSi;qMag;qSpin] (与 solve_node 同序), Jr = sum(q) (= D mu^2 CO/L 到容差内),
%       ok 收敛标志, it 迭代次数。
%
% 性质: g 在 (0,pi/2) 严格单调增 (第一项增, mu*cot(mu) 减而 Q 不减),
%       g(0+) = -Q(CO_bar), g(pi/2) = pi^2/4*D*CO_bar/L - Q(0) >= 0。
%       Q(CO_bar) <= 0 (无 O 或都在门槛之下) 时无根: mu = 0, Jr = 0, u = CO_bar。
% 数值: 牛顿 + 括号二分保底 (磁铁矿门槛拐点由二分兜住); 收敛判据是
%       |g| <= tolMu * (D*mu^2*CO/L + Q(u)), 即两项在根处的相对一致度,
%       这样 Jr = sum(q) 与 D*mu^2*CO/L 的相对偏差 <= tolMu, 且 CO_bar 很小时
%       绝对容差也不会被平凡满足。

epsP = p.epsP;
E2   = p.E_mag;
E3   = p.E_spin;
tol  = getf(p, 'tolMu', 1e-10);
half_pi = pi/2;

% ---- 无根分支: 平均浓度下都不反应 ----
[Qbar, kbar] = Qof(CO_bar);
if ~(CO_bar > 0) || Qbar <= 0
    mu = 0;  Jr = 0;  u = CO_bar;  q = zeros(4,1);  ok = true;  it = 0;
    return
end

gD = D * CO_bar / L;                              % D*CO/L

% ---- 初值: 线性化 Da = k*L/D 的近似闭式 (Da->0: sqrt(Da); Da->inf: pi/2) ----
if nargin < 9 || isempty(mu0) || ~isfinite(mu0) || mu0 <= 0 || mu0 >= half_pi
    Da = kbar * L / D;
    mu = sqrt(Da / (1 + Da / half_pi^2));
end
if nargin >= 9 && ~isempty(mu0) && isfinite(mu0) && mu0 > 0 && mu0 < half_pi
    mu = mu0;
end
a = 0;  b = half_pi;
mu = min(max(mu, 1e-8), half_pi - 1e-8);

% ---- 牛顿 + 二分 ----
ok = false;
for it = 1:80
    [g, dg, ~, ~, gsum] = res(mu);
    if abs(g) <= tol * gsum, ok = true; break; end
    if g > 0, b = mu; else, a = mu; end          % g 单调增 => 括号收缩
    mn = mu - g / dg;
    if ~isfinite(mn) || mn <= a || mn >= b
        mn = 0.5 * (a + b);                       % 出括号 => 二分
    end
    mu = mn;
    if b - a < 1e-15, ok = true; break; end
end

[~, ~, u, q] = res(mu);
Jr = sum(q);

% ---------------------------------------------------------------------
    function [g, dg, u, qv, gsum] = res(m)
        [mc, dmc] = mucot(m);
        u  = CO_bar * mc;
        [P1, d1] = PposD(u,      epsP);
        [P2, d2] = PposD(u - E2, epsP);
        [P3, d3] = PposD(u - E3, epsP);
        qv = [aCr*P1; aSi*P1; aMag*P2; aSpin*P3];
        Q  = sum(qv);
        dQ = (aCr + aSi)*d1 + aMag*d2 + aSpin*d3;   % dQ/du
        g    = gD * m^2 - Q;
        gsum = gD * m^2 + abs(Q);                   % 收敛尺度
        dg   = 2 * gD * m - dQ * CO_bar * dmc;
    end

    function [Q, dQ] = Qof(v)                     % Q(v), dQ/dv 在 v 处
        [P1, d1] = PposD(v,      epsP);
        [P2, d2] = PposD(v - E2, epsP);
        [P3, d3] = PposD(v - E3, epsP);
        Q  = (aCr + aSi)*P1 + aMag*P2 + aSpin*P3;
        dQ = (aCr + aSi)*d1 + aMag*d2 + aSpin*d3;
    end
end

function [y, dy] = mucot(m)                       % mu*cot(mu) 及导数, 小 mu 用级数
if m < 1e-4
    y  = 1 - m^2/3 - m^4/45;
    dy = -2*m/3 - 4*m^3/45;
else
    s  = sin(m);  c = cos(m);
    y  = m * c / s;
    dy = (s*c - m) / s^2;
end
end

function [y, dy] = PposD(x, epsP)                 % 平滑正部及其导数 (同 solve_node)
r  = sqrt(x.^2 + epsP^2);
y  = 0.5*(x + r) - 0.5*epsP;
dy = 0.5*(1 + x./r);
end

function v = getf(p, name, dflt)
if isfield(p, name) && ~isempty(p.(name)), v = p.(name); else, v = dflt; end
end
