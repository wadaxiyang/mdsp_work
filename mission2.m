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
pre_trigger_time = 0.2;  % trigger前的时间（秒）
post_trigger_time = 1.5;  % trigger后的时间（秒）


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

%% ===================== 任务 2.1: AEF (N100m) 修正版 =====================
fprintf('\n===================== 开始 AEF (N100m) 修正分析 =====================\n');

% 修正版预处理：使用 FIR 滤波器避免不稳
fprintf('正在进行 1-40Hz 带通滤波 (FIR模式)...\n');

cfg_proc = [];
cfg_proc.bpfilter = 'yes';
cfg_proc.bpfreq = [1 40];    
% [关键修改] 改用 FIR 滤波器，它是永远稳定的
cfg_proc.bpfilttype = 'firws'; 
% [建议] 使用 fft 加速计算，否则 FIR 会比较慢
cfg_proc.usefftfilt = 'yes';   

% 执行滤波
data_aef_clean = ft_preprocessing(cfg_proc, data_filtered);

% 2. 叠加平均 & 强制基线校正
cfg_tl = [];
cfg_tl.covariance = 'no';
cfg_tl.keeptrials = 'no'; 
cfg_tl.removemean = 'yes';   % 去除均值
% cfg_tl.baseline   = [-0.2 -0.06]; % [关键] 强制将 -0.2s 到 0s 的平均值拉回 0点
cfg_tl.baseline   = [-0.2 -0.0]; % [关键] 强制将 -0.2s 到 0s 的平均值拉回 0点
avg_aef = ft_timelockanalysis(cfg_tl, data_aef_clean);

% 3. 计算 GFP (Global Field Power)
gfp = std(avg_aef.avg, 0, 1);

% 4. 绘图
figure('Name', 'AEF (N100m) 最终结果', 'Color', 'w', 'Position', [100, 100, 1000, 600]);

% 子图1: 蝴蝶图 (所有通道)
subplot(2, 1, 1);
plot(avg_aef.time, avg_aef.avg, 'Color', [0.6 0.6 0.6 0.5]); hold on; % 灰色半透明
plot(avg_aef.time, gfp, 'k', 'LineWidth', 1.5); % 叠加 GFP
xline(0, '-k'); yline(0, '-k'); % 坐标轴
xline(0.1, '--b', 'Exp. N100m'); % 预期的 N100m 位置
title('AEF 蝴蝶图 (1-40Hz Bandpass)');
xlabel('Time (s)'); ylabel('Amplitude');
grid on; xlim([-0.1, 0.4]); 
% 此时 Y 轴应该在 0 附近震荡，数量级应该大幅减小

% 子图2: GFP 与 真正的 N100m 峰值
subplot(2, 1, 2);
plot(avg_aef.time, gfp, 'k', 'LineWidth', 2); hold on;

% 在 0.08s - 0.15s (80-150ms) 之间寻找最大值，这才是 N100m
n100_window = [0.08 0.15]; 
idx_win = avg_aef.time >= n100_window(1) & avg_aef.time <= n100_window(2);
[peak_amp, peak_idx_local] = max(gfp(idx_win));
time_vals = avg_aef.time(idx_win);
peak_time = time_vals(peak_idx_local);

% 在 -0.1s - 0s 之间计算基线噪声水平
idx_base = avg_aef.time >= -0.2 & avg_aef.time <= -0.06;
noise_level = mean(gfp(idx_base)); 

% 标记峰值
plot(peak_time, peak_amp, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 8);
text(peak_time, peak_amp, sprintf('  N100m: %.3fs', peak_time), 'FontSize', 12);

% 计算真实的 SNR
real_snr = peak_amp / noise_level;

title(sprintf('GFP 分析\nN100m Amp: %.2e | Baseline Noise: %.2e | Real SNR: %.2f', ...
    peak_amp, noise_level, real_snr));
