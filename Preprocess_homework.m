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



%%
% % 裁剪数据，保留前300秒--用于第二项作业
% samples_to_keep = 300 * Fs;  % 300秒 * 采样率
%     data_start = data_start(:, 1:samples_to_keep);
%     sync = sync(1:samples_to_keep);
%     digi = digi(1:samples_to_keep);
%     t = t(1:samples_to_keep);
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


%% --- [任务 1.2 步骤1]：时域观察尖峰噪音 ---
% 选择一个典型通道（例如第1个Z轴通道）进行观察
observe_ch = 6; 
observe_data = data_cali_Z(observe_ch, :); % 使用校准后、滤波前的数据

figure('Name', '任务1.2: 尖峰噪音观察', 'Color', 'w');
subplot(2,1,1);
plot(t, observe_data);
title('全时段数据 (寻找异常突变)');
xlabel('Time (s)'); ylabel('Amplitude');

subplot(2,1,2);
% 随机放大一个包含尖峰的区域 (根据实际数据调整这里的范围)
% 假设尖峰可能发生在任意位置，这里取前1秒作为示例，你可能需要手动缩放
plot(t(1:Fs), observe_data(1:Fs), '.-'); 
title('1秒放大视图 (观察波形平滑度)');
xlabel('Time (s)'); ylabel('Amplitude');
grid on;


%% --- [任务 1.2 步骤3]：验证去尖峰效果 ---
% 对比去尖峰前后的数据，确保 17Hz 信号没有被误杀
check_idx = 1; % 检查第1个通道
tmp_trip_idx=5000;
t_snippet = t(1:tmp_trip_idx); % 取前 2000 个点观察

figure('Name', '任务1.2: 去尖峰效果验证', 'Color', 'w');
subplot(2,1,1);
plot(t_snippet, data_cali_Z(check_idx, 1:tmp_trip_idx), 'Color', [0.8 0.8 0.8], 'LineWidth', 2); hold on;
plot(t_snippet, data_despiked_Z(check_idx, 1:tmp_trip_idx), 'b', 'LineWidth', 1);
legend('原始带尖峰数据', '去尖峰后数据');
title('波形对比 (灰色为原始，蓝色为处理后)');
ylabel('Amplitude');

subplot(2,1,2);
% 计算残差：看看我们减掉了什么
residual = data_cali_Z(check_idx, 1:tmp_trip_idx) - data_despiked_Z(check_idx, 1:tmp_trip_idx);
plot(t_snippet, residual, 'r');
title('被剔除的尖峰 (Residual)');
xlabel('Time (s)'); ylabel('Amplitude');


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

%% 手动选择要剔除的通道（基于Z轴数据）
fprintf('\n===================== 手动通道剔除（基于Z轴数据） =====================\n');
fprintf('正在准备Z轴数据用于可视化...\n');

% 提取Z轴数据用于选择（奇数行）
z_channel_indices = 1:2:127;  % Z轴通道索引
z_channel_labels = data_proc.label(z_channel_indices);

% 创建仅包含Z轴数据的选择数据
selection_data = data_proc;
selection_data.trial{1} = data_proc.trial{1}(z_channel_indices, :);
selection_data.label = z_channel_labels;

% 简化grad结构（仅Z轴）
z_grad = grad_transformed;
z_grad.label = z_channel_labels;
selection_data.grad = z_grad;

% 显示所有Z轴通道的时间序列，让用户选择要剔除的通道
figure('Name', '通道选择 - 单击选择要剔除的通道（Z轴数据）', 'NumberTitle', 'off', ...
    'Position', [100, 100, 1400, 800]);

% 使用ft_multiplotER显示所有Z轴通道
cfg = [];
cfg.layout = layout;
cfg.interactive = 'yes';
cfg.showlabels = 'yes';
cfg.showoutline = 'yes';
cfg.channel = 'all';
ft_multiplotER(cfg, selection_data);

% 手动选择要剔除的Z轴通道
fprintf('=== 手动通道剔除（Z轴） ===\n');

% 显示所有可用Z轴通道
fprintf('可用的Z轴通道列表：\n');
for i = 1:length(z_channel_labels)
    fprintf('%3d: %s\n', i, z_channel_labels{i});
end
fprintf('\n');

% 用户输入要剔除的通道编号
prompt = '请输入要剔除的Z轴通道编号（多个编号用空格或逗号分隔，直接回车跳过）：\n';
channel_input = input(prompt, 's');

