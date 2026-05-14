function [J_I_x,J_I_y] = JI(J_Cr_I_x,J_Cr_I_y, J_Fe_I_x, J_Fe_I_y, J_Ni_I_x, J_Ni_I_y, J_Si_I_x, J_Si_I_y)
J_I_x = (J_Cr_I_x+J_Fe_I_x+J_Ni_I_x+J_Si_I_x);
J_I_y = (J_Cr_I_y+J_Fe_I_y+J_Ni_I_y+J_Si_I_y);
end