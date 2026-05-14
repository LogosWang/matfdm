function [J_V_x,J_V_y] = JV(J_Cr_V_x,J_Cr_V_y, J_Fe_V_x, J_Fe_V_y, J_Ni_V_x, J_Ni_V_y, J_Si_V_x, J_Si_V_y)
J_V_x = -(J_Cr_V_x+J_Fe_V_x+J_Ni_V_x+J_Si_V_x);
J_V_y = -(J_Cr_V_y+J_Fe_V_y+J_Ni_V_y+J_Si_V_y);
end