% 处理用户输入
channels_to_remove = [];
if ~isempty(channel_input)
    % 替换逗号为空格
    channel_input = strrep(channel_input, ',', ' ');
    
    % 分割输入字符串
    channel_nums_str = strsplit(strtrim(channel_input));
    
    % 转换为数字
    for i = 1:length(channel_nums_str)
        if ~isempty(channel_nums_str{i})
            num = str2double(channel_nums_str{i});
            if ~isnan(num) && num >= 1 && num <= length(z_channel_labels)
                channels_to_remove = [channels_to_remove, num];
            else
                fprintf('警告：通道编号 %s 无效，已跳过\n', channel_nums_str{i});
            end
        end
    end
end

% 去重并排序
channels_to_remove = unique(channels_to_remove);

if ~isempty(channels_to_remove)
    % 获取要剔除的Z轴通道标签
    selected_z_channels = z_channel_labels(channels_to_remove);
    
    fprintf('您选择的剔除通道：\n');
    for i = 1:length(selected_z_channels)
        fprintf('%s\n', selected_z_channels{i});
    end
    
    % 找到对应的Y轴通道
    selected_channels = {};
    for i = 1:length(selected_z_channels)
        % Z轴通道名
        z_name = selected_z_channels{i};
        % 对应的Y轴通道名（将CHXX改为CHXXY）
        if startsWith(z_name, 'CH')
            channel_num = z_name(3:end);
            y_name = ['CH' channel_num 'Y'];
            selected_channels = [selected_channels; {z_name}; {y_name}];
        end
    end
    
    fprintf('同时剔除对应的Y轴通道：\n');
    for i = 2:2:length(selected_channels)
        fprintf('%s\n', selected_channels{i});
    end
    
    % 从数据中移除选中的通道（Z轴和对应的Y轴）
    cfg = [];
    cfg.channel = setdiff(data_proc.label, selected_channels);  % 排除选中的通道
    data_proc = ft_selectdata(cfg, data_proc);
    
    % 更新通道数量
    n_channels = length(data_proc.label);
    fprintf('剔除后剩余通道数：%d (Z轴: %d, Y轴: %d)\n', ...
        n_channels, sum(contains(data_proc.label, 'CH') & ~contains(data_proc.label, 'Y')), ...
        sum(contains(data_proc.label, 'Y')));
    
    % 同时更新layout，移除相应Z轴通道
    if exist('layout', 'var')
        % 找到要保留的Z轴通道在原始layout中的索引
        keep_idx = [];
        for i = 1:length(layout.label)
            if ~ismember(layout.label{i}, selected_z_channels)
                keep_idx = [keep_idx, i];
            end
        end
        
        % 创建新的layout结构
        layout_clean.label = layout.label(keep_idx);
        layout_clean.pos = layout.pos(keep_idx, :);
        layout_clean.width = layout.width(keep_idx);
        layout_clean.height = layout.height(keep_idx);
        
        if isfield(layout, 'outline')
            layout_clean.outline = layout.outline;
        end
        if isfield(layout, 'mask')
            layout_clean.mask = layout.mask;
        end
        
        layout = layout_clean;
        fprintf('Layout已更新，移除对应Z轴通道\n');
    end
else
    fprintf('未输入任何通道编号，跳过通道剔除\n');
end

fprintf('=== 通道剔除完成 ===\n\n');

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



%% ===================== 验证猜想：参考通道信号泄露分析 =====================
fprintf('\n===================== 验证猜想：检查参考通道信号泄露 =====================\n');

% 1. 提取参考通道数据 
% 注意：我们需要使用 RLS 处理之前的“干净”数据（即经过校准和陷波的数据）
% 也就是 data_notched_Z 和 data_notched_Y 的 65-67 通道
ref_data_z = data_notched_Z(65:67, :); % Z轴参考
ref_data_y = data_notched_Y(65:67, :); % Y轴参考

% 合并成 6 个通道的矩阵 (3个Z轴 + 3个Y轴)
ref_data_combined = [ref_data_z; ref_data_y];

% 2. 构建临时的 FieldTrip 结构用于分析
data_ref_ft = [];
data_ref_ft.fsample = Fs;
data_ref_ft.time{1} = t;
data_ref_ft.trial{1} = ref_data_combined;
% 给通道起个名字方便看图
data_ref_ft.label = {'Ref-Z (Ch65)', 'Ref-Z (Ch66)', 'Ref-Z (Ch67)', ...
                     'Ref-Y (Ch65)', 'Ref-Y (Ch66)', 'Ref-Y (Ch67)'};

