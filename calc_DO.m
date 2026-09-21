function DO = calc_DO(CCr2O3,CFe3O4,CFeCr2O4,CSiO2,...
                      DO0,slab,DCr2O3,DFe3O4,DFeCr2O4,DSiO2)
% 局部混合的有效 O 扩散系数: 在通道半宽 L = chan_width(S, slab) 上按体积分数
% 并联混合。S < slab 时剩余 (slab - S) 算作空通道 (DO0); S > slab 时 L = S,
% 就是纯氧化物的体积分数平均。
S = CCr2O3 + CFe3O4 + CFeCr2O4 + CSiO2;
L = chan_width(S, slab);

numerator = ...
      CCr2O3    .* (DCr2O3   - DO0) ...
    + CFe3O4    .* (DFe3O4   - DO0) ...
    + CFeCr2O4  .* (DFeCr2O4 - DO0) ...
    + CSiO2     .* (DSiO2    - DO0);

DO = DO0 + numerator ./ L;

end
