function J_Cr_drift = JCrdrift(lattice_velocity,CCr)
[ny,nx]=size(CCr);
for i=1:nx-1
    J_Cr_drift(i)=lattice_velocity(i)*(CCr(i)+CCr(i+1))/2;
end
end