% 3. 计算频谱 (PSD)
cfg_ref = [];
cfg_ref.method = 'mtmfft';     % 多推测窗变换
cfg_ref.taper = 'hanning';     % 汉宁窗
cfg_ref.output = 'pow';        % 输出功率谱
cfg_ref.pad = 'nextpow2';      % 补零以优化FFT速度
cfg_ref.foi = 1:0.5:40;        % 我们只关心低频，特别是 17Hz 附近
cfg_ref.keeptrials = 'no';     % 计算平均谱

fprintf('正在计算参考通道的频谱...\n');
freq_ref = ft_freqanalysis(cfg_ref, data_ref_ft);

% 4. 绘图验证
figure('Name', '验证猜想：参考通道中的信号泄露 (Signal Leakage)', 'Color', 'w', 'Position', [100, 100, 800, 600]);

% 子图1：Z轴参考传感器
subplot(2,1,1);
plot(freq_ref.freq, freq_ref.powspctrm(1:3, :), 'LineWidth', 1.5);
hold on;
xline(17, '--r', '17Hz Signal', 'LineWidth', 1.5, 'LabelVerticalAlignment', 'bottom');
title('参考传感器频谱 (Z轴) - 是否包含 17Hz 信号？');
xlabel('Frequency (Hz)');
ylabel('Power (T^2/Hz)');
legend(data_ref_ft.label(1:3), 'Location', 'northeast');
grid on;
xlim([5 30]); % 放大看 5-30Hz 范围

% 子图2：Y轴参考传感器
subplot(2,1,2);
plot(freq_ref.freq, freq_ref.powspctrm(4:6, :), 'LineWidth', 1.5);
hold on;
xline(17, '--r', '17Hz Signal', 'LineWidth', 1.5, 'LabelVerticalAlignment', 'bottom');
title('参考传感器频谱 (Y轴) - 是否包含 17Hz 信号？');
xlabel('Frequency (Hz)');
ylabel('Power (T^2/Hz)');
legend(data_ref_ft.label(4:6), 'Location', 'northeast');
grid on;
xlim([5 30]); % 放大看 5-30Hz 范围

% 5. 自动判断并输出结论
% 简单检测：比较 17Hz 的能量和 15Hz 的能量
idx_17 = find(abs(freq_ref.freq - 17) < 0.25, 1);
idx_15 = find(abs(freq_ref.freq - 15) < 0.25, 1);

mean_power_17 = mean(mean(freq_ref.powspctrm(:, idx_17)));
mean_power_15 = mean(mean(freq_ref.powspctrm(:, idx_15)));
ratio = mean_power_17 / mean_power_15;

fprintf('\n----------------------------------------\n');
fprintf('       Mission 1.1: 信号泄露验证结果       \n');
fprintf('----------------------------------------\n');
fprintf('  17Hz 处平均功率: %.2e\n', mean_power_17);
fprintf('  15Hz 处背景功率: %.2e\n', mean_power_15);
fprintf('  信噪比 (Leakage Ratio): %.2f 倍\n', ratio);

if ratio > 10
    fprintf('\n  [结论]: 验证成功！参考通道中存在极强的 17Hz 信号泄露。\n');
    fprintf('         这解释了为什么 RLS 算法会导致信噪比下降。\n');
else
    fprintf('\n  [结论]: 泄露不明显，可能需要重新检查数据或频带设置。\n');
end
fprintf('----------------------------------------\n');



%% ===================== 任务 1.3：使用 LMS 自适应谱线增强 (ALE) =====================
fprintf('\n===================== 任务 1.3：LMS 自适应谱线增强 (ALE) =====================\n');
fprintf('原理：使用 Normalized LMS 算法，利用信号周期性分离噪声\n');

% 1. 准备数据
% 我们使用 "去尖峰后" 的数据作为输入
% (为了公平对比，我们不使用 RLS 参考降噪后的数据，而是直接从去尖峰后的数据开始)
fprintf('构建输入数据 (合并 Z 和 Y 轴)...\n');
data_for_lms = zeros(128, size(data_despiked_Z, 2));
for i = 1:64
    data_for_lms(2*i-1, :) = data_despiked_Z(channelBYlayout(i), :);
    data_for_lms(2*i, :) = data_despiked_Y(channelBYlayout(i), :);
