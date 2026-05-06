function J_V_drift = JVdrift(lattice_velocity,V)
[ny,nx]=size(V);
for i=1:nx-1
    J_V_drift(i)=lattice_velocity(i)*(V(i)+V(i+1))/2;
end
end