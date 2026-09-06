clearvars; clear rhs_aks;
 
p = build_p_decouple(3.0);
p.num_ckpt = 3;
run_onlyRIS(p); 