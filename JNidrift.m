function J_Ni_drift = JNidrift(lattice_velocity,CNi)
[ny,nx]=size(CNi);
for i=1:nx-1
    J_Ni_drift(i)=lattice_velocity(i)*(CNi(i)+CNi(i+1))/2;
end
end