%% ===================== Trigger识别与Trial分割 =====================
% 这部分代码用于识别同步信号中的trigger，并将连续数data_filtered据分割为trials
% 适用于128通道双轴数据（64个Z轴通道 + 64个Y轴通道）

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

load("workspace2.mat")

fprintf('\n===================== Trigger识别与Trial分割 =====================\n');

data_filtered=data_proc;

%% 1. 参数设置
% 关键参数定义（可根据实际情况调整）
trigger_threshold = max(sync)/2;  % Trigger检测阈值
skip_samples_after_trigger = 5000;  % 检测到trigger后跳过的采样点数（防止重复检测）
fs = 4800;  % 采样率
trial_duration = 1.5;  % 每个trial的持续时间（秒）
pre_trigger_time = 0.1;  % trigger前的时间（秒）
post_trigger_time = 0.5;  % trigger后的时间（秒）

%% 2. Trigger检测
fprintf('检测trigger...\n');
n_samples = length(sync);
trigger_indices = [];  % 存储所有trigger位置
current_pos = 1;  % 当前搜索位置

% 第一阶段：寻找所有符合条件的trigger
while current_pos <= n_samples
    % 从当前位置开始找到第一个超过阈值的点
    trigger_idx = find(sync(current_pos:end) > trigger_threshold, 1);
    
    if isempty(trigger_idx)
        break;  % 没有找到更多trigger
    end
    
    % 计算全局索引并保存
    global_idx = current_pos + trigger_idx - 1;
    trigger_indices = [trigger_indices, global_idx];
    
    % 跳过当前trigger及后续一定数量的点（防止重复检测）
    current_pos = global_idx + skip_samples_after_trigger;
end

fprintf('检测到 %d 个trigger\n', length(trigger_indices));

% 显示前几个trigger的位置
if length(trigger_indices) > 0
    fprintf('前5个trigger位置（采样点）: ');
    fprintf('%d ', trigger_indices(1:min(5, length(trigger_indices))));
    fprintf('\n');
end

%% 3. 创建trial定义矩阵
fprintf('创建trial定义矩阵...\n');

% 计算trial的起点和终点（以采样点为单位）
pre_samples = round(pre_trigger_time * fs);  % trigger前的采样点数
post_samples = round(post_trigger_time * fs);  % trigger后的采样点数
trial_samples = pre_samples + post_samples;  % 每个trial的总采样点数

% 获取数据总长度
total_samples = size(data_filtered.trial{1}, 2);
fprintf('数据总长度: %d 个采样点 (约%.2f秒)\n', total_samples, total_samples/fs);

% 创建trial定义矩阵：[起点, 终点, 偏移量]
trials = [];

for i = 1:length(trigger_indices)
    % 计算trial起点（trigger前pre_samples个点）
    start_sample = trigger_indices(i) - pre_samples;
    
    % 计算trial终点
    end_sample = start_sample + trial_samples - 1;
    
    % 检查trial范围是否合法
    if start_sample < 1
        fprintf('警告: Trial %d 起点(%d) < 1，已跳过\n', i, start_sample);
        continue;
    end
    
    if end_sample > total_samples
        fprintf('警告: Trial %d 终点(%d) > 总长度(%d)，已跳过\n', i, end_sample, total_samples);
        continue;
    end
    
    % 保存trial定义
    trials = [trials; start_sample, end_sample, -pre_samples];  % trigger在trial中的偏移量
end

n_valid_trials = size(trials, 1);
fprintf('成功创建 %d 个有效的trial\n', n_valid_trials);

