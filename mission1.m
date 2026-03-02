


clear;
close all;
clc;

% 1. 首先添加 FieldTrip 路径
addpath('./fieldtrip-20251218/');

% 2. 将 FieldTrip 路径移到后面，让 MATLAB 内置函数优先
fieldtrip_path = './fieldtrip-20251218/';
rmpath(fieldtrip_path);
addpath(fieldtrip_path, '-end');  % '-end' 参数将路径添加到末尾

% 3. 验证路径顺序
which iscolumn -all
ft_defaults;

load("workspace.mat");



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
plot(t_snippet, data_cali_Z(check_idx, 1:tmp_trip_idx), 'Color', [0 0 0], 'LineWidth', 2); hold on;
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
ale_order = 45;         
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
cfg_freq.foi = 1:0.5:100; % 关注 0-400Hz (涵盖 17Hz 信号和 240/320Hz 噪音)
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





%% ===================== [新增] 进阶评估：频域 SNR 与 噪声抑制 =====================
fprintf('\n===================== 进阶指标评估 (SNR & Noise Floor) =====================\n');

% --- 参数设置 ---
target_f        = 17;   % 目标信号频率 (Hz)
signal_bw       = 0.5;  % 信号峰值带宽 +/- Hz (视分辨率而定，0.5Hz足够覆盖峰值)
noise_local_bw  = 2.0;  % 局部噪声计算带宽 +/- Hz (用于计算SNR的分母)
noise_floor_rng = [1, 45]; % 宽带噪声地板计算范围 (Hz)

% 封装一个计算函数 (Local Function)
% 输入: FieldTrip的freq结构体, 标签名
% 输出: 结构体包含 SNR, 信号功率, 噪声底功率
calc_metrics = @(ft_freq, label) calculate_spectral_metrics(ft_freq, ...
    target_f, signal_bw, noise_local_bw, noise_floor_rng, label);

% 1. 对各阶段数据进行计算
% 注意：利用脚本之前生成的 freq_raw, freq_notch, freq_rls, freq_hfc
% 这里的 powspctrm 维度通常是 [nChans x nFreqs]，我们取平均(mean)代表整体水平
metrics_raw   = calc_metrics(freq_raw,   'Raw (原始)');
metrics_notch = calc_metrics(freq_notch, 'Notch (陷波)');
metrics_rls   = calc_metrics(freq_rls,   'RLS (参考)');
metrics_hfc   = calc_metrics(freq_hfc,   'HFC (均匀场)');

% 如果有 LMS 结果，也计算
if exist('freq_lms', 'var')
    metrics_lms = calc_metrics(freq_lms, 'LMS (自适应)');
    all_metrics = [metrics_raw, metrics_notch, metrics_rls, metrics_hfc, metrics_lms];
else
    all_metrics = [metrics_raw, metrics_notch, metrics_rls, metrics_hfc];
end

% 2. 输出对比表格
fprintf('\n--------------------------------------------------------------------------------------\n');
fprintf('  阶段              | SNR_17Hz (dB) |  信号保留率(%%) | 宽带底噪(1-45Hz) | 底噪衰减(dB) \n');
fprintf('--------------------------------------------------------------------------------------\n');

base_signal_pow = metrics_raw.signal_pow; % 以原始数据的信号功率为基准
base_noise_floor = metrics_raw.noise_floor; % 以原始数据的底噪为基准

for i = 1:length(all_metrics)
    m = all_metrics(i);
    
    % 计算相对于 Raw 的变化
    sig_preservation = (m.signal_pow / base_signal_pow) * 100; % 信号保留率
    noise_attenuation = 10 * log10(base_noise_floor / m.noise_floor); % 底噪衰减 (正值代表降噪)
    
    fprintf('  %-16s  |  %6.2f       |  %8.1f %%     |  %.2e      |  %6.2f \n', ...
        m.name, m.snr_db, sig_preservation, m.noise_floor, noise_attenuation);
end
fprintf('--------------------------------------------------------------------------------------\n');
fprintf('指标说明:\n');
fprintf('1. SNR_17Hz: 越大越好。反映 17Hz 信号在邻近噪声中的凸显程度。\n');
fprintf('2. 信号保留率: 越接近 100%% 越好。反映降噪是否误伤了 17Hz 主波。\n');
fprintf('3. 底噪衰减: 正值越大越好。反映宽带背景噪声降低了多少 dB。\n');
fprintf('--------------------------------------------------------------------------------------\n');


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



% --- 辅助计算函数 (放在脚本最后或作为独立函数) ---
function res = calculate_spectral_metrics(ft_freq, target_f, sig_bw, noise_bw, floor_rng, name)
    % 获取频率轴和功率谱(全通道平均)
    f_axis = ft_freq.freq;
    P_mean = mean(ft_freq.powspctrm, 1); % [1 x nFreqs]
    
    % 1. 提取信号功率 (Target Freq 附近的峰值积分或最大值)
    idx_sig = f_axis >= (target_f - sig_bw) & f_axis <= (target_f + sig_bw);
    signal_pow = max(P_mean(idx_sig)); % 取峰值点作为信号强度
    
    % 2. 提取局部噪声 (Target Freq 左右两侧，不包含信号本身)
    % 左侧带: [target - noise_bw, target - sig_bw]
    % 右侧带: [target + sig_bw, target + noise_bw]
    idx_noise_local = (f_axis >= (target_f - noise_bw) & f_axis < (target_f - sig_bw)) | ...
                      (f_axis > (target_f + sig_bw) & f_axis <= (target_f + noise_bw));
    noise_local_pow = mean(P_mean(idx_noise_local));
    
    % 计算 SNR (dB)
    snr_db = 10 * log10(signal_pow / noise_local_pow);
    
    % 3. 提取宽带底噪 (Noise Floor)
    % 范围 floor_rng，但要剔除 17Hz 信号区 和 50Hz 工频区(如果有)
    idx_floor = f_axis >= floor_rng(1) & f_axis <= floor_rng(2);
    % 剔除信号区
    idx_floor(idx_sig) = 0; 
    % 简单剔除 50Hz (49-51)
    idx_50hz = f_axis >= 49 & f_axis <= 51;
    idx_floor(idx_50hz) = 0;
    
    noise_floor_val = mean(P_mean(idx_floor));
    
    % 打包结果
    res.name = name;
    res.snr_db = snr_db;
    res.signal_pow = signal_pow;
    res.noise_floor = noise_floor_val;
end