end

% 2. 设置 LMS-ALE 参数
% 延迟 (Delay): 必须大于噪声的相关时间。25ms 约为 17Hz 信号的半个周期，效果较好
ale_delay_ms = 25;      
% 阶数 (Order): 滤波器长度。对于单频信号，30-50 阶足够
ale_order = 30;         
% 步长 (Step Size, mu): 决定收敛速度和稳态误差
% 我们使用归一化 LMS (NLMS)，步长通常取 0.01 - 1.0 之间
ale_mu = 0.001;          

fprintf('开始 LMS-ALE 处理 (Delay=%dms, Order=%d, Step=%.3f)...\n', ...
    ale_delay_ms, ale_order, ale_mu);

% 3. 调用 LMS 函数
tic; % 计时
data_lms_cleaned = apply_ale_lms(data_for_lms, Fs, ale_delay_ms, ale_order, ale_mu);
toc;

% 4. 将结果转回 FieldTrip 结构以便评估
data_lms_ft = data_notch_ft; % 借用壳子
data_lms_ft.trial{1} = data_lms_cleaned;

fprintf('LMS 处理完成。\n');

% --- 对比评估 (LMS vs HFC) ---
% 计算 LMS 的 MSE (相对于 Sync)
if exist('sync_norm', 'var') && exist('compute_mse_internal', 'file')
    mse_lms = compute_mse_internal(data_lms_ft.trial{1}, sync_norm);
    
    fprintf('\n----------------------------------------\n');
    fprintf('       Mission 1.3: LMS 降噪效果评估       \n');
    fprintf('----------------------------------------\n');
    fprintf('  方法              |  MSE (归一化)  |  结论 \n');
    fprintf('----------------------------------------\n');
    fprintf('  1. HFC (均匀场)   |  %8.4f      |  (参考基准)\n', mse_hfc);
    fprintf('  2. LMS-ALE        |  %8.4f      |  %s\n', mse_lms, ...
        string(ifelse(mse_lms < mse_hfc, '更优', '相当/稍逊')));
    fprintf('----------------------------------------\n');
    fprintf('  * LMS 优势：计算量极低，无需参考通道，适合在线处理 *\n');
    fprintf('----------------------------------------\n');
end






%% ===================== 任务 1.1：降噪效果评估 (PSD & SNR) =====================
fprintf('\n===================== 开始执行任务 1.1：降噪评估 =====================\n');

% 1. 构建“原始数据” (Raw) 的 FieldTrip 结构
% 说明：因为代码流程中先做陷波才转FT格式，我们需要手动用 data_cali_Y/Z 重组一个 Raw 数据的结构
fprintf('正在构建原始数据(Raw)用于对比...\n');
data_raw_ft = data_notch_ft; % 借用现有的结构体壳子
data_combined_raw = zeros(128, size(data_cali_Y, 2));
for i = 1:64
    % 使用 deep_notch_filter 之前的变量 data_cali_Z 和 data_cali_Y
    data_combined_raw(2*i-1, :) = data_cali_Z(channelBYlayout(i), :); % Z轴
    data_combined_raw(2*i, :) = data_cali_Y(channelBYlayout(i), :);   % Y轴
end
data_raw_ft.trial{1} = data_combined_raw;

% 2. 频谱分析配置
cfg_freq = [];
cfg_freq.method = 'mtmfft';
cfg_freq.taper = 'hanning';
cfg_freq.output = 'pow';
cfg_freq.pad = 'nextpow2';
cfg_freq.foi = 1:0.5:100; % 关注 1-100Hz 范围，包含 17Hz 信号
cfg_freq.keeptrials = 'no';

fprintf('正在计算各阶段功率谱密度(PSD)...\n');
freq_raw   = ft_freqanalysis(cfg_freq, data_raw_ft);
freq_notch = ft_freqanalysis(cfg_freq, data_notch_ft);
freq_rls   = ft_freqanalysis(cfg_freq, data_rls_ft);
freq_hfc   = ft_freqanalysis(cfg_freq, data_hfc_ft);

% 3. 绘制 PSD 对比图
figure('Name', '任务1.1: 降噪效果评估 - 功率谱密度对比', 'Color', 'w');
% 计算所有通道的平均频谱
loglog(freq_raw.freq, mean(freq_raw.powspctrm), 'k', 'LineWidth', 1.0); hold on;
loglog(freq_notch.freq, mean(freq_notch.powspctrm), 'b', 'LineWidth', 1.2);
loglog(freq_rls.freq, mean(freq_rls.powspctrm), 'g', 'LineWidth', 1.5);
loglog(freq_hfc.freq, mean(freq_hfc.powspctrm), 'r', 'LineWidth', 1.5);

