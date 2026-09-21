function [q, uu, ok, mu, Jr, L, D] = solve_mu(CO_bar, CCr, CFe_m, CNi_m, CSi, ...
                                             LCr2O3, LSiO2, Lmag, Lspin, p, mu0)
% 界面代数, Laplace 基模闭合版 (替代 solve_node)。签名前 10 个参数与 solve_node
% 一致, 返回的 q / uu / ok 也同义, rhs_aks 里可以直接切换:
%   q  = [qCr;qSi;qMag;qSpin]   (O 场单位 × nm/s, 与 solve_node 同)
%   uu = [u;u;CFe_m;CNi_m]      (uu(2) = 界面 O 活度 C_int = CO_bar*mu*cot(mu))
% 额外返回 mu, Jr = sum(q), 通道半宽 L 与有效扩散系数 D (rhs 算稀释与沿 GB 电导可复用)。
%
% 与 solve_node 的区别:
%   solve_node: 膜电导 g = D/(ΣL_k + Lmin), 解 g*(CO_gb - u) = Q(u), 未知量 u
%   solve_mu  : 通道半宽 L = chan_width(ΣL_k, slab) (>= slab, 无需 Lmin),
%               解 D*mu^2*CO_bar/L = Q(CO_bar*mu*cot(mu)), 未知量 mu

S = LCr2O3 + LSiO2 + Lmag + Lspin;
L = chan_width(S, p.slab);
D = calc_DO(LCr2O3, Lmag, Lspin, LSiO2, ...
            p.DO0, p.slab, p.DCr2O3, p.DFe3O4, p.DFeCr2O4, p.DSiO2);

% ---- 速率前因子 (与 solve_node 完全相同) ----
Sfc   = CCr*CFe_m / (CCr + 2*CFe_m + p.epsC);   % FeCr2O4: Fe-Cr 共消耗 (1 Fe : 2 Cr)
aCr   = p.kCr   * CCr;
aSi   = p.kSi   * CSi;
aMag  = p.kFe   * CFe_m;
aSpin = p.kspin * Sfc;

if nargin < 11, mu0 = []; end
[mu, Jr, u, q, ok] = mu_closure(CO_bar, D, L, aCr, aSi, aMag, aSpin, p, mu0);
uu = [u; u; CFe_m; CNi_m];
end