if n_valid_trials == 0
    fprintf('错误: 没有创建有效的trial！\n');
    fprintf('可能的原因：\n');
    fprintf('  1. trigger位置太靠前，没有足够的pre-trigger数据\n');
    fprintf('  2. trigger位置太靠后，没有足够的post-trigger数据\n');
    fprintf('  3. 数据长度不足\n');
    fprintf('建议的解决方案：\n');
    fprintf('  1. 减少pre_trigger_time（当前: %.2f秒)\n', pre_trigger_time);
    fprintf('  2. 减少post_trigger_time（当前: %.2f秒)\n', post_trigger_time);
    fprintf('  3. 检查trigger检测阈值\n');
    
    % 显示数据统计信息
    fprintf('\n数据统计信息：\n');
    fprintf('  数据总长度: %d 采样点 (%.2f秒)\n', total_samples, total_samples/fs);
    if length(trigger_indices) > 0
        fprintf('  第一个trigger位置: %d (数据开始后%.2f秒)\n', ...
            trigger_indices(1), trigger_indices(1)/fs);
        fprintf('  最后一个trigger位置: %d (数据开始后%.2f秒)\n', ...
            trigger_indices(end), trigger_indices(end)/fs);
    end
    
    return;  % 如果没有有效的trial，提前返回
end

%% 4. 分割数据为trials（适用于128通道双轴数据）
fprintf('分割数据为trials...\n');

% 初始化存储trial数据的cell数组
trial_data = cell(1, n_valid_trials);
trial_time = cell(1, n_valid_trials);
trial_triggers = cell(1, n_valid_trials);

% 获取数据维度信息
n_channels = size(data_filtered.trial{1}, 1);  % 应为128（64Z + 64Y）
fprintf('数据通道数: %d (应为128: 64Z + 64Y)\n', n_channels);

% 分割每个trial
for i = 1:n_valid_trials
    start_idx = trials(i, 1);
    end_idx = trials(i, 2);
    
    % 提取trial数据（所有128个通道）
    trial_data{i} = data_filtered.trial{1}(:, start_idx:end_idx);
    
    % 创建对应的时间向量（以秒为单位）
    trial_time{i} = (0:(end_idx-start_idx)) / fs + (-pre_trigger_time);
    
    % 提取对应的trigger信号
    trial_triggers{i} = sync(start_idx:end_idx);
    
end

%% 5. 更新data_filtered结构
fprintf('更新数据结构...\n');

% 保存原始的连续数据（可选）
if ~isfield(data_filtered, 'continuous_data')
    data_filtered.continuous_data = data_filtered.trial{1};
end
if ~isfield(data_filtered, 'continuous_time')
    data_filtered.continuous_time = data_filtered.time{1};
end
if ~isfield(data_filtered, 'continuous_sync')
    data_filtered.continuous_sync = sync;
end

% 更新为trial格式的数据
data_filtered.trial = trial_data;
data_filtered.time = trial_time;
data_filtered.sampleinfo = trials;  % 保存trial的起点和终点信息
data_filtered.triggers = trial_triggers;  % 保存每个trial的trigger信号

% 添加trial信息到结构体
data_filtered.cfg.trl = trials;
data_filtered.cfg.pre_trigger_time = pre_trigger_time;
data_filtered.cfg.post_trigger_time = post_trigger_time;
data_filtered.cfg.trial_duration = trial_duration;
data_filtered.cfg.n_trials = n_valid_trials;

%% 6. 验证和输出信息
fprintf('\n===================== Trial分割完成 =====================\n');
fprintf('Trial信息汇总：\n');
fprintf('  总trials数量: %d\n', n_valid_trials);
fprintf('  每个trial时长: %.2f 秒\n', trial_duration);
fprintf('  每个trial采样点数: %d\n', trial_samples);
fprintf('  Trigger前时间: %.2f 秒\n', pre_trigger_time);
fprintf('  Trigger后时间: %.2f 秒\n', post_trigger_time);
fprintf('  数据维度: %d通道 × %d时间点 × %dtrials\n', ...
    n_channels, trial_samples, n_valid_trials);

% 显示前几个trial的trigger位置
if n_valid_trials > 0
    fprintf('\n前5个trial的trigger位置信息：\n');
    for i = 1:min(5, n_valid_trials)
        start_sample = trials(i, 1);
        end_sample = trials(i, 2);
        trigger_offset = trials(i, 3);
        trigger_in_data = start_sample - trigger_offset;  % trigger在原始数据中的位置
        trigger_time_in_trial = -trigger_offset / fs;
        fprintf('  Trial %d: [%d - %d], trigger在trial中: %d采样点 (%.3f秒)\n', ...
            i, start_sample, end_sample, -trigger_offset, trigger_time_in_trial);
    end
