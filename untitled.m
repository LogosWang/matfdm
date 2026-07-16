a=0.18;
b=0.02;
k=0.9;
x1=a;
x2 = b;
X1=zeros(1000,1)
X2=zeros(1000,1)
for i=1:1000
    x1=(1-k)*x1+a;
    x2=(1-k)*x2+b;
    X1(i,1) = x1;
    X2(i,1) = x2;

end
figure
plot(X1,'DisplayName', 'X1');
hold on;
plot(X2, 'DisplayName', 'X2');
xlabel('Iteration');
ylabel('Value');
title('Dynamics of X1 and X2');
legend show;
hold off;
    
