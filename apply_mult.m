function [p, vals] = apply_mult(p, mult)
%APPLY_MULT  把 CMA 的十个乘子施加到基线上, 并处理两处绑定。
%
%   标定 (run_calibration_case) 和验证 (run_verify_case) 都调这里, 免得两边
%   各写一份、改了一处忘了另一处。
%
%   顺序: [kCr kFe kSi kspin DCr2O3O DFe3O4 DFeCr2O4 DSiO2 kRobin E_mag]
%   绑定: DCr2O3 跟随 DCr2O3O; DO0 (O 通道基底) 跟随 DSiO2 —— 后者的意思是
%         O 通道基底就是非晶 SiO2, 所以它随 mult(8) 一起被 CMA 调。

base = [p.kCr p.kFe p.kSi p.kspin p.DCr2O3O p.DFe3O4 ...
        p.DFeCr2O4 p.DSiO2 p.kRobin p.E_mag];
vals = base .* mult(:)';

p.kCr = vals(1);  p.kFe = vals(2);  p.kSi = vals(3);  p.kspin = vals(4);
p.DCr2O3O = vals(5);  p.DCr2O3 = p.DCr2O3O;
p.DFe3O4  = vals(6);  p.DFeCr2O4 = vals(7);  p.DSiO2 = vals(8);
p.DO0 = p.DSiO2;
p.kRobin = vals(9);  p.E_mag = vals(10);
end