end

% 检查是否有Z轴和Y轴通道标签
if isfield(data_filtered, 'label')
    z_channels = sum(contains(data_filtered.label, 'CH') & ~contains(data_filtered.label, 'Y'));
    y_channels = sum(contains(data_filtered.label, 'Y'));
    fprintf('\n通道信息：\n');
    fprintf('  Z轴通道数: %d\n', z_channels);
    fprintf('  Y轴通道数: %d\n', y_channels);
end



%% ===================== 任务 2.1：提高信噪比 (SNR) 分析 =====================
% 前置条件：必须先运行完 processing_mission2.m 的前半部分，
% 确保工作区中有分好段的数据结构体 data_filtered

fprintf('\n===================== 开始任务 2.1：AEF 与 ASSR 分析 =====================\n');

if ~exist('data_filtered', 'var')
    error('未找到 data_filtered 变量，请先运行 Trial 分割代码！');
end

%% --- [Part 1] AEF 分析 (时域叠加平均) ---
fprintf('1. 正在进行时域叠加平均 (计算 AEF)...\n');

% 1. 配置 ft_timelockanalysis
cfg_tl = [];
cfg_tl.covariance = 'no';        % 不需要计算协方差
cfg_tl.keeptrials = 'no';        % 直接计算平均值，不保留单次试次
cfg_tl.removemean = 'yes';       % 基线校正
cfg_tl.baseline   = [-0.2 0];    % 使用刺激前 200ms 作为基线

% 执行叠加平均
avg_aef = ft_timelockanalysis(cfg_tl, data_filtered);

% 2. 计算全球场功率 (Global Field Power, GFP)
% GFP 是所有通道的标准差，能反映整体脑反应的强度，不依赖于特定通道的选择
gfp = std(avg_aef.avg, 0, 1);

% 3. 绘制 AEF 波形图 (蝴蝶图 + GFP)
figure('Name', '任务 2.1: AEF (听觉诱发场) 时域分析', 'Color', 'w', 'Position', [100, 100, 1000, 600]);

% 子图1：蝴蝶图 (所有通道重叠)
subplot(2, 1, 1);
plot(avg_aef.time, avg_aef.avg, 'Color', [0.7 0.7 0.7]); hold on; % 灰色细线画所有通道
plot(avg_aef.time, gfp, 'k', 'LineWidth', 2); % 黑色粗线画 GFP
xline(0, '--r', 'Stimulus Onset');
xlabel('Time (s)'); ylabel('Amplitude (T)');
title(sprintf('AEF 叠加平均 (Trials = %d)', size(data_filtered.trial, 2)));
grid on; xlim([-0.2, 0.5]); % 聚焦 -0.2 到 0.5 秒

% 子图2：N100m 峰值检测与 SNR 计算
subplot(2, 1, 2);
plot(avg_aef.time, gfp, 'k', 'LineWidth', 1.5); hold on;

% 寻找 N100m (通常在 80ms - 150ms 之间)
n100_window = [0.08 0.15];
idx_window = avg_aef.time >= n100_window(1) & avg_aef.time <= n100_window(2);
[peak_amp, peak_idx_local] = max(gfp(idx_window));
% 还原全局索引
time_indices = find(idx_window);
peak_idx = time_indices(peak_idx_local);
peak_time = avg_aef.time(peak_idx);

% 寻找基线噪声水平 (-0.2 到 0s)
idx_baseline = avg_aef.time >= -0.2 & avg_aef.time <= 0;
baseline_noise = mean(gfp(idx_baseline)); % GFP 的基线均值近似噪声水平
baseline_std = std(gfp(idx_baseline));

% 标记峰值
plot(peak_time, peak_amp, 'ro', 'MarkerFaceColor', 'r');
text(peak_time, peak_amp*1.1, sprintf('N100m: %.2f ms', peak_time*1000));

