 
clearvars; clear rhs_aks;
 
p = build_p_decouple(0.5);
p.oxi_time = 1500*60*60;
p.num_ckpt = 150;
run_ckpt_decouple(p); 