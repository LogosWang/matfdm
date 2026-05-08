function J_V = JV(J_CrCr_V,J_FeFe_V,J_NiNi_V,J_SiSi_V)
J_V = -(J_CrCr_V+J_FeFe_V+J_NiNi_V+J_SiSi_V);
end