% 计算并显示 SNR
aef_snr = peak_amp / baseline_std;
title(sprintf('GFP 放大图 & SNR 计算\nN100m 幅度: %.2e, 基线噪声: %.2e, SNR: %.2f', ...
    peak_amp, baseline_std, aef_snr));
xlabel('Time (s)'); ylabel('Global Field Power (T)');
grid on; xlim([-0.1, 0.4]);


%% --- [Part 2] ASSR 分析 (频域分析) ---
fprintf('\n2. 正在进行频域分析 (计算 ASSR)...\n');

% 1. 配置 ft_freqanalysis
cfg_freq = [];
cfg_freq.method = 'mtmfft';      % 多推测窗 FFT
cfg_freq.taper = 'hanning';      % 汉宁窗
cfg_freq.output = 'pow';         % 输出功率谱
cfg_freq.foi = 1:0.5:120;        % 关注 1-120Hz (包含 89Hz)
cfg_freq.keeptrials = 'no';      % 计算所有 Trial 的平均功率谱 (Induction)
% 注意：这里使用的是 "FFT then Average" 策略 (Induced Power)

% 执行频域分析
freq_assr = ft_freqanalysis(cfg_freq, data_filtered);

% 2. 绘制 ASSR 频谱图
figure('Name', '任务 2.1: ASSR (稳态响应) 频域分析', 'Color', 'w', 'Position', [150, 150, 1000, 500]);

% 计算所有通道的平均频谱
mean_spectrum = mean(freq_assr.powspctrm, 1);
log_spectrum = 10*log10(mean_spectrum); % 转为 dB 便于观察

plot(freq_assr.freq, mean_spectrum, 'b', 'LineWidth', 1.5); hold on;
xlabel('Frequency (Hz)'); ylabel('Power (T^2/Hz)');
title('全通道平均功率谱密度 (ASSR 检测)');
grid on; xlim([70 110]); % 聚焦 89Hz 附近

% 3. 计算 89Hz 处的 SNR
target_freq = 89;
neighbor_width = 2; % 左右邻域宽度 (Hz)

% 找到 89Hz 的索引
[~, idx_89] = min(abs(freq_assr.freq - target_freq));
power_89 = mean_spectrum(idx_89);

% 找到邻域噪声 (比如 85-87Hz 和 91-93Hz)
idx_noise_low = freq_assr.freq >= (target_freq - 2 - neighbor_width) & freq_assr.freq <= (target_freq - 2);
idx_noise_high = freq_assr.freq >= (target_freq + 2) & freq_assr.freq <= (target_freq + 2 + neighbor_width);
idx_noise = idx_noise_low | idx_noise_high;

power_noise = mean(mean_spectrum(idx_noise));
assr_snr_db = 10 * log10(power_89 / power_noise);

% 标记和显示
xline(target_freq, '--r', '89Hz Stim');
plot(freq_assr.freq(idx_89), power_89, 'ro', 'MarkerFaceColor', 'r');

% 在图上显示 SNR 结果
text_str = sprintf('ASSR @ 89Hz\nSignal Power: %.2e\nNoise Power: %.2e\nSNR: %.2f dB', ...
    power_89, power_noise, assr_snr_db);
text(target_freq+2, power_89, text_str, 'BackgroundColor', 'w', 'EdgeColor', 'k');

fprintf('分析完成。\n');
fprintf('  AEF N100m SNR: %.2f\n', aef_snr);
fprintf('  ASSR 89Hz SNR: %.2f dB\n', assr_snr_db);



%% ===================== [新增] 任务 2.1 进阶：主动提高 SNR 的策略 =====================
fprintf('\n===================== 执行 SNR 增强策略 (滤波 + 坏段剔除) =====================\n');

% 策略 1: 坏段剔除 (Bad Trial Rejection)
% 原理：计算每个 Trial 的幅度极差(Range)或方差(Var)。
% 如果某 Trial 的波动幅度超过了整体平均水平的 3 倍标准差，就视为“伪影试次”并剔除。