xline(17, '--m', 'Signal 17Hz'); % 标记信号频率
grid on;
legend({'Raw (仅校准)', 'Notched (陷波)', 'After RLS', 'After HFC'}, 'Location', 'southwest');
xlabel('Frequency (Hz)');
ylabel('Power Spectral Density (T^2/Hz)');
title('Mission 1: 降噪流程频谱对比 (全通道平均)');
xlim([1 60]); % 重点展示低频区域





% MSE 越低，说明波形越接近真实的 17Hz 发射信号

fprintf('正在计算 MSE (基于 Z-score 标准化波形对比)...\n');

% 确保 sync 长度与数据一致 (防止数据被裁剪过)
n_samples_current = size(data_raw_ft.trial{1}, 2);
if length(sync) >= n_samples_current
    sync_ref = sync(1:n_samples_current);
else
    error('Sync 信号长度小于当前数据长度，无法对齐比较。');
end


% 对标准信号进行 Z-score 标准化
sync_norm = (sync_ref - mean(sync_ref)) / std(sync_ref);

% 1. 定义 MSE 计算逻辑 (使用匿名函数封装，包含极性校正)
% 逻辑：标准化 -> 极性检测(翻转) -> 计算差异平方均值
calc_norm_mse = @(ft_data) compute_mse_internal(ft_data.trial{1}, sync_norm);



%% ===================== [新增] 绘制各阶段时域波形对比 =====================
fprintf('\n正在绘制各阶段波形对比图...\n');

% --- 设置绘图参数 ---
% 1. 选择一个观察通道
% 建议选择 Z 轴通道 (奇数)，通常信号较强
plot_ch_idx = 1; % 对应 label 中的第1个通道 (通常是 CH01)

% 2. 选择显示的时间窗口 (秒)
% 建议选一个短窗口 (如 0.5秒) 以看清 17Hz 正弦波的细节
% 如果选太长，正弦波会挤在一起看不清
plot_time_range = [0.0, 70]; % 显示第 1.0 秒到 1.5 秒的数据

% --- 准备绘图数据 ---
% 获取时间轴
t_vec = data_raw_ft.time{1};
% 找到对应时间窗口的索引
t_idx = t_vec >= plot_time_range(1) & t_vec <= plot_time_range(2);

% 获取通道名称
ch_name = data_raw_ft.label{plot_ch_idx};

% --- 开始绘图 ---
figure('Name', ['任务1.1: 降噪流程波形对比 - ' ch_name], 'Color', 'w', 'Position', [100, 50, 800, 1000]);

% 子图 1: Raw 原始数据
subplot(3, 2, 1);
plot(t_vec(t_idx), data_raw_ft.trial{1}(plot_ch_idx, t_idx), 'Color', [0.5 0.5 0.5]);
title(['1. Raw (原始数据) - ' ch_name]);
ylabel('Amp (T)'); grid on; axis tight;
% 可以在这里加一个注释，说明是否有漂移

% 子图 2: Notch 陷波后
subplot(3, 2, 2);
plot(t_vec(t_idx), data_notch_ft.trial{1}(plot_ch_idx, t_idx), 'b');
title('2. Notch (陷波 + 去尖峰后)');
ylabel('Amp (T)'); grid on; axis tight;

% 子图 3: RLS 降噪后
subplot(3, 2, 3);
plot(t_vec(t_idx), data_rls_ft.trial{1}(plot_ch_idx, t_idx), 'g');
title('3. RLS (参考降噪后 - 注意观察是否保留了正弦波)');
ylabel('Amp (T)'); grid on; axis tight;

% 子图 4: HFC 降噪后
subplot(3, 2, 4);
plot(t_vec(t_idx), data_hfc_ft.trial{1}(plot_ch_idx, t_idx), 'r');
title('4. HFC (均匀场校正后)');
ylabel('Amp (T)'); grid on; axis tight;

% 子图 4: lms 降噪后
subplot(3, 2, 5);
plot(t_vec(t_idx), data_lms_ft.trial{1}(plot_ch_idx, t_idx), 'r');
title('5. LMS');
ylabel('Amp (T)'); grid on; axis tight;

