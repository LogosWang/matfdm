function [q, uu, ok] = solve_node(CO_gb, CCr, CFe_m, CNi_m, CSi, ...
                                  LCr2O3, LSiO2, Lmag, Lspin, p, uu0)
% 单层氧化物界面代数: 唯一未知量 u = 金属/氧化物界面处 O 活度。
%   膜内输运  J = g*(CO_gb - u),  g = D_mix/L
%   L     = 四种氧化物总厚 + Lmin 正则化
%   D_mix = calc_DO 对层内成分的混合 (与面内 EMT 同一混合律)
%   全部氧化物在金属/氧化物界面生长, 消耗全部记在 u 处:
%       g*(CO_gb - u) = qCr + qSi + qMag + qSpin
% 性质: F(u) = g*(CO_gb-u) - Q(u) 严格单调减, 根唯一且被 [a,b] 括住,
%       牛顿步 + 出界二分保底, 不会发散。
% 兼容: q 顺序不变 [qCr;qSi;qMag;qSpin]; uu 仍返回 4 元 [u;u;CFe_m;CNi_m]
%       (供给直接取金属场; uu(2) 仍是界面 O, rhs 零改动读法; CNi_m 仅占位未参与)
 
% ---- 单层电导 ----
L = LCr2O3 + LSiO2 + Lmag + Lspin + p.Lmin;
D = calc_DO(LCr2O3, Lmag, Lspin, LSiO2, ...
            p.DO0, p.slab, p.DCr2O3, p.DFe3O4, p.DFeCr2O4, p.DSiO2);
g = D / L;
 
% ---- 供给与速率系数 (u 无关, 提出循环) ----
S     = CCr*CFe_m / (CCr + 2*CFe_m + p.epsC);   % FeCr2O4: Fe-Cr 共消耗 (1 Fe : 2 Cr)
aCr   = p.kCr * CCr;
aSi   = p.kSi * CSi;
aMag  = p.kFe * CFe_m;
aSpin = p.kspin * S;
 
% ---- 括根区间 [a,b]: F(a)>=0, F(b)<=0 严格成立 ----
a = 0;
b = CO_gb + 0.5*p.epsP*(aCr + aSi + aMag + aSpin)/g;   % Ppos>=-eps/2 的严格上界
 
% ---- 初值: 热启动取上次界面 O, 冷启动 = "膜不挡"极限 u = CO_gb ----
if nargin < 11 || isempty(uu0) || any(~isfinite(uu0))
    u = CO_gb;
else
    u = min(max(uu0(2), a), b);
end
 
% ---- 牛顿 + 二分保底 ----
ok = false;
for it = 1:60
    [F, dF] = res(u);
    if abs(F) < p.tolNode, ok = true; break; end
    if F > 0, a = u; else, b = u; end          % F 单调减 => 括号收缩
    un = u - F/dF;                             % 牛顿步
    if ~isfinite(un) || un <= a || un >= b
        un = 0.5*(a + b);                      % 出括号 => 二分
    end
    u = un;
end
 
[~, ~, q] = res(u);                            % 收敛解代回 => 输出速率
uu = [u; u; CFe_m; CNi_m];
 
% ---- 残差: 单条守恒, 物理全部在此 ----
    function [F, dF, qv] = res(v)
        [P1, d1] = PposD(v,            p.epsP);   % E_Cr = E_Si = 0
        [P2, d2] = PposD(v - p.E_mag,  p.epsP);
        [P3, d3] = PposD(v - p.E_spin, p.epsP);
        qCr   = aCr   * P1;
        qSi   = aSi   * P1;
        qMag  = aMag  * P2;
        qSpin = aSpin * P3;
        F  = g*(CO_gb - v) - (qCr + qSi + qMag + qSpin);
        dF = -g - ((aCr + aSi)*d1 + aMag*d2 + aSpin*d3);
        qv = [qCr; qSi; qMag; qSpin];
    end
end
 
function [y, dy] = PposD(x, epsP)              % 平滑正部及其导数
r  = sqrt(x.^2 + epsP^2);
y  = 0.5*(x + r) - 0.5*epsP;
dy = 0.5*(1 + x./r);
end