fprintf('1. 正在执行坏段剔除 (Artifact Rejection)...\n');

% 计算每个 Trial 的统计量
n_trials_all = length(data_filtered.trial);
trial_max_vals = zeros(n_trials_all, 1);

for i = 1:n_trials_all
    % 计算该 Trial 所有通道的最大峰峰值 (Max - Min)
    % 只要有一个通道爆表，整个 Trial 就不要了
    trial_data = data_filtered.trial{i};
    range_per_channel = max(trial_data, [], 2) - min(trial_data, [], 2);
    trial_max_vals(i) = max(range_per_channel);
end

% 设定阈值 (自动适应)
% 剔除极其离谱的极值后计算均值和标准差，防止阈值被本身很大的伪影拉高
clean_subset = trial_max_vals(trial_max_vals < median(trial_max_vals)*5);
threshold = mean(clean_subset) + 3 * std(clean_subset);

% 找出坏试次
bad_trials_idx = find(trial_max_vals > threshold);
good_trials_idx = setdiff(1:n_trials_all, bad_trials_idx);

fprintf('  阈值设定: %.2e T\n', threshold);
fprintf('  检测到 %d 个坏试次，保留 %d / %d 个好试次\n', ...
    length(bad_trials_idx), length(good_trials_idx), n_trials_all);

% [关键步骤] 筛选数据
cfg_select = [];
cfg_select.trials = good_trials_idx;
data_clean = ft_selectdata(cfg_select, data_filtered);


% 策略 2: 针对性滤波 (Targeted Filtering)
% AEF 和 ASSR 的频率成分完全不同，必须“分而治之”才能获得最高 SNR。

fprintf('\n2. 正在构建针对性滤波数据...\n');

% --- A. 为 AEF 准备的低通滤波数据 ---
% AEF (N100m) 主要能量集中在 0-30Hz，高频全是噪声
cfg_aef = [];
cfg_aef.lpfilter = 'yes';
cfg_aef.lpfreq = 40;        % 40Hz 低通 (保留 N100m，切断肌电干扰)
cfg_aef.hpfilter = 'yes';
cfg_aef.hpfreq = 1;         % 1Hz 高通 (去除极低频漂移)
data_for_aef = ft_preprocessing(cfg_aef, data_clean);
fprintf('  [AEF数据] 已应用 1-40Hz 带通滤波\n');

% --- B. 为 ASSR 准备的窄带滤波数据 ---
% ASSR 集中在 89Hz，我们只需要关注这个窄带，切断低频 alpha/beta 波和高频干扰
cfg_assr = [];
cfg_assr.bpfilter = 'yes';
cfg_assr.bpfreq = [80 100]; % 80-100Hz 带通 (紧紧包围 89Hz)
data_for_assr = ft_preprocessing(cfg_assr, data_clean);
fprintf('  [ASSR数据] 已应用 80-100Hz 窄带滤波\n');

fprintf('===================== SNR 增强完成 =====================\n');

% 更新后续分析使用的数据变量
% 注意：之后的 AEF 分析请使用 data_for_aef
%       之后的 ASSR 分析请使用 data_for_assr



%% ===================== 任务 2.2：计算最少试次 (Bootstrap 分析) =====================
fprintf('\n===================== 开始任务 2.2：最少试次 Bootstrap 分析 =====================\n');

% 检查数据是否存在 (需要上一节生成的针对性滤波数据)
if ~exist('data_for_aef', 'var') || ~exist('data_for_assr', 'var')
    error('缺少滤波后的数据 data_for_aef 或 data_for_assr，请先运行任务 2.1 的增强代码！');
end

%% 1. 参数设置
n_bootstraps = 30;     % 重抽样次数 (建议 20-50 次，次数越多曲线越平滑但越慢)
max_trials = length(data_for_aef.trial); % 最大可用 Trial 数
step_size = 2;         % 步长 (为了速度，每隔 2 个 Trial 算一次，如 1, 3, 5...)
trial_steps = 1:step_size:max_trials;

% 预分配存储矩阵 [Trial数量 x Bootstrap次数]
snr_history_aef = zeros(length(trial_steps), n_bootstraps);
snr_history_assr = zeros(length(trial_steps), n_bootstraps);

fprintf('正在进行重抽样计算 (Total Trials=%d, Bootstraps=%d)...\n', max_trials, n_bootstraps);
fprintf('这可能需要一点时间，请稍候...\n');

%% 2. 准备数据矩阵 (加速运算)
% 将 FieldTrip 的 cell 数据转换为 3D 矩阵 [Channels x Time x Trials] 以利用 GPU/CPU 加速
% AEF 数据矩阵
aef_matrix = cat(3, data_for_aef.trial{:}); 
time_vec = data_for_aef.time{1};
% ASSR 数据矩阵
assr_matrix = cat(3, data_for_assr.trial{:});

%% 3. 执行循环 (AEF - N100m)
% 定义 N100m 时间窗和基线窗
idx_n100 = time_vec >= 0.08 & time_vec <= 0.15;
idx_base = time_vec >= -0.2 & time_vec <= 0;

for k = 1:n_bootstraps
    for i = 1:length(trial_steps)
        n = trial_steps(i);
        
        % 1. 随机抽取 n 个 Trial 的索引
        rand_idx = randperm(max_trials, n);
        
        % 2. 叠加平均 (Time-locked Average)
        % 对选中的 n 个 Trial 求平均，再对所有通道求 GFP (std)
        avg_data = mean(aef_matrix(:, :, rand_idx), 3);
        gfp = std(avg_data, 0, 1); % Global Field Power
        
        % 3. 计算 SNR
        peak_amp = max(gfp(idx_n100)); % 信号：N100 峰值
        noise_level = std(gfp(idx_base)); % 噪声：基线标准差
        
        snr_history_aef(i, k) = peak_amp / noise_level;
    end
    if mod(k, 5) == 0, fprintf('  AEF Bootstrap: %d / %d 完成\n', k, n_bootstraps); end
end

%% 4. 执行循环 (ASSR - 89Hz)
% 对于 ASSR，"叠加后FFT" (Evoked) 提升 SNR 的效率最高
% 频率轴相关
n_samples = size(assr_matrix, 2);
freq_axis = (0:n_samples-1) * (fs / n_samples);
target_freq = 89;
[~, idx_89] = min(abs(freq_axis - target_freq)); % 找到 89Hz 的索引
% 邻域噪声索引 (例如 85-87Hz 和 91-93Hz)
idx_noise = (freq_axis >= 85 & freq_axis <= 87) | (freq_axis >= 91 & freq_axis <= 93);

for k = 1:n_bootstraps
    for i = 1:length(trial_steps)
        n = trial_steps(i);
        
        % 1. 随机抽取
        rand_idx = randperm(max_trials, n);
        
        % 2. 先时域平均 (Evoked response)
        % 这是消除背景噪声最有效的方法
        avg_time_data = mean(assr_matrix(:, :, rand_idx), 3);
        
        % 3. 后频域变换 (FFT)
        % 对平均后的波形做 FFT，然后计算全通道平均功率
        fft_data = abs(fft(avg_time_data, [], 2));
        mean_spectrum = mean(fft_data, 1); % 通道平均
        
        % 4. 计算 SNR
        signal_power = mean_spectrum(idx_89);
        noise_power = mean(mean_spectrum(idx_noise));
        
        snr_history_assr(i, k) = signal_power / noise_power;
    end
    if mod(k, 5) == 0, fprintf('  ASSR Bootstrap: %d / %d 完成\n', k, n_bootstraps); end
end

%% 5. 绘图与结果判定
% 计算均值和标准差用于绘图
mean_snr_aef = mean(snr_history_aef, 2);
std_snr_aef = std(snr_history_aef, 0, 2);
mean_snr_assr = mean(snr_history_assr, 2);
std_snr_assr = std(snr_history_assr, 0, 2);