% 子图 5: 标准 Sync 信号 (参考答案)
subplot(3, 2, 6);
if exist('sync', 'var')
    % 确保 sync 长度匹配
    sync_disp = sync(1:length(t_vec));
    % 归一化 sync 以便观察 (因为 sync 是电压，单位不同)
    % 这里我们画原始的波形形状
    plot(t_vec(t_idx), sync_disp(t_idx), 'k', 'LineWidth', 1.5);
    title('5. Target (标准 Sync 信号 - 理想波形)');
    ylabel('Amp (V)'); grid on; axis tight;
else
    text(0.5, 0.5, 'Sync 变量丢失', 'HorizontalAlignment', 'center');
end

xlabel('Time (s)');
sgtitle(['Mission 1 降噪效果逐级对比 (Time: ' num2str(plot_time_range(1)) '-' num2str(plot_time_range(2)) 's)']);

fprintf('波形对比图已生成。请观察 RLS 和 HFC 步骤是否使波形更接近底部的 Sync 信号。\n');




% 2. 计算各阶段 MSE
mse_raw   = calc_norm_mse(data_raw_ft);
mse_notch = calc_norm_mse(data_notch_ft);
mse_rls   = calc_norm_mse(data_rls_ft);
mse_hfc   = calc_norm_mse(data_hfc_ft);
mse_lms   = calc_norm_mse(data_lms_ft);

% 5. 输出 MSE 结果表
fprintf('\n----------------------------------------\n');
fprintf('       Mission 1.1: MSE 评估结果 (相对于 Sync 信号)       \n');
fprintf('       * 指标说明：MSE 越低，波形还原度越高 (0=完美) *\n');
fprintf('----------------------------------------\n');
fprintf('  阶段              |  MSE (归一化)  |  优化程度 \n');
fprintf('----------------------------------------\n');
fprintf('  1. Raw (原始)     |  %8.4f      |     -\n', mse_raw);
fprintf('  2. Notch (陷波)   |  %8.4f      |  %+8.4f\n', mse_notch, mse_notch - mse_raw);
fprintf('  3. RLS (参考降噪) |  %8.4f      |  %+8.4f\n', mse_rls, mse_rls - mse_notch);
fprintf('  4. HFC (均匀场)   |  %8.4f      |  %+8.4f\n', mse_hfc, mse_hfc - mse_rls);
fprintf('  5. LMS (均匀场)   |  %8.4f      |  %+8.4f\n', mse_lms, mse_lms - mse_rls);
fprintf('----------------------------------------\n');
fprintf('  总优化 (Raw->HFC) :  %+8.4f (负值表示有效降噪)\n', mse_hfc - mse_raw);
fprintf('----------------------------------------\n');



%% ===================== [新增] 绘制各阶段频域(PSD)对比图 =====================
fprintf('\n正在绘制频域 PSD 对比图...\n');

% 1. 计算所有阶段的频谱 (如果之前没算过)
cfg_freq = [];
cfg_freq.method = 'mtmfft';
cfg_freq.taper = 'hanning';
cfg_freq.output = 'pow';
cfg_freq.pad = 'nextpow2';
cfg_freq.foi = 1:0.5:400; % 关注 0-400Hz (涵盖 17Hz 信号和 240/320Hz 噪音)
cfg_freq.keeptrials = 'no'; % 计算平均谱

% 检查变量是否存在，避免重复计算
if ~exist('freq_raw', 'var'), freq_raw = ft_freqanalysis(cfg_freq, data_raw_ft); end
if ~exist('freq_notch', 'var'), freq_notch = ft_freqanalysis(cfg_freq, data_notch_ft); end
if ~exist('freq_rls', 'var'), freq_rls = ft_freqanalysis(cfg_freq, data_rls_ft); end
if ~exist('freq_hfc', 'var'), freq_hfc = ft_freqanalysis(cfg_freq, data_hfc_ft); end
% 如果有 ALE/LMS 结果，也加上
if exist('data_lms_ft', 'var'), freq_lms = ft_freqanalysis(cfg_freq, data_lms_ft); end

% 2. 绘图
figure('Name', '任务1: 降噪流程频域对比 (PSD)', 'Color', 'w', 'Position', [100, 100, 900, 600]);

