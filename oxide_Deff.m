function D = oxide_Deff(fCr2O3, fFe3O4, fFeCr2O4, fSiO2, p)
% 一层氧化物的局部有效 O 扩散系数 Deff(x), f_k = 该层内各氧化物的体积分数 (Σf = 1):
%     Deff = DCr2O3*fCr2O3 + DFe3O4*fFe3O4 + DFeCr2O4*fFeCr2O4 + DSiO2*fSiO2^m
% 前三项按体积分数并联; SiO2 用 Archie 形式 (连通性随分数的 m 次方下降),
% m = p.archie_m (build_p_decouple, 缺省 2; m = 1 即退化为纯并联)。逐元素可向量化。
if isfield(p,'archie_m') && ~isempty(p.archie_m), m = p.archie_m; else, m = 2; end
D = p.DCr2O3*fCr2O3 + p.DFe3O4*fFe3O4 + p.DFeCr2O4*fFeCr2O4 + p.DSiO2*fSiO2.^m;
end