figure('Name', '任务 2.2: 最少试次判定 (SNR vs Trials)', 'Color', 'w', 'Position', [100, 100, 1000, 500]);

% --- 子图 1: AEF SNR 曲线 ---
subplot(1, 2, 1);
% 绘制误差带
fill([trial_steps, fliplr(trial_steps)], ...
    [(mean_snr_aef-std_snr_aef)', fliplr((mean_snr_aef+std_snr_aef)')], ...
    [0.8 0.8 1], 'EdgeColor', 'none'); hold on;
plot(trial_steps, mean_snr_aef, 'b.-', 'LineWidth', 1.5);

% 判定阈值 (例如 SNR > 3)
threshold_aef = 3.0; 
yline(threshold_aef, 'r--', 'Threshold SNR=3');
% 寻找达到阈值的点
idx_pass = find(mean_snr_aef > threshold_aef, 1);
if ~isempty(idx_pass)
    min_trials_aef = trial_steps(idx_pass);
    xline(min_trials_aef, 'g--', sprintf('Min Trials: %d', min_trials_aef));
    plot(min_trials_aef, mean_snr_aef(idx_pass), 'go', 'MarkerFaceColor', 'g');
else
    min_trials_aef = NaN;
    title('AEF: 未达到稳定阈值');
end

xlabel('Number of Trials'); ylabel('SNR (Peak/Baseline_STD)');
title(sprintf('AEF (N100m) SNR 增长曲线\nEst. Min Trials: %d', min_trials_aef));
grid on;

% --- 子图 2: ASSR SNR 曲线 ---
subplot(1, 2, 2);
% 绘制误差带
fill([trial_steps, fliplr(trial_steps)], ...
    [(mean_snr_assr-std_snr_assr)', fliplr((mean_snr_assr+std_snr_assr)')], ...
    [1 0.8 0.8], 'EdgeColor', 'none'); hold on;
plot(trial_steps, mean_snr_assr, 'r.-', 'LineWidth', 1.5);

% 判定阈值 (ASSR 比较强，可以设高一点，例如 SNR > 3倍 或 5倍)
% 注意：这里计算的是幅度比，功率比的话数值会更大
threshold_assr = 3.0; 
yline(threshold_assr, 'b--', 'Threshold Ratio=3');
% 寻找达到阈值的点
idx_pass_assr = find(mean_snr_assr > threshold_assr, 1);
if ~isempty(idx_pass_assr)
    min_trials_assr = trial_steps(idx_pass_assr);
    xline(min_trials_assr, 'g--', sprintf('Min Trials: %d', min_trials_assr));
    plot(min_trials_assr, mean_snr_assr(idx_pass_assr), 'go', 'MarkerFaceColor', 'g');
else
    min_trials_assr = NaN;
    title('ASSR: 未达到稳定阈值');
end

xlabel('Number of Trials'); ylabel('SNR (Signal/Noise Ratio)');
title(sprintf('ASSR (89Hz) SNR 增长曲线\nEst. Min Trials: %d', min_trials_assr));
grid on;

%% 6. 输出最终结论
fprintf('\n===================== 最终结论 =====================\n');
fprintf('基于 Bootstrap (%d 次重复) 的分析结果：\n', n_bootstraps);
fprintf('1. AEF (N100m 瞬态反应):\n');
if ~isnan(min_trials_aef)
    fprintf('   - 达到 SNR > %.1f 所需的最少试次为: %d 次\n', threshold_aef, min_trials_aef);
else
    fprintf('   - 在当前 Trial 数量下未达到预设 SNR 阈值，建议增加实验时长。\n');
end

fprintf('2. ASSR (89Hz 稳态反应):\n');
if ~isnan(min_trials_assr)
    fprintf('   - 达到 SNR > %.1f 所需的最少试次为: %d 次\n', threshold_assr, min_trials_assr);
else
    fprintf('   - 未达到阈值。可能需要检查 89Hz 滤波带宽或噪声水平。\n');
end
fprintf('==================================================\n');