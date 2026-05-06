function J_Fe_drift = JFedrift(lattice_velocity,CFe)
[ny,nx]=size(CFe);
for i=1:nx-1
    J_Fe_drift(i)=lattice_velocity(i)*(CFe(i)+CFe(i+1))/2;
end
end