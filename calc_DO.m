function [Dx, Dy] = calc_DO(CCr2O3, CFe3O4, CFeCr2O4, CSiO2, IA, IH, p)
% 通道截面 [0, L] 上的有效 O 扩散系数, 区分方向:
%   x (横穿通道, 侧向闭合 solve_mu/solve_node 用):  串联  Dx = L / ∫ dx/Deff(x)
%   y (沿 GB, JO 的电导 D*L 用):                    并联  Dy = ∫ Deff(x) dx / L
% L = chan_width(S, slab), S = ΣL_k。[0, S] 是氧化物, Deff(x) 由该处那一层的成分给出
% (oxide_Deff, SiO2 为 Archie 形式); [S, L] 是尚未填满的空通道, 取 DO0。
%
% 氧化物各层成分不同 (向内生长, 新层长在 x = S, 生成后冻结), 所以积分不能只由当前
% 总厚算。rhs_aks 把两个积分作为状态量随时间累积:
%   IA = ∫_0^S Deff dx,   IH = ∫_0^S dx/Deff
% 传空 IA/IH 时 (旧状态向量 6N+5ny 的驱动, 或单点调用) 退化为按当前总厚的均匀层:
%   Deff_u = oxide_Deff(C_k/S),  IA = Deff_u*S,  IH = S/Deff_u。
% m = 1 且均匀时 Dy 与旧 calc_DO (体积分数并联) 逐式相同。
S = CCr2O3 + CFe3O4 + CFeCr2O4 + CSiO2;
L = chan_width(S, p.slab);
E = L - S;                                         % 空通道厚 (chan_width 光滑, >= 0)

if isempty(IA) || isempty(IH)
    Sg = max(S, realmin);
    Du = oxide_Deff(CCr2O3./Sg, CFe3O4./Sg, CFeCr2O4./Sg, CSiO2./Sg, p);
    IA = Du .* S;
    IH = S ./ max(Du, realmin);
end

Dy = (IA + p.DO0 .* E) ./ L;
Dx = L ./ (IH + E ./ p.DO0);
end
