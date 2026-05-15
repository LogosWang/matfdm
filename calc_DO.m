function DO = calc_DO(CCr2O3,CNiO,CSiO2,alpha,DO0,DOmax,oxide_character)
r = DOmax/DO0 -1;
DO = DOmax/(1+r*exp((-(CCr2O3+CNiO+CSiO2)+alpha*CCr2O3)/oxide_character));
end