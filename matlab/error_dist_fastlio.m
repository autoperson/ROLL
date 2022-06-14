% clc
% clear;
% close all
%% Sometimes the code malfunctions and you will get wierd statistics;
% don't know why so just reboot the MATLAB
% folder = "/mnt/sdb/Datasets/NCLT/datasets/fastlio_noTMM";
folder = "/mnt/sdb/Datasets/NCLT/datasets/fastlio_loc2";
% folder = "/mnt/sdb/Datasets/NCLT/datasets/no_LIO";
% folder = "/mnt/sdb/Datasets/NCLT/datasets/LOAM";

date = "2012-02-02";
% sequence = "HKcampus";
% sequence = "HILTI_Campus1";
% sequence = "HILTI_uzh_tracking_area_run2";
sequence = "120202mapping_after_info_filtering";
% sequence = "120202mapping";
mkdir(sequence);
poseFilePath = "/home/haisenberg/Documents/ROLL/src/FAST_LIO/Log/"+sequence+"/mat_out.txt";
timeLogPath = "/home/haisenberg/Documents/ROLL/src/FAST_LIO/Log/"+sequence+"/time_log.txt";
% poseFilePath = "/home/haisenberg/Documents/ROLL/src/FAST_LIO/Log/mat_out.txt";
gtFilePath = "/mnt/sdb/Datasets/NCLT/datasets/ground_truth/groundtruth_"+date+".csv";

%% log file reading
fID = fopen(poseFilePath);
strPattern = "";
n = 26;
for i=1:n
    strPattern = strPattern+"%f";
end
logData = textscan(fID,strPattern);
matPose =[logData{1},logData{5},logData{6},logData{7},pi/180*logData{2},pi/180*logData{3},pi/180*logData{4}];
biasG = [logData{17},logData{18},logData{19}];
biasA = [logData{20},logData{21},logData{22}];
timePose = (matPose(:,1)-matPose(1,1)); % sec -> sec
lenPose = length(timePose);

fID2 = fopen(timeLogPath);
strPattern = "";
n = 6;
for i=1:n
    strPattern = strPattern+"%f";
end
logData2 = textscan(fID2,strPattern);
timeLog = logData2{1};
timeUpdate = logData2{2}*1000; % ms
timeFeature = logData2{3}*1000; % ms
timeSolve = logData2{4}*1000; % maximum 3 iterations: ms
effPoints = logData2{5};



%% gt reading
% readcsv readmatrix:sth is wrong
fID3 = fopen(gtFilePath);
gtData = textscan(fID3, "%f%s%f%s%f%s%f%s%f%s%f%s%f");
% downsample
downsample = 10;
lenGT = length(gtData{1});
matGT = zeros(floor(lenGT/downsample),7);
%% ROLL uses imu pose, so here convert body pose to imu pose
%% for original fastlio: zero pose from the start
trans_i2b = [-0.11 -0.18 -0.71 0 0 0];
Ti2b = trans2affine(trans_i2b); % right multiply: converts imu frame to body frame of nclt
Tm2o = eye(4); % left multiply: converts map frame to odom frame
tmp = zeros(1,7);
for i=1:floor(lenGT/downsample)
    for j=1:7
        tmp(j) = gtData{2*j-1}(downsample*i);
    end
    Tb2m = trans2affine(tmp(2:7));
    Ti2m = Tb2m*Ti2b;
    if i==1
        Tm2o = inv(Ti2m);
    end
    Ti2o = Tm2o*Ti2m;
    
    % to trans vector
    matGT(i,2:7) = affine2trans(Ti2o);
    matGT(i,1) = tmp(1);
end

%% sync with time
timeGT = (matGT(:,1)-matGT(1,1))/1e+6; % us -> sec

% MDtimeGT = KDTreeSearcher(timeGT);
[idx, D] = rangesearch(timeGT,timePose,0.05);
ateErrorINI = zeros(lenPose,1);
Err = zeros(lenPose,6);
not_found = 0;
idxC = 0;
for i=1:lenPose
    if isempty(idx{i})
        not_found = not_found + 1;
        continue;    
    end
    idxC = idxC + 1;
%     ateError(i) = norm(matPose(i,2:3)-matGT(idx{i}(1),2:3));
    Err(i,:) = matPose(i,2:7)-matGT(idx{i}(1),2:7);
    
    for iE = 1:3 % removing jump
        Err(i,iE+3) = 180/pi*(Err(i,iE+3) - 2*pi*round(Err(i,iE+3)/2/pi));
    end
    deltaT = transError(matGT(idx{i}(1),2:7),matPose(i,2:7));
    ateErrorINI(idxC) = norm(deltaT(1:3,4));

end
ateError = ateErrorINI(1:idxC);

disp("RMSE error: "+norm(ateError)/sqrt(idxC))
disp("max error: "+max(ateError))
disp("Loc rate: "+length(ateError)/(timePose(end)-timePose(1)))
disp("Success ratio: "+100*length(find(ateError < 1.0))/(timeGT(end)-timeGT(1))/10)
disp("<0.1 %: "+ 100*length(find(ateError < 0.1))/idxC)
disp("<0.2 %: "+ 100*length(find(ateError < 0.2))/idxC)
disp("<0.5 %: "+ 100*length(find(ateError < 0.5))/idxC)
disp("<1.0 %: "+ 100*length(find(ateError < 1.0))/idxC)

nonZeroIdx = find(Err(:,1)~=0);
figure(1)
hold on
plot(matPose(:,2),matPose(:,3),'--');
plot(matGT(:,2),matGT(:,3));
% legend("LOAM(M)+TM","LOAM(M)","ROLL","G.T.");
legend("fastlio","G.T.");
xlabel("X (m)");
ylabel("Y (m)");

figure(2)
histogram(ateError);

figure(3)
subplot(3,2,1)
plot(timePose(nonZeroIdx)-timePose(1),Err(nonZeroIdx,1),'r');
xlabel("Time (s)");
ylabel("Error in x (m)");
subplot(3,2,3)
plot(timePose(nonZeroIdx)-timePose(1),Err(nonZeroIdx,2),'r');
xlabel("Time (s)");
ylabel("Error in y (m)");
subplot(3,2,5)
plot(timePose(nonZeroIdx)-timePose(1),Err(nonZeroIdx,3),'r');
xlabel("Time (s)");
ylabel("Error in z (m)");

subplot(3,2,2)
plot(timePose(nonZeroIdx)-timePose(1),Err(nonZeroIdx,4),'r');
xlabel("Time (s)");
ylabel("Error in roll (^{\circ})");
subplot(3,2,4)
plot(timePose(nonZeroIdx)-timePose(1),Err(nonZeroIdx,5),'r');
xlabel("Time (s)");
ylabel("Error in pitch (^{\circ})");
subplot(3,2,6)
plot(timePose(nonZeroIdx)-timePose(1),Err(nonZeroIdx,6),'r');
xlabel("Time (s)");
ylabel("Error in yaw (^{\circ})");
% legend("FAST-LIO2","ROLL");
% 
% figure(4)
% plot(timePose-timePose(1),biasA(:,1));
% hold on
% plot(timePose-timePose(1),biasA(:,2));
% plot(timePose-timePose(1),biasA(:,3));
% legend("X","Y","Z");
% xlabel("Time (s)");
% ylabel("Acceleration bias (m^2/s)");
% saveas(4,sequence+"/AccBias.jpg");
% figure(5)
% plot(timePose-timePose(1),biasG(:,1));
% hold on
% plot(timePose-timePose(1),biasG(:,2));
% plot(timePose-timePose(1),biasG(:,3));
% legend("X","Y","Z");
% xlabel("Time (s)");
% ylabel("Gyroscope bias (rad/s)");
% saveas(5,sequence+"/GyroBias.jpg");

figure(6)
timeLog  = timeLog - timeLog(1);
subplot(2,2,1)
plot(timeLog,timeUpdate);
xlabel("time (s)");
ylabel("time of kalman update (ms)");
hold on
subplot(2,2,2)
plot(timeLog,timeFeature);
xlabel("time (s)");
ylabel("time of feature association (ms)");
hold on
subplot(2,2,3)
plot(timeLog,timeSolve);
xlabel("time (s)");
ylabel("time of eskf iterations (ms)");
hold on
subplot(2,2,4)  
plot(timeLog,effPoints);
xlabel("time (s)");
ylabel("Effective points");
hold on

legend("W.O. info. filtering","W. info. filtering");
function eT = transError(Vgt,V2)
% input: x y z r p y
    T1 = eye(4);
    T2 = eye(4);
    T1(1:3,1:3) = eul2rotm([Vgt(6),Vgt(5),Vgt(4)],"ZYX");
    T2(1:3,1:3) = eul2rotm([V2(6),V2(5),V2(4)],"ZYX");
    T1(1:3,4) = Vgt(1:3)';
    T2(1:3,4) = V2(1:3)';
    eT = T1\T2;    % equals to T1\T2
end

function y = removeJump(x)
    % 2pi
    Ntmp = round(x/360);
    y = x - Ntmp*360;
end

%% v is a 1x6 vector with [x y z roll pitch yaw]
function T = trans2affine(v)
   T = eye(4);
   if length(v) ~= 6
       disp("wrong dimension");
   end
   T(1:3,1:3) = eul2rotm([v(6),v(5),v(4)],"ZYX");
   T(1:3,4) = v(1:3)';
end

%% v is a 1x6 vector with [x y z roll pitch yaw]
function v = affine2trans(T)
   v = zeros(1,6);
   if any(size(T)-4)
       disp("wrong dimension");
   end
   v(1:3) = T(1:3,4)';
   tmp = rotm2eul(T(1:3,1:3),"ZYX");
   v(4:6) = [tmp(3),tmp(2),tmp(1)];
end