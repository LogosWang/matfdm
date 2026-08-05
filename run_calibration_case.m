function run_calibration_case(case_tag, dose, mult)
% Run one isolated decoupled calibration leg.
% mult order: [kCr kFe kSi kspin DCr2O3O DFe3O4 DFeCr2O4 DSiO2 kRobin E_mag].
arguments
    case_tag (1,1) string
    dose (1,1) double
    mult (1,10) double = ones(1,10)
end

p = build_p_decouple(dose);
base = [p.kCr p.kFe p.kSi p.kspin p.DCr2O3O p.DFe3O4 ...
        p.DFeCr2O4 p.DSiO2 p.kRobin p.E_mag];
vals = base .* mult;
p.kCr = vals(1); p.kFe = vals(2); p.kSi = vals(3); p.kspin = vals(4);
p.DCr2O3O = vals(5); p.DCr2O3 = p.DCr2O3O;
p.DFe3O4 = vals(6); p.DFeCr2O4 = vals(7); p.DSiO2 = vals(8);
p.kRobin = vals(9); p.E_mag = vals(10); p.case_tag = case_tag;

fprintf('[case] %s dose=%g\n', case_tag, dose);
fprintf('[base] kCr=%.9g kFe=%.9g kSi=%.9g kspin=%.9g ', base(1:4));
fprintf('DCr2O3O=%.9g DFe3O4=%.9g DFeCr2O4=%.9g DSiO2=%.9g kRobin=%.9g E_mag=%.9g\n', base(5:10));
fprintf('[params] kCr=%.9g kFe=%.9g kSi=%.9g kspin=%.9g ', vals(1:4));
fprintf('DCr2O3O=%.9g DFe3O4=%.9g DFeCr2O4=%.9g DSiO2=%.9g kRobin=%.9g E_mag=%.9g\n', vals(5:10));
run_ckpt_decouple(p);
end
