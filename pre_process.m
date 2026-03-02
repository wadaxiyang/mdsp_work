%% 双轴（Y+Z）OPM数据处理流程

% 数据说明：所有数据均为64通道OPM-MEG原始数据。读取到的原始数据当中共有68个sensor，136个channel, 139 Data Columns;
% Sensor设置：1-64为头部MEG通道，65-67为空间背景当中正交的三轴reference sensors,
% 68为常备MMG/MCG通道。随后两个通道分别记录了刺激信号（对于mission1的干模为AWG发出的电信号，对于mission2则为音频信号同步记录）和并口数字trigger。
clear; close all; clc;

% 1. 首先添加 FieldTrip 路径
addpath('./fieldtrip-20251218/');

% 2. 将 FieldTrip 路径移到后面，让 MATLAB 内置函数优先
fieldtrip_path = './fieldtrip-20251218/';
rmpath(fieldtrip_path);
addpath(fieldtrip_path, '-end');  % '-end' 参数将路径添加到末尾

% 3. 验证路径顺序
which iscolumn -all
ft_defaults;

%% 路径设置
% 存储.lvm文件的文件夹的路径
floder_path = './Mission1/';
% .lvm文件的文件名
file_name = 'data_1.lvm';
% 分离出不含后缀的文件名
temp = split(file_name, '.lvm');
data_name = temp{1};
% .lvm文件的存储路径
file_path = [floder_path file_name];
% 设置结果文件夹路径 如果不存在文件夹，新建
result_path = [floder_path 'results\'];
if ~exist(result_path, 'dir'); mkdir(result_path); end
% 存储模板数据和layout的文件夹路径
load_path = './lvm2ft_processing/';




%% 读取.lvm数据 - 分离Y轴和Z轴数据
% 数据的采样率，按实际情况修改
Fs = 4800;
% 从V到T的转换系数，按实际情况修改
gain = 1e6; 
data_NI = lvm_import(file_path); 
data_raw = data_NI.Segment1.data;
data_start = data_raw';
% 为了保证t的初始值为0，时间向量减去初始值
t = 0:(1/Fs):((length(data_start)-1)/Fs);
sync = data_start(138,:)-data_start(138,1);
digi = data_start(139,:);

%% ===================== Y轴数据处理 =====================
fprintf('===================== 处理Y轴数据 =====================\n');
data_start_Y = data_start(2:end, :)* gain;  % Y轴数据在偶数通道
channel_Y = [2:2:136];  % Y轴通道
data_Y = data_start_Y(channel_Y, :);

% 基线校正
initial_values_Y = data_Y(:, 1);
data_Y = data_Y - initial_values_Y;

% Y轴标定参数
refFreq_Y = 240;  % Y轴参考信号频率
targetPeak_Y = 62400;  % Y轴目标峰值
N_samples = size(data_Y, 2);

fprintf('Y轴实时校准...\n');
data_cali_Y = real_time_calibration(data_Y, Fs, refFreq_Y, targetPeak_Y);


% >>>>> [插入开始] 任务 1.2 去除尖峰电子噪音 >>>>>
fprintf('Y轴去尖峰处理 (Despiking)...\n');
% 参数：窗口长度 20ms (约96个点), 阈值 6倍标准差 (严格剔除极值)
[data_despiked_Y, n_spikes_Y] = remove_spikes_gradient(data_cali_Y, 5);
fprintf('  Y轴共检测并修复了 %d 个尖峰点\n', sum(n_spikes_Y));
% 更新数据流：将去尖峰后的数据传给下一级
data_cali_Y = data_despiked_Y; 
% <<<<< [插入结束] <<<<<


% Y轴240Hz深度陷波滤波
fprintf('Y轴240Hz深度陷波滤波...\n');
data_notched_Y = deep_notch_filter(data_cali_Y, Fs, 240);

%% ===================== Z轴数据处理 =====================
fprintf('\n===================== 处理Z轴数据 =====================\n');
data_start_Z = data_start(2:end, :)* gain;  % Z轴数据在奇数通道
channel_Z = [1:2:136];  % Z轴通道
data_Z = data_start_Z(channel_Z, :);

% 基线校正
initial_values_Z = data_Z(:, 1);
data_Z = data_Z - initial_values_Z;

% Z轴标定参数
refFreq_Z = 320;  % Z轴参考信号频率
targetPeak_Z = 55600;  % Z轴目标峰值

fprintf('Z轴实时校准...\n');
data_cali_Z = real_time_calibration(data_Z, Fs, refFreq_Z, targetPeak_Z);

% >>>>> [插入开始] 任务 1.2 去除尖峰电子噪音 >>>>>
fprintf('Z轴去尖峰处理 (Despiking)...\n');
[data_despiked_Z, n_spikes_Z] = remove_spikes_gradient(data_cali_Z, 5);
fprintf('  Z轴共检测并修复了 %d 个尖峰点\n', sum(n_spikes_Z));
% <<<<< [插入结束] <<<<<

%% 
% Z轴320Hz深度陷波滤波
fprintf('Z轴320Hz深度陷波滤波...\n');
data_notched_Z = deep_notch_filter(data_despiked_Z, Fs, 320);


%% 通过探头在头盔上的位置和与采集到数据通道的对应表得到通道情况
layout_idx = [27 17 2 36 9 30 13 3 16 33 7 4 14 59 43 40 42 60 46 57 41 37 63 44 45 19 26 18 56 53 10 54 32 64 29 15 28 52 58 12 1 51 62 31 34 6 39 22 24 11 55 38 61 47 50 23 20 25 5 21 49 48 8 35];
% 与layout通道编号对应的数据通道序号
channelBYlayout = [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64];
% 数据通道序号重新排序
channel_idx = sort(channelBYlayout);


%% 合并Y轴和Z轴数据，创建双轴数据矩阵
fprintf('\n===================== 合并Y轴和Z轴数据 =====================\n');
% 创建合并的数据矩阵：奇数行是Z轴，偶数行是Y轴
data_combined = zeros(128, N_samples);
for i = 1:64
    % Z轴数据在奇数行 (1, 3, 5, ..., 127)
    data_combined(2*i-1, :) = data_notched_Z(channelBYlayout(i), :);
    % Y轴数据在偶数行 (2, 4, 6, ..., 128)
    data_combined(2*i, :) = data_notched_Y(channelBYlayout(i), :);
end

fprintf('合并数据大小: %d通道 × %d时间点\n', size(data_combined, 1), size(data_combined, 2));

%% 将数据转换成fieldtrip格式（双轴版本）
fprintf('\n===================== 转换为FieldTrip格式（双轴） =====================\n');

% 加载filedtrip可读格式的数据模板
data_temp = importdata( './data_temp30s.mat'); 
% 加载layout
layout = importdata( './layout_zkzyopm.mat');

% 将现有数据写入模板，包含双轴通道
data_ft = data_temp;
data_ft.fsample = Fs;
data_ft.trial{1} = data_combined;  % 包含128个通道（64个Z轴 + 64个Y轴）
data_ft.time{1} = t;

% 创建双轴通道标签：Z轴为CH01, CH02,...，Y轴为CH01Y, CH02Y,...
channels = cell(128, 1);
for i = 1:64
    % Z轴通道标签
    channels{2*i-1} = sprintf('CH%02d', channel_idx(i));
    % Y轴通道标签
    channels{2*i} = sprintf('CH%02dY', channel_idx(i));
end
data_ft.label = channels;

cfg = [];
cfg.hpfilter = 'no';
cfg.lpfilter = 'no';
cfg.channel = channels; 
data_proc = ft_preprocessing(cfg, data_ft);

fprintf('双轴FieldTrip数据结构创建完成\n');
fprintf('  总通道数: %d (64 Z轴 + 64 Y轴)\n', length(data_proc.label));
fprintf('  Z轴通道: CH01-CH64 (奇数行)\n');
fprintf('  Y轴通道: CH01Y-CH64Y (偶数行)\n');


% 保存陷波滤波后的数据用于评估 ---
data_notch_ft = data_proc;


%% layout label 对齐到 data_ft label（基于Z轴通道）
fprintf('\n===================== 对齐layout标签 =====================\n');
layout_label = layout.label;
for i = 1:length(channel_idx)
    idx = layout_idx(i);
    idx_str = string(idx);
    label_num = find(strcmp(layout.label(:, 1), string(idx)));
    layout_label{label_num} = sprintf('CH%02d', channelBYlayout(i));
end
layout.label = layout_label;

fprintf('Layout标签已对齐到Z轴通道\n');

%% 修正grad结构（使用grad_original和grad_Y_original）
fprintf('\n===================== 修正grad结构（ZY双轴） =====================\n');

% 加载Z轴和Y轴的grad结构
load('./grad_transformed.mat');  % Z轴grad
load('./grad_Y_transformed.mat');  % Y轴grad

% 为双轴数据创建grad结构
grad_dual = struct();

% 合并位置信息
grad_dual.chanpos = zeros(128, 3);
grad_dual.coilpos = zeros(128, 3);

% 合并方向信息：Z轴使用ori_z，Y轴使用ori_y
grad_dual.ori_z = zeros(128, 3);  % Z轴方向（法向）
grad_dual.ori_y = zeros(128, 3);  % Y轴方向（短边）
grad_dual.ori_x = zeros(128, 3);  % X轴方向（长边）

% 合并chanori和coilori
grad_dual.chanori = zeros(128, 3);
grad_dual.coilori = zeros(128, 3);

% 填充数据：Z轴通道（奇数行）
for i = 1:64
    idx_z = 2*i-1;
    grad_dual.chanpos(idx_z, :) = grad_transformed.chanpos(i, :);
    grad_dual.coilpos(idx_z, :) = grad_transformed.coilpos(i, :);
    grad_dual.ori_z(idx_z, :) = grad_transformed.ori_z(i, :);      % Z轴法向
    grad_dual.ori_y(idx_z, :) = grad_transformed.ori_y(i, :);      % 短边方向
    grad_dual.ori_x(idx_z, :) = grad_transformed.ori_x(i, :);      % 长边方向
    grad_dual.chanori(idx_z, :) = grad_transformed.chanori(i, :);  % 通常为Z轴方向
    grad_dual.coilori(idx_z, :) = grad_transformed.coilori(i, :);  % 通常为Z轴方向
end

% 填充数据：Y轴通道（偶数行）
for i = 1:64
    idx_y = 2*i;
    grad_dual.chanpos(idx_y, :) = grad_Y_transformed.chanpos(i, :);
    grad_dual.coilpos(idx_y, :) = grad_Y_transformed.coilpos(i, :);
    grad_dual.ori_z(idx_y, :) = grad_Y_transformed.ori_z(i, :);      % 法向（应与Z轴相同）
    grad_dual.ori_y(idx_y, :) = grad_Y_transformed.ori_y(i, :);      % Y轴方向
    grad_dual.ori_x(idx_y, :) = grad_Y_transformed.ori_x(i, :);      % X轴方向
    grad_dual.chanori(idx_y, :) = grad_Y_transformed.chanori(i, :);  % 通常为Z轴方向
    grad_dual.coilori(idx_y, :) = grad_Y_transformed.coilori(i, :);  % 通常为Z轴方向
end

grad_dual.label = channels;
grad_dual.chantype = repmat({'meg'}, 128, 1);
grad_dual.chanunit = repmat({'T'}, 128, 1);
grad_dual.tra = eye(128);
grad_dual.type = 'meg';
grad_dual.unit = 'mm';

data_proc.grad = grad_dual;
fprintf('双轴grad结构创建完成\n');
fprintf('  Z轴方向从grad_transformed获取\n');
fprintf('  Y轴方向从grad_Y_transformed获取\n');

%% 传感器深度调整
fprintf('\n===================== 传感器深度调整 =====================\n');
% 默认所有传感器向头模外侧后退5.5mm
depth_adjustments = 5.5 * ones(128, 1);  % 所有通道相同调整

for i = 1:length(data_proc.grad.chanpos)
    current_pos = data_proc.grad.chanpos(i, :);
    if mod(i, 2) == 1  % 奇数行：Z轴，使用ori_z作为法向
        current_ori = data_proc.grad.ori_z(i, :);
    else  % 偶数行：Y轴，也使用ori_z作为法向（应与Z轴相同）
        current_ori = data_proc.grad.ori_z(i, :);
    end
    new_pos = current_pos + current_ori * depth_adjustments(i);
    data_proc.grad.chanpos(i, :) = new_pos;
    data_proc.grad.coilpos(i, :) = new_pos;
    if i <= 10 || mod(i, 20) == 0  % 只显示部分信息避免输出太多
        fprintf('通道 %s: 位置调整 %.1f mm\n', data_proc.label{i}, depth_adjustments(i));
    end
end
fprintf('传感器深度调整完成\n');




%% 实时三轴线性降噪（使用参考传感器数据 - Z轴和Y轴）
fprintf('\n===================== 实时三轴线性降噪（双轴参考） =====================\n');

% 参考传感器索引（假设在原始数据中的位置）
% 使用65、66、67号传感器的Z轴和Y轴数据，共6个参考通道
ref_z_idx = [65, 66, 67];  % Z轴参考传感器
ref_y_idx = [65, 66, 67];  % Y轴参考传感器（与Z轴对应）
n_ref_z = length(ref_z_idx);
n_ref_y = length(ref_y_idx);
n_ref_total = n_ref_z + n_ref_y;  % 总共6个参考通道
n_meg_dual = size(data_proc.trial{1}, 1);  % 双轴MEG通道数

% 从原始数据中获取参考传感器数据（Z轴和Y轴）
ref_data = zeros(n_ref_total, N_samples);
% Z轴参考数据
for i = 1:n_ref_z
    ref_data(i, :) = data_notched_Z(ref_z_idx(i), :);
end
% Y轴参考数据
for i = 1:n_ref_y
    ref_data(n_ref_z + i, :) = data_notched_Y(ref_y_idx(i), :);
end



% 实时参数
adaptive_forgetting_factor = 0.995;  % RLS遗忘因子
window_size = 1024;  % 用于估计协方差矩阵的窗口大小
min_samples_for_estimation = 100;  % 开始降噪的最小样本数

% 初始化实时变量
beta_real_time = zeros(n_ref_total + 1, n_meg_dual);  % 实时回归系数
P_matrix = 1000 * eye(n_ref_total + 1);  % RLS算法的P矩阵
noise_history = zeros(n_ref_total + 1, window_size);  % 参考信号历史
meg_history = zeros(n_meg_dual, window_size);  % MEG信号历史
sample_count = 0;

% 实时降噪输出
data_denoised_real_time = zeros(n_meg_dual, N_samples);

fprintf('开始实时三轴双参考降噪...\n');
fprintf('  处理%d个双轴MEG通道\n', n_meg_dual);
fprintf('  使用%d个参考通道（3个Z轴 + 3个Y轴）\n', n_ref_total);
fprintf('  参考传感器：65、66、67的Z轴和Y轴数据\n');

% 递推最小二乘法
for n = 1:N_samples
    % 获取当前时刻的参考信号和MEG信号
    current_ref = [1; ref_data(:, n)];  % 添加常数项
    current_meg = data_proc.trial{1}(:, n);
    
    sample_count = sample_count + 1;
    
    if sample_count >= min_samples_for_estimation
        % RLS算法更新回归系数
        K = P_matrix * current_ref / (adaptive_forgetting_factor + current_ref' * P_matrix * current_ref);
        prediction_error = current_meg - beta_real_time' * current_ref;
        beta_real_time = beta_real_time + K * prediction_error';
        P_matrix = (P_matrix - K * current_ref' * P_matrix) / adaptive_forgetting_factor;
        
        % 实时降噪
        noise_prediction = beta_real_time' * current_ref;
        data_denoised_real_time(:, n) = current_meg - noise_prediction;
    else
        % 前min_samples_for_estimation个样本，只收集数据不进行降噪
        data_denoised_real_time(:, n) = current_meg;
        
        % 更新历史数据
        if sample_count <= window_size
            noise_history(:, sample_count) = current_ref;
            meg_history(:, sample_count) = current_meg;
        end
        
        % 当收集到足够样本时，初始化回归系数
        if sample_count == min_samples_for_estimation
            fprintf('初始化回归系数，使用前%d个样本...\n', min_samples_for_estimation);
            X_initial = noise_history(:, 1:min_samples_for_estimation)';
            Y_initial = meg_history(:, 1:min_samples_for_estimation)';
            beta_real_time = X_initial \ Y_initial;
            
            % 显示回归系数信息
            fprintf('回归系数矩阵大小: %d x %d\n', size(beta_real_time, 1), size(beta_real_time, 2));
        end
    end
    

end

% 应用降噪结果
data_proc.trial{1} = data_denoised_real_time;

% --- [插入代码] 保存 RLS 降噪后的数据用于评估 ---
data_rls_ft = data_proc;
% -------------------------------------------

% 分析降噪效果
fprintf('实时三轴双参考降噪完成\n');

% 计算降噪前后的功率变化
if N_samples > 1000
    % 计算降噪前后的信号功率（使用后1000个样本）
    start_idx = max(1, N_samples - 1000);
    signal_before = data_proc.trial{1}(:, start_idx:end);
    % 重新计算原始数据用于比较（需要从data_start获取原始双轴数据）
    original_dual_data = zeros(n_meg_dual, N_samples);
    for i = 1:64
        % Z轴数据在奇数行
        original_dual_data(2*i-1, :) = data_notched_Z(channelBYlayout(i), :);
        % Y轴数据在偶数行
        original_dual_data(2*i, :) = data_notched_Y(channelBYlayout(i), :);
    end
    
    % 如果有剔除通道，需要对齐
    if exist('selected_channels', 'var') && ~isempty(selected_channels)
        % 找到保留通道的索引
        keep_indices = find(~ismember(data_proc.label, selected_channels));
        if ~isempty(keep_indices)
            original_dual_data = original_dual_data(keep_indices, :);
        end
    end
    
    power_before = mean(var(original_dual_data(:, start_idx:end), 0, 2));
    power_after = mean(var(data_denoised_real_time(:, start_idx:end), 0, 2));
    reduction = 100 * (1 - power_after / power_before);
    
    fprintf('降噪效果评估（使用后1000个样本）：\n');
    fprintf('  降噪前平均功率: %.4e\n', power_before);
    fprintf('  降噪后平均功率: %.4e\n', power_after);
    fprintf('  噪声降低: %.1f%%\n', reduction);
end

%% HFC前滤波
fprintf('\n===================== HFC前滤波 =====================\n');
cfg = [];
cfg.channel = 'all';
cfg.demean = 'yes';
cfg.dftfilttype = 'firws';  % 使用线性相位或最小相位滤波器
cfg.usefftfilt = 'yes';  % 启用频域滤波减少时域畸变
cfg.dftfilter = 'yes';  % baseline correct
cfg.dftfreq = refFreq_Z;  % 使用Z轴参考频率
cfg.dftreplace = 'neighbour';
cfg.dftbandwidth = [4];
cfg.dftneighbourwidth = [4];
cfg.detrend = 'yes';
data_proc1 = ft_preprocessing(cfg, data_proc);
fprintf('HFC前滤波完成\n');

%% ===================== ZY双轴联合HFC降噪 =====================
fprintf('\n===================== ZY双轴联合HFC降噪 =====================\n');

% 获取当前通道数
n_channels = size(data_proc1.trial{1}, 1);

% 提取Z轴和Y轴通道索引
z_indices = find(contains(data_proc1.label, 'CH') & ~contains(data_proc1.label, 'Y'));
y_indices = find(contains(data_proc1.label, 'Y'));

% 获取Z轴和Y轴的方向信息
if isfield(data_proc1.grad, 'ori_z') && isfield(data_proc1.grad, 'ori_y')
    % 提取Z轴方向（法向）
    Ori_z_matrix = zeros(n_channels, 3);
    Ori_z_matrix(z_indices, :) = data_proc1.grad.ori_z(z_indices, :);  % Z轴通道的法向
    Ori_z_matrix(y_indices, :) = data_proc1.grad.ori_z(y_indices, :);  % Y轴通道的法向（应与Z轴相同）
    
    % 提取Y轴方向（短边方向）
    Ori_y_matrix = zeros(n_channels, 3);
    Ori_y_matrix(z_indices, :) = data_proc1.grad.ori_y(z_indices, :);  % Z轴通道的Y轴方向
    Ori_y_matrix(y_indices, :) = data_proc1.grad.ori_y(y_indices, :);  % Y轴通道的Y轴方向
    
    fprintf('ZY双轴方向信息已获取\n');
    fprintf('  Z轴通道数: %d\n', length(z_indices));
    fprintf('  Y轴通道数: %d\n', length(y_indices));
else
    error('grad结构中缺少ori_z或ori_y字段');
end

% ===================== 双轴联合投影矩阵 =====================
fprintf('\n构建ZY双轴联合投影矩阵\n');

% 将Z轴和Y轴方向合并为一个矩阵 [N_z, N_y]
% 这是一个 2n × n 的矩阵，但我们需要将其转换为适当的形式
n = n_channels;  % 总通道数

% 创建方向矩阵：每行对应一个通道，每列对应一个空间方向
% 对于ZY双轴HFC，我们想要消除的是传感器局部坐标系中的两个方向分量
% 因此我们需要构建一个投影到这两个方向张成的子空间的正交补空间的投影矩阵

% 方法：使用奇异值分解（SVD）来构建投影矩阵
N_combined = [Ori_z_matrix'; Ori_y_matrix'];  % 3×n 和 3×n 合并为 6×n
N_combined = N_combined';  % 转置为 n×6

% 使用SVD计算投影矩阵
[U, S, V] = svd(N_combined, 'econ');

% 确定有效秩（非零奇异值的数量）
sv = diag(S);
tol = max(size(N_combined)) * eps(max(sv));
rank_N = sum(sv > tol);

fprintf('方向矩阵信息：\n');
fprintf('  矩阵大小: %dx%d\n', size(N_combined, 1), size(N_combined, 2));
fprintf('  奇异值: %s\n', mat2str(sv', 3));
fprintf('  有效秩: %d\n', rank_N);

if rank_N > 0
    % 构建投影矩阵：P = I - U(:,1:rank_N) * U(:,1:rank_N)'
    U_reduced = U(:, 1:rank_N);
    P = eye(n) - U_reduced * U_reduced';
    
    fprintf('投影矩阵构建完成：\n');
    fprintf('  投影矩阵大小: %dx%d\n', size(P, 1), size(P, 2));
    fprintf('  投影矩阵秩: %d\n', rank(P));
    fprintf('  特征值范围: [%.2e, %.2e]\n', min(eig(P)), max(eig(P)));
    
    % 应用投影矩阵进行HFC降噪
    data_before_HFC = data_proc1.trial{1};
    data_AfterHFC = P * data_before_HFC;
    data_proc1.trial{1} = data_AfterHFC;
    
    
    % --- [插入代码] 保存 HFC 降噪后的数据用于评估 ---
    data_hfc_ft = data_proc1;
    % -------------------------------------------

    fprintf('ZY双轴联合HFC降噪完成\n');
    
    % 计算降噪效果
    noise_power_before = mean(var(data_before_HFC, 0, 2));
    noise_power_after = mean(var(data_AfterHFC, 0, 2));
    noise_reduction = 100 * (1 - noise_power_after / noise_power_before);
    
    fprintf('降噪效果评估：\n');
    fprintf('  降噪前平均功率: %.4e\n', noise_power_before);
    fprintf('  降噪后平均功率: %.4e\n', noise_power_after);
    fprintf('  噪声降低: %.1f%%\n', noise_reduction);
else
    fprintf('警告：方向矩阵秩为0，无法进行HFC降噪\n');
end



%% 最终滤波
fprintf('\n===================== 最终滤波处理 =====================\n');
cfg = [];
cfg.channel = 'all';
cfg.demean = 'yes';
cfg.dftfilttype = 'firws';  % 使用线性相位或最小相位滤波器
cfg.usefftfilt = 'yes';  % 启用频域滤波减少时域畸变
cfg.dftfilter = 'yes';  % baseline correct
cfg.dftfreq = [50, 100, 150, 200, 250];
cfg.dftreplace = 'neighbour';
cfg.dftbandwidth = [2, 2, 2, 2, 2];
cfg.dftneighbourwidth = [4, 4, 4, 4, 4];
cfg.detrend = 'yes';
cfg.hpfilttype = 'firws';  % 使用线性相位或最小相位滤波器
cfg.hpfilter = 'yes';  % highpass filter
cfg.hpfreq = 1;
cfg.lpfilttype = 'firws';  % 使用线性相位或最小相位滤波器
cfg.lpfilter = 'yes';  % lowpass filter
cfg.lpfreq = 400;
data_filtered = ft_preprocessing(cfg, data_proc1);

fprintf('\n===================== 处理完成 =====================\n');
fprintf('双轴数据处理流程完成！\n');
fprintf('最终数据结构信息：\n');
fprintf('  通道总数: %d\n', length(data_filtered.label));
fprintf('  Z轴通道数: %d\n', sum(contains(data_filtered.label, 'CH') & ~contains(data_filtered.label, 'Y')));
fprintf('  Y轴通道数: %d\n', sum(contains(data_filtered.label, 'Y')));
fprintf('  时间点数: %d\n', size(data_filtered.trial{1}, 2));
fprintf('  采样率: %.0f Hz\n', data_filtered.fsample);


data_filtered = data_proc1;






%% save
save('./workspace.mat')