% 使用半对数坐标 (Y轴对数)，因为功率谱范围很大
semilogy(freq_raw.freq, mean(freq_raw.powspctrm), 'Color', [0.7 0.7 0.7], 'LineWidth', 1); hold on;
semilogy(freq_notch.freq, mean(freq_notch.powspctrm), 'b', 'LineWidth', 1);
semilogy(freq_rls.freq, mean(freq_rls.powspctrm), 'g', 'LineWidth', 1.2);
semilogy(freq_hfc.freq, mean(freq_hfc.powspctrm), 'r', 'LineWidth', 1.2);

% 如果有 LMS 结果，用黑色粗线画
if exist('freq_lms', 'var')
    semilogy(freq_lms.freq, mean(freq_lms.powspctrm), 'k', 'LineWidth', 1.5);
    legend_str = {'Raw (原始)', 'Notch (陷波)', 'RLS (参考降噪)', 'HFC (均匀场)', 'LMS-ALE (自适应)'};
else
    legend_str = {'Raw (原始)', 'Notch (陷波)', 'RLS (参考降噪)', 'HFC (均匀场)'};
end

% 3. 标记关键频率
xline(17, '--m', 'Target 17Hz', 'LineWidth', 1.5);
xline(50, ':k', '50Hz Power');
xline(240, ':k', '240Hz Calib');
xline(320, ':k', '320Hz Calib');

% 4. 美化
grid on;
legend(legend_str, 'Location', 'northeast');
xlabel('Frequency (Hz)');
ylabel('Power Spectral Density (T^2/Hz)');
title('Mission 1: 全流程降噪效果频谱对比');
xlim([1 350]); % 显示到 350Hz 以查看标定信号是否去除

% 5. 局部放大图 (插图) - 专门看 17Hz 附近的细节
axes('Position',[.55 .55 .3 .3]) % 在右上角创建一个小坐标轴
box on;
semilogy(freq_raw.freq, mean(freq_raw.powspctrm), 'Color', [0.7 0.7 0.7]); hold on;
semilogy(freq_hfc.freq, mean(freq_hfc.powspctrm), 'r');
if exist('freq_lms', 'var'), semilogy(freq_lms.freq, mean(freq_lms.powspctrm), 'k'); end
xlim([10 25]); % 只看 10-25Hz
title('17Hz 信号细节');
grid on;

fprintf('频域对比图已生成。请检查:\n');
fprintf('  1. 240Hz/320Hz 处是否有深坑 (Notch效果)\n');
fprintf('  2. 17Hz 处的尖峰是否保留完好\n');
fprintf('  3. 低频 (1-10Hz) 噪声基线是否下降\n');




%% 辅助函数 (若之前未定义)
function out = ifelse(condition, true_val, false_val)
    if condition, out = true_val; else, out = false_val; end
end



%% 辅助函数定义
function data_cali = real_time_calibration(data, Fs, refFreq, targetPeak)
    % 实时校准函数
    nChannels = size(data, 1);
    N_samples = size(data, 2);
    
    % 生成参考信号
    t_signal = (0:N_samples-1) / Fs;
    reference_sin = sin(2*pi*refFreq*t_signal);
    reference_cos = cos(2*pi*refFreq*t_signal);
    
    % 设计FIR滤波器
    fir_order = 100;
    cutoff_freq = [refFreq-5, refFreq+5];
    b_fir = fir1(fir_order, cutoff_freq/(Fs/2), 'bandpass');
    
    % 实时低通滤波器参数
    lp_cutoff = 2;
    [b_lp, a_lp] = butter(2, lp_cutoff/(Fs/2));
    
    % 初始化变量
    data_cali = zeros(size(data));
    
    for ch = 1:nChannels
        % 应用FIR带通滤波器
        filtered_signal = filter(b_fir, 1, data(ch, :));
        
        % 数字锁相放大
        I_component = filtered_signal .* reference_sin;
        Q_component = filtered_signal .* reference_cos;
        
        % 低通滤波提取直流分量
        I_smoothed = filtfilt(b_lp, a_lp, I_component);
        Q_smoothed = filtfilt(b_lp, a_lp, Q_component);
        
        % 计算测量幅度
        measured_amplitude = 2 * sqrt(I_smoothed.^2 + Q_smoothed.^2);
        
        % 计算实时校准因子
        min_amplitude = targetPeak * 0.01;
        realtime_factors = targetPeak ./ max(measured_amplitude, min_amplitude);
        
        % 应用增益（补偿群延迟）
        group_delay = fir_order/2;
        if group_delay < length(realtime_factors)
            compensated_gain = [realtime_factors(group_delay+1:end), ...
                               realtime_factors(end)*ones(1, group_delay)];
        else
            compensated_gain = realtime_factors;
        end
        
        data_cali(ch, :) = data(ch, :) .* compensated_gain;
    end
    
    % 二次基线校准
    initial_values = data_cali(:, 1);
    data_cali = data_cali - initial_values;
end

function data_notched = deep_notch_filter(data, Fs, notch_freq)
    % 深度陷波滤波函数
    notch_bw = 10;
    fir_order = 400;
    
    % 计算归一化频率
    wn = [(notch_freq - notch_bw)/(Fs/2), (notch_freq + notch_bw)/(Fs/2)];
    
    % 设计FIR带阻滤波器
    b_notch = fir1(fir_order, wn, 'stop');
    
    % 级联多个滤波器以获得更深度的抑制
    data_notched = data;
    for cascade = 1:6
        temp_data = zeros(size(data_notched));
        for ch = 1:size(data_notched, 1)
            temp_data(ch, :) = filtfilt(b_notch, 1, data_notched(ch, :));
        end
        data_notched = temp_data;
    end
end



% 如果不想放在末尾，也可以将上面的 calc_norm_mse 调用改为直接的循环实现
function avg_mse = compute_mse_internal(data_mat, ref_norm)
    [n_ch, ~] = size(data_mat);
    mse_accum = 0;
    
    for ch = 1:n_ch
        sig = data_mat(ch, :);
        % 1. 通道数据标准化
        sig_norm = (sig - mean(sig)) / std(sig);
        
        % 2. 极性校正：计算相关性
        % 脑磁信号的方向取决于传感器位置，可能与电信号反相
        % 如果相关性为负，将信号翻转，否则 MSE 会因为反相而巨大
        if (sig_norm * ref_norm') < 0 
            sig_norm = -sig_norm;
        end
        
        % 3. 计算该通道的 MSE
        mse_accum = mse_accum + mean((sig_norm - ref_norm).^2);
    end
    
    % 返回所有通道的平均 MSE
    avg_mse = mse_accum / n_ch;
end



function data_cleaned = apply_ale_lms(data, Fs, delay_ms, M, mu)
    % APPLY_ALE_LMS 实现基于 NLMS 的自适应谱线增强器
    % 输入:
    %   data: [Channels x Time] 输入数据
    %   Fs: 采样率
    %   delay_ms: 延迟量 (毫秒)
    %   M: 滤波器阶数 (Taps)
    %   mu: 归一化步长 (建议 0.01 - 0.5)
    % 输出:
    %   data_cleaned: 提取出的周期性信号 (ALE输出)
    
    [n_ch, n_samples] = size(data);
    data_cleaned = zeros(n_ch, n_samples);
    
    % 将延迟转换为采样点数
    D = round(delay_ms / 1000 * Fs);
    
    % 正则化参数 (防止分母为0)
    epsilon = 1e-6; 
    
    fprintf('  LMS 进度: ');
    
    for ch = 1:n_ch
        x = data(ch, :); % 输入信号 (含噪声)
        y = zeros(1, n_samples); % 滤波器输出 (预测的信号)
        
        % LMS 权重初始化 (全零)
        w = zeros(M, 1);
        
        % 遍历时间点
        % 从 D+M 开始，确保有足够的数据构建输入向量
        for n = (D + M):n_samples
            % 1. 构建输入向量 (Delayed Input)
            % u(n) = [x(n-D), x(n-D-1), ..., x(n-D-M+1)]
            u = x(n - D : -1 : n - D - M + 1)'; 
            
            % 2. 计算滤波器输出 (预测值)
            y_curr = w' * u;
            
            % 3. 计算误差 (期望信号 - 预测值)
            % 期望信号 d(n) 就是当前的观测值 x(n)
            e = x(n) - y_curr;
            
            % 4. NLMS 权重更新
            % w(n+1) = w(n) + mu * e(n) * u(n) / (u'u + epsilon)
            u_power = u' * u + epsilon; % 输入信号的能量
            w = w + (mu / u_power) * e * u;
            
            % 5. 保存输出
            % y(n) 是信号成分，e(n) 是噪声成分
            y(n) = y_curr;
        end
        
        data_cleaned(ch, :) = y;
        
        % 简单的进度显示
        if mod(ch, 20) == 0
            fprintf('%d..', ch);
        end
    end
    fprintf(' 完成\n');
end