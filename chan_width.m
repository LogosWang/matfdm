function [L, dLdS] = chan_width(S, slab)
% 通道半宽 L = 对称轴到氧化物/金属界面的距离, 及其对氧化物总厚 S 的导数。
%   模型域是镜像的一半: 空 GB 全宽 2*slab, 模型里只有 slab (=1 nm) 这一侧;
%   S = 单侧氧化物总厚 ΣL_k。氧化物没填满原 GB 通道前 L = slab, 填满后 L = S。
%   用 calc_DO 里原来的光滑 max(slab, S) (eps_s = 1e-2*slab) 抹平拐点, 这样
%   D_eff (体积分数混合的分母) 与 L (储存宽度 / 沿 GB 电导 / 闭合的半宽) 用的
%   是同一个宽度。dLdS 给 rhs 算稀释项 dL/dt = dLdS * dS/dt 用。
eps_s = 1e-2 * slab;
r     = sqrt((slab - S).^2 + eps_s.^2);
L     = 0.5 .* (slab + S + r);
dLdS  = 0.5 .* (1 + (S - slab) ./ r);
end