xlabel('Time (s)'); ylabel('Global Field Power');
grid on; xlim([-0.1, 0.4]);

fprintf('AEF 分析完成。N100m 峰值时间: %.3f s, SNR: %.2f\n', peak_time, real_snr);


%% --- [Part 2] ASSR 分析 (修正版：Evoked Power 策略) ---
fprintf('\n2. 正在进行频域分析 (计算 ASSR - Evoked Strategy)...\n');

% === 修正1：重新分割数据，覆盖完整的刺激时长 ===
% 注意：为了获得最佳 ASSR，建议取 0.2s 到 1.2s (避开起始的瞬态反应，覆盖稳态)
% 但由于你之前的 segmentation 只有 0.5s，如果你不想重新跑 segmentation，
% 这里的效果会受限。强烈建议将上文的 segmentation 改为 post_trigger_time = 1.2;
% 假设你已经修改了 segmentation 长度...

% 1. 先进行时域叠加平均 (Time-Lock Average)
% 这步操作能极大消除非锁相的背景噪声
cfg_tl = [];
cfg_tl.covariance = 'no';
cfg_tl.keeptrials = 'no'; 
cfg_tl.removemean = 'yes';
cfg_tl.baseline   = [-0.1 0]; 
avg_assr_time = ft_timelockanalysis(cfg_tl, data_filtered);

% 2. 截取稳态时间窗 (仅对有效信号段做 FFT)
% 我们只取刺激开始后稳定的一段，例如 0s 到 1s (或者 0.2s 到 1.0s)
cfg_select = [];
cfg_select.latency = [0 1.0]; % 仅分析 0~1秒的数据
avg_assr_stable = ft_selectdata(cfg_select, avg_assr_time);

% 3. 再进行频域分析 (FFT)
cfg_freq = [];
cfg_freq.method = 'mtmfft';      
cfg_freq.taper = 'boxcar';       % 对于锁相的周期信号，boxcar (矩形窗) 通常能保持最尖锐的峰
cfg_freq.output = 'pow';        
cfg_freq.pad = 4;                % 补零以获得更平滑的频谱曲线
cfg_freq.foi = 1:0.5:120;        
cfg_freq.keeptrials = 'no';      

% 对“平均后的时域波形”做 FFT
freq_assr = ft_freqanalysis(cfg_freq, avg_assr_stable);

% 4. 绘制 ASSR 频谱图
figure('Name', '任务 2.1: ASSR (Evoked Power) 分析', 'Color', 'w');

% 计算所有通道的平均频谱
mean_spectrum = mean(freq_assr.powspctrm, 1);
% 转换为对数坐标通常更容易观察
plot(freq_assr.freq, mean_spectrum, 'b', 'LineWidth', 1.5); hold on;

% 标记 89Hz
xline(89, '--r', '89Hz Stim');
xlabel('Frequency (Hz)'); ylabel('Power (T^2/Hz)');
title('ASSR 诱发响应 (FFT of Time-Averaged Data)');
grid on; xlim([80 100]); % 放大观察 80-100Hz

