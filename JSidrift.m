function J_Si_drift = JSidrift(lattice_velocity,CSi)
[ny,nx]=size(CSi);
for i=1:nx-1
    J_Si_drift(i)=lattice_velocity(i)*(CSi(i)+CSi(i+1))/2;
end
end