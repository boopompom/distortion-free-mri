%% Investigate the idea of dynamic single point imaging with regularized reconstruction for inherent distortion free MRI
% Inherent distortion free mri with accelerated single point imaging and regularized reconstruction
% possible names:
% spicy
% spike
% spinach
% spiro

% Assumptions:
% 1) No T1/T2 decay
% 2) Single receiver work
% 3) Initial image = 100% real-valued
clear all;close all;clc;
addpath(genpath(cd))
addpath(genpath('/nfs/rtsan02/userdata/home/tbruijne/Documents/MATLAB/MReconUMC/MReconUMC/MReconUMC_V5/Packages/utils'))
addpath(genpath('/home/tbruijne/Documents/MATLAB/MReconUMC/MReconUMC/MReconUMC_V5/Standalone/Fessler_nufft/'))

woff_fat=220; % Hz
%% Phantom + field generation
N=128;

% Water layer phantom
x_w=phantom(N);

% Fat layer phantom
x_f=zeros(size(x_w));
x_f(x_w==1)=.3; % fat fraction
x_w(x_w==1)=.2;
subplot(331);imshow(x_w,[]);title('Water phantom')
subplot(332);imshow(x_f,[]);title('Fat phantom')

% Add susceptibillity  source
width_sus=2;
dChi=zeros(N,N,N);
dChi(N/2-width_sus:N/2+width_sus,N/2-width_sus:N/2+width_sus,N/2-width_sus:N/2+width_sus)=3*10^-6+.25*10^-6*rand(2*width_sus+1,2*width_sus+1,2*width_sus+1); % Titanium alloy
B0 = 3; % tesla;
voxelSize = [1 1 1]; % mm
gyromagneticRatio = 2*pi*42.58e6;
dB = B0*calculateFieldShift(dChi, voxelSize);
dOhmega = dB*gyromagneticRatio;

w_max=120; % 100 Hz
B0=rot90(w_max*normalise(generate_b0(1,N)),1)+dOhmega(:,:,N/2);

% Calculate derivative of B0 for intravoxel dephasing
der_B0=conv2(B0,[0 -1 0; -1 4 -1; 0 -1 0],'same');

subplot(333);imshow(B0,[]);colormap(gca, jet);title('B0 - susceptibillity');
subplot(334);imshow(der_B0,[]);colormap(gca, jet);title('Derivative B0 ');

%% Sequence settings
SQ.TE=1.4E-03;
SQ.ADC_duration=1E-03;
SQ.ADC_dt=SQ.ADC_duration/(N);
fat_phi=@(tau,woff)(sin((woff_fat+woff).*tau));
water_phi=@(tau,woff)(sin(woff.*tau));

%% Standard Cartesian acquisition
k=zeros(N,N);
for fe=1:N
    t=SQ.TE+(fe-1)*SQ.ADC_dt;
    % Apply phase ramping due to off res + chem shift
    x=exp(-1j*2*pi*fat_phi(t,B0)).*x_f+...
        exp(-1j*2*pi*water_phi(t,B0)).*x_w;
    
    % Apply intravoxel dephasing 
    for xcoord=1:N^2
    spins=t*der_B0(xcoord);
    if spins(end)>1
        x(xcoord)=0;
    else
        x(xcoord)=x(xcoord)*exp(-4.6*abs(spins));
    end
    end
    
    % Sample a complete phase-encode line (say TE)
    X=ifftshift(fft2(fftshift(x)));
    k(fe,:)=X(fe,:);
end

x_recon=ifftshift(ifft2(fftshift(k)));
subplot(335);imshow(abs(x_recon),[]);title('Geometrically distorted')

%% Proposed method
% Assume I take 33 samples across the ADC --> 33 2D images
% Also assume that I take N readouts
nsamples=2*N;
k=zeros(nsamples,N);

% Compute Golden angle radial trajectory with N readouts
% First compute the radial angles
d_angle=pi/((1+sqrt(5))/2);angles=0:d_angle:d_angle*(N-1);

% Now compute all the sample points that I want!
kx=linspace(0,nsamples-1,nsamples)'-(nsamples-1)/2;

% Modulate the phase of all the successive spokes
for l=1:N
    k(:,l)=kx*exp(-1j*angles(l));
end

% Normalise
k=.5*k/max(abs(k(:)));
cp=ceil(nsamples/2);

% For every adc point select the adequate k-pos and store --> Still
% requires a lot of effort
k_ref=size(nsamples,N);

for ns=1:nsamples
    for s_itl=1:N    
        idx=cp+s_itl;
        while idx > nsamples
            idx=idx-cp-1;
        end
        
        proj=s_itl+ns-1;
        while proj>N
            proj=proj-N;
        end
        k_ref(ns,s_itl)=k(idx,proj);
        
        %scatter(real(k(idx,proj)),imag(k(idx,proj)));hold on;pause(1);axis([-.5 .5 -.5 .5])
    end
end

% Estimate density function
%for ns=1:nsamples;dcf(ns,:)=sdc3_MAT(cat(1,real(k(ns,:)),imag(k(ns,:)),zeros(size(k(ns,:)))),25,N,0);end
dcf=sdc3_MAT(cat(1,real(k(:)),imag(k(:)),zeros(size(k(:)))),25,N,0);
%dcf=abs(k);dcf(cp,:)=1/nsamples;

% Precreate Cartesian mesh for interpolation
cxy=linspace(-.5,.5,round(N)+1);cxy(end)=[];
[KX,KY]=meshgrid(cxy,cxy);

% Perform k-space sampling
kdata=zeros(size(k_ref));
for fe=1:nsamples
    % Apply phase ramping due to off res + chem shift
    x=exp(-1j*2*pi*fat_phi(SQ.TE+(fe-1)*SQ.ADC_dt,B0)).*x_f+...
        exp(-1j*2*pi*water_phi(SQ.TE+(fe-1)*SQ.ADC_dt,B0)).*x_w;
    x=x_w;
    % Sample a complete phase-encode line (say TE)
    X=ifftshift(fft2(fftshift(x)));
    
    % Interpolation
    kdata(fe,:)=interp2(KX,KY,X,imag(k(fe,:)),real(k(fe,:)),'spline');
end

% Fourier transform
for ns=1:1
    om=[real(k(:)) imag(k(:))]*2*pi;
    F=nufft_init(om,[N N],[5 5],2*[N N],.5*[N N]);
    recon(:,:,ns)=nufft_adj(matrix_to_vec(dcf(:).*kdata(:)),F)/sqrt(N^2);
end

figure,imshow(abs(recon),[])