% 计算 SNR (峰值 / 邻域均值)
target_idx = dsearchn(freq_assr.freq', 89);
noise_idx = [dsearchn(freq_assr.freq', 87) dsearchn(freq_assr.freq', 91)];
signal_power = mean_spectrum(target_idx);
noise_power = mean(mean_spectrum([noise_idx(1):target_idx-2, target_idx+2:noise_idx(2)]));

fprintf('修正后的 ASSR 分析结果：\n');
fprintf('  89Hz 信号功率: %.2e\n', signal_power);
fprintf('  邻域噪声功率: %.2e\n', noise_power);
fprintf('  SNR: %.2f dB\n', 10*log10(signal_power/noise_power));





%% ===================== 任务 2.1: ASSR 深度救援版 (Smart Channel Selection) =====================
fprintf('\n===================== 开始 ASSR 深度救援分析 =====================\n');

% 1. 预处理：陷波滤波去除 50Hz 基频和 100Hz 谐波
% 这一步至关重要，必须把图上那个 100Hz 的巨峰杀掉，否则它会污染整个频谱
cfg_pre = [];
cfg_pre.dftfilter = 'yes';
cfg_pre.dftfreq = [50 100 150]; % 去除工频及其谐波
% 此时我们可以稍微放宽一点带通，为了观察整体底噪
cfg_pre.bpfilter = 'yes';
cfg_pre.bpfreq = [70 120];      
data_notched = ft_preprocessing(cfg_pre, data_filtered);

% 2. 时域叠加平均 (Time-Lock)
% 保持你的 Evoked 策略，这是对的
cfg_tl = [];
cfg_tl.covariance = 'no';
cfg_tl.keeptrials = 'no'; 
cfg_tl.removemean = 'yes';
cfg_tl.baseline   = [-0.1 0]; 
avg_assr_time = ft_timelockanalysis(cfg_tl, data_notched);

% 3. 截取稳态窗口 (避开起始的瞬态反应)
% 选取 0.2s - 1.0s (假设你的 Trial 长度足够)
cfg_select = [];
cfg_select.latency = [0.2 1.0]; 
avg_assr_stable = ft_selectdata(cfg_select, avg_assr_time);

% 4. 频域分析 (使用 Hanning 窗抑制泄漏)
cfg_freq = [];
cfg_freq.method = 'mtmfft';      
cfg_freq.taper = 'hanning';      % <--- 改回 Hanning，防止 100Hz 噪声泄漏
cfg_freq.output = 'pow';        
cfg_freq.pad = 10;               % <--- 大量补零，让频谱曲线更平滑，定位更准
cfg_freq.foi = 70:0.1:110;       % 高分辨率扫描
cfg_freq.keeptrials = 'no';      
freq_assr = ft_freqanalysis(cfg_freq, avg_assr_stable);

% 5. 关键步骤：智能通道选择 (而不是全通道平均！)
% 我们需要找到 89Hz 反应最强的那个通道，而不是被这 128 个通道稀释

% 找到 89Hz 在频率轴上的索引
[~, idx_89] = min(abs(freq_assr.freq - 89));

% 提取所有通道在 89Hz 处的功率值
power_at_89 = freq_assr.powspctrm(:, idx_89);

% 找到功率最大的前 5 个通道
[sorted_power, sort_idx] = sort(power_at_89, 'descend');
top5_channels = sort_idx(1:5);
best_channel_label = freq_assr.label{top5_channels(1)};

fprintf('检测到 89Hz 反应最强的通道: %s (Power: %.2e)\n', best_channel_label, sorted_power(1));
fprintf('将仅使用 Top 5 通道进行平均分析...\n');

% 6. 绘图：对比“全通道平均”和“Top-5 通道”
figure('Name', 'ASSR 救援分析: 全局 vs 局部', 'Color', 'w', 'Position', [100, 100, 1000, 600]);

% --- 子图1: Top 5 通道的平均频谱 (这就是你要的结果) ---
subplot(2,1,1);
% 提取 Top 5 通道的频谱并平均
top5_spectrum = mean(freq_assr.powspctrm(top5_channels, :), 1);
plot(freq_assr.freq, top5_spectrum, 'r', 'LineWidth', 2); hold on;
xline(89, '--k', 'Target 89Hz');
title(sprintf('Top 5 最强通道平均 (最佳通道: %s)', best_channel_label));
xlabel('Frequency (Hz)'); ylabel('Power (T^2/Hz)');
grid on; xlim([80 100]);
% 标出峰值
[p_max, i_max] = max(top5_spectrum);
f_max = freq_assr.freq(i_max);
text(f_max, p_max, sprintf('Peak: %.1fHz', f_max), 'VerticalAlignment', 'bottom');

% --- 子图2: 全通道平均 (复现你之前的问题) ---
subplot(2,1,2);
all_mean_spectrum = mean(freq_assr.powspctrm, 1);
plot(freq_assr.freq, all_mean_spectrum, 'k', 'LineWidth', 1); hold on;
xline(89, '--r');
title('全通道平均 (Global Average) - 信号被稀释');
xlabel('Frequency (Hz)'); ylabel('Power (T^2/Hz)');
grid on; xlim([80 100]);

% 7. 输出信噪比
% 在 Top 5 谱上计算 SNR
noise_window_idx = (freq_assr.freq >= 86 & freq_assr.freq <= 88) | ...
                   (freq_assr.freq >= 90 & freq_assr.freq <= 92);
signal_power = top5_spectrum(idx_89);
noise_power = mean(top5_spectrum(noise_window_idx));
snr_db = 10 * log10(signal_power / noise_power);

fprintf('\n=== 最终结果 ===\n');
fprintf('ASSR (Top 5 Channels) SNR: %.2f dB\n', snr_db);
if snr_db > 3
    fprintf('结论: 成功检测到 ASSR 信号！\n');
else
    fprintf('结论: 信号依然微弱。可能原因：Trigger 抖动严重或受试者反应微弱。\n');
end


%%

data_assr_clean=data_notched;

%% ===================== 任务 2.2: 最少试次分析 (Bootstrap) =====================
fprintf('\n===================== 开始最少试次 Bootstrap 分析 =====================\n');

% === 参数设置 ===
n_bootstraps = 50;        % 每个点重复抽样 50 次
step_size = 5;            % 每次增加 5 个试次
snr_threshold_aef = 1.0;  % AEF 的阈值 (能看见信号)
snr_threshold_assr = 7.5; % ASSR 的阈值 (清晰信号)

% --- 准备数据 (转换为矩阵以加速) ---
% 1. AEF 数据准备
% 提取数据矩阵: [Channels x Time x Trials]
trials_aef_mat = cat(3, data_aef_clean.trial{:});
time_vec = data_aef_clean.time{1};
n_trials_total = size(trials_aef_mat, 3);
trial_steps = 10:step_size:n_trials_total; % 横坐标：试次数量

% AEF 的时间窗索引
idx_n100 = time_vec >= 0.08 & time_vec <= 0.12;     % 信号窗
idx_base = time_vec >= -0.2 & time_vec <= -0.06;    % 噪声窗 (避开伪影)

% 2. ASSR 数据准备
% 提取数据矩阵
trials_assr_mat = cat(3, data_assr_clean.trial{:});
% 自动寻找 ASSR 最强通道 (使用之前的逻辑)
% 为了简化计算，我们先计算一次全平均，找到最强通道索引
avg_temp = mean(trials_assr_mat, 3);
fft_temp = abs(fft(avg_temp, [], 2));
freq_axis = linspace(0, 4800, size(fft_temp, 2));
[~, idx_89] = min(abs(freq_axis - 89));
[~, best_ch_idx] = max(fft_temp(:, idx_89));
fprintf('ASSR 分析将使用最佳通道: %d\n', best_ch_idx);

% ASSR 的频率索引
idx_noise_low = (freq_axis >= 86 & freq_axis <= 88);
idx_noise_high = (freq_axis >= 90 & freq_axis <= 92);

% --- 开始循环计算 (这也需要一点时间) ---
snr_curve_aef = zeros(length(trial_steps), 2);  % [Mean, Std]
snr_curve_assr = zeros(length(trial_steps), 2); % [Mean, Std]

fprintf('正在进行计算 (Max Trials = %d)...\n', n_trials_total);

for i = 1:length(trial_steps)
    n = trial_steps(i);
    temp_snr_aef = zeros(n_bootstraps, 1);
    temp_snr_assr = zeros(n_bootstraps, 1);
    
    for b = 1:n_bootstraps
        % 随机抽取 n 个索引
        rand_idx = randperm(n_trials_total, n);
        
        % === 计算 AEF SNR ===
        % 1. 时域平均
        avg_aef_data = mean(trials_aef_mat(:, :, rand_idx), 3);
        % 2. 计算 GFP
        gfp = std(avg_aef_data, 0, 1);
        % 3. 计算 SNR
        signal = max(gfp(idx_n100));
        noise = mean(gfp(idx_base));
        temp_snr_aef(b) = signal / noise;
        
        % === 计算 ASSR SNR (Evoked 策略) ===
        % 1. 时域平均 (只取最佳通道)
        avg_assr_data = mean(trials_assr_mat(best_ch_idx, :, rand_idx), 3);
        % 2. 截取稳态部分 (0.2s - 1.0s) 进行 FFT
        % 假设采样率 4800，对应索引范围
        t_start = dsearchn(time_vec', 0.2);
        t_end = dsearchn(time_vec', 1.0);
        stable_data = avg_assr_data(t_start:t_end);
        
        % 3. FFT
        L = length(stable_data);
        Y = abs(fft(stable_data));
        P2 = Y/L;
        P1 = P2(1:floor(L/2)+1);
        P1(2:end-1) = 2*P1(2:end-1);
        f = 4800*(0:(L/2))/L;
        
        % 4. 计算 SNR (89Hz / 邻域)
        [~, i_89] = min(abs(f - 89));
        sig_pow = P1(i_89);
        % 简单的邻域噪声估算
        noise_pow = mean(P1([i_89-3:i_89-1, i_89+1:i_89+3])); 
        temp_snr_assr(b) = sig_pow / noise_pow; % 幅度比
    end
    
    % 记录平均值和标准差
    snr_curve_aef(i, :) = [mean(temp_snr_aef), std(temp_snr_aef)];
    snr_curve_assr(i, :) = [mean(temp_snr_assr), std(temp_snr_assr)];
    
    if mod(i, 5) == 0, fprintf('已完成 %d / %d 步...\n', i, length(trial_steps)); end
end

% --- 绘图与结果判定 ---
figure('Name', '最少试次判定', 'Color', 'w', 'Position', [100, 100, 1000, 500]);

% AEF 绘图
subplot(1, 2, 1);
errorbar(trial_steps, snr_curve_aef(:,1), snr_curve_aef(:,2), 'b-o', 'LineWidth', 1.5);
yline(snr_threshold_aef, 'r--', 'Detect Limit (SNR=1)');
xlabel('Number of Trials'); ylabel('SNR'); title('AEF (N100m) Stability');
grid on;
% 寻找交叉点
idx_pass_aef = find(snr_curve_aef(:,1) > snr_threshold_aef, 1);
if ~isempty(idx_pass_aef)
    min_aef = trial_steps(idx_pass_aef);
    xline(min_aef, 'g--', sprintf('Min: %d', min_aef));
else
    min_aef = NaN;
end

% ASSR 绘图
subplot(1, 2, 2);
errorbar(trial_steps, snr_curve_assr(:,1), snr_curve_assr(:,2), 'r-o', 'LineWidth', 1.5);
yline(snr_threshold_assr, 'b--', 'Stable Limit (SNR=3)');
xlabel('Number of Trials'); ylabel('SNR'); title('ASSR (89Hz) Stability');
grid on;
% 寻找交叉点
idx_pass_assr = find(snr_curve_assr(:,1) > snr_threshold_assr, 1);
if ~isempty(idx_pass_assr)
    min_assr = trial_steps(idx_pass_assr);
    xline(min_assr, 'g--', sprintf('Min: %d', min_assr));
else
    min_assr = NaN;
end

fprintf('\n=== 分析结论 ===\n');
fprintf('1. AEF (N100m): 达到可检测水平 (SNR>1) 最少需要: %d 个试次\n', min_aef);
fprintf('2. ASSR (89Hz): 达到稳定水平 (SNR>3) 最少需要: %d 个试次\n', min_assr);