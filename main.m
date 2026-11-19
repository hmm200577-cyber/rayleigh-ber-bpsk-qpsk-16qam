%% Part 0: Setup
clear; clc; close all;
rng(1);
N = 1e6;                         % number of bits per SNR point
assert(mod(N,4) == 0, 'N must be a multiple of 4 (needed for 16-QAM)');
SNR_dB  = 0:2:30;
SNR_lin = 10.^(SNR_dB/10);       % linear Eb/N0
Eb = 1;                          % normalized bit energy
N0 = Eb ./ SNR_lin;              % one N0 per SNR point
BER_bpsk  = zeros(size(SNR_dB));
BER_qpsk  = zeros(size(SNR_dB));
BER_16qam = zeros(size(SNR_dB));
disp(table(SNR_dB', SNR_lin', N0', 'VariableNames', {'SNR_dB','SNR_lin','N0'}));        % check

%% Part 1: Bits and BPSK mapping
bits = randi([0 1], 1, N);       % random bit stream (row vector)
x    = map_bpsk(bits, Eb);       % BPSK symbols
% check
fprintf('Fraction of ones      : %.4f  (expect ~0.5)\n', mean(bits));
fprintf('Average symbol power  : %.4f  (expect Eb = %.1f)\n', mean(abs(x).^2), Eb);
fprintf('Unique symbol values  : %s   (expect -1 and +1)\n', mat2str(unique(x)));
fprintf('First 8 bits          : %s\n', mat2str(bits(1:8)));
fprintf('First 8 symbols       : %s\n', mat2str(x(1:8)));

%% Part 2: Channel generation
h = gen_channel(N);
% check
fprintf('Var of hr          : %.4f  (expect 0.5)\n', var(real(h)));
fprintf('Var of hi          : %.4f  (expect 0.5)\n', var(imag(h)));
fprintf('Mean of |h|^2      : %.4f  (expect 1)\n',   mean(abs(h).^2));

figure('Name','Part 2: channel check');
subplot(1,2,1);
histogram(abs(h), 100, 'Normalization', 'pdf'); hold on;
r = linspace(0, max(abs(h)), 500);
plot(r, 2*r.*exp(-r.^2), 'r', 'LineWidth', 1.5);   % Rayleigh pdf with E[A^2] = 1
xlabel('|h|'); ylabel('pdf'); title('Amplitude vs Rayleigh pdf');
legend('simulated', 'theory'); grid on;

subplot(1,2,2);
histogram(mod(angle(h), 2*pi), 50, 'BinLimits', [0 2*pi], 'Normalization', 'pdf'); hold on;
yline(1/(2*pi), 'r', 'LineWidth', 1.5);            % uniform pdf on [0, 2*pi]
xlabel('phase (rad)'); ylabel('pdf'); title('Phase vs uniform pdf');
xlim([0 2*pi]); grid on;

%% Part 3: Noise generation
test_idx = [1 6 11 16];          % 0, 10, 20, 30 dB
fprintf('\nPart 3 check:\n');
fprintf('SNR_dB | N0/2 (expected) | var(nc) | var(ns) | mean(nc) | mean(ns)\n');
for k = test_idx
    n = gen_noise(N, N0(k));
    fprintf('%6d | %15.5f | %7.5f | %7.5f | %8.5f | %8.5f\n', ...
        SNR_dB(k), N0(k)/2, var(real(n)), var(imag(n)), mean(real(n)), mean(imag(n)));
end

%% Part 4: Received signal
% (1) Noiseless check: y = h.*x, then dividing by h must give x back
y0    = h .* x;
x_eq0 = y0 ./ h;
fprintf('\nPart 4 check:\n');
fprintf('Max |x_eq - x| with no noise : %.3e  (expect ~1e-16)\n', max(abs(x_eq0 - x)));

% (2) With noise at 10 dB (index 6): y = h.*x + n
k = 6;
n = gen_noise(N, N0(k));
y = h .* x + n;
x_eq = y ./ h;                       % equalized symbols = x + n./h

fprintf('Mean |y|^2 at %d dB          : %.4f  (expect Eb*E|h|^2 + N0 = %.4f)\n', ...
    SNR_dB(k), mean(abs(y).^2), Eb + N0(k));
fprintf('Mean |x_eq - x|^2 at %d dB   : %.4f  (much larger than N0 = %.4f)\n', ...
    SNR_dB(k), mean(abs(x_eq - x).^2), N0(k));

%% Part 5: BPSK receiver (one SNR point)
% (1) No noise: BER must be exactly 0
b_hat0 = demap_bpsk(y0 ./ h);
errs0  = sum(b_hat0 ~= bits);
fprintf('\nPart 5 check:\n');
fprintf('Errors with no noise : %d  (expect 0)\n', errs0);

% (2) With noise at 10 dB (y and x_eq from Part 4)
b_hat = demap_bpsk(x_eq);
ber10 = mean(b_hat ~= bits);

g = SNR_lin(k);                              % Eb/N0 at k (10 dB)
ber10_theory = 0.5 * (1 - sqrt(g/(1+g)));    % BPSK over Rayleigh
fprintf('BER at %d dB         : %.5f\n', SNR_dB(k), ber10);
fprintf('Theory at %d dB      : %.5f\n', SNR_dB(k), ber10_theory);

%% Part 6: BER loop (BPSK)
for k = 1:numel(SNR_dB)
    bits  = randi([0 1], 1, N);          % new bits
    x     = map_bpsk(bits, Eb);          % BPSK symbols
    h     = gen_channel(N);              % new channel (one sample per symbol)
    n     = gen_noise(N, N0(k));         % noise for this SNR
    y     = h .* x + n;                  % received signal
    b_hat = demap_bpsk(y ./ h);          % equalize + hard decision
    BER_bpsk(k) = mean(b_hat ~= bits);   % bit error rate
end

% Theory
BER_bpsk_rayleigh = 0.5 * (1 - sqrt(SNR_lin ./ (1 + SNR_lin)));   % BPSK/QPSK, Rayleigh
BER_bpsk_awgn     = 0.5 * erfc(sqrt(SNR_lin));                    % BPSK, AWGN only

plot_ber(SNR_dB, BER_bpsk, BER_bpsk_rayleigh, BER_bpsk_awgn, 'BPSK');

disp(table(SNR_dB', BER_bpsk', BER_bpsk_rayleigh', ...
    'VariableNames', {'SNR_dB','Simulated','Theory'}));

%% Part 7: QPSK
% Check 1: mapping table
bits_t = [0 0  0 1  1 1  1 0];
x_t    = map_qpsk(bits_t, Eb);
labels = {'00','01','11','10'};
fprintf('\nPart 7 check:\n');
for i = 1:4
    fprintf('bits %s -> %+.0f %+.0fj\n', labels{i}, real(x_t(i)), imag(x_t(i)));
end

% Check 2: power and no-noise BER
bits = randi([0 1], 1, N);
x    = map_qpsk(bits, Eb);
Ns   = numel(x);
fprintf('Average symbol power : %.4f  (expect 2*Eb = %.1f)\n', mean(abs(x).^2), 2*Eb);

h = gen_channel(Ns);
b_hat0 = demap_qpsk((h .* x) ./ h);
fprintf('Errors with no noise : %d  (expect 0)\n', sum(b_hat0 ~= bits));

% BER loop
for k = 1:numel(SNR_dB)
    bits  = randi([0 1], 1, N);
    x     = map_qpsk(bits, Eb);
    h     = gen_channel(numel(x));
    n     = gen_noise(numel(x), N0(k));
    y     = h .* x + n;
    b_hat = demap_qpsk(y ./ h);
    BER_qpsk(k) = mean(b_hat ~= bits);
end

%% Part 8: 16-QAM
d = sqrt(0.4*Eb);
% Check 1: mapping against the figure (levels in units of d)
tests = [0 0 0 0;  0 1 0 1;  1 1 1 1;  1 0 1 0;  0 0 1 0;  1 1 0 0];
fprintf('\nPart 8 check 1 (mapping):\n');
for i = 1:size(tests,1)
    xt = map_16qam(tests(i,:), Eb) / d;
    fprintf('bits %s -> I=%+d, Q=%+d\n', sprintf('%d', tests(i,:)), round(real(xt)), round(imag(xt)));
end

% Check 2: power and noiseless BER
bits = randi([0 1], 1, N);
x    = map_16qam(bits, Eb);
fprintf('Average symbol power : %.4f  (expect 4*Eb = %.1f)\n', mean(abs(x).^2), 4*Eb);

h = gen_channel(numel(x));
fprintf('Errors with no noise (fading) : %d  (expect 0)\n', ...
    sum(demap_16qam((h .* x) ./ h, Eb) ~= bits));

% Check 3: AWGN only (h = 1) against theory, validates mapper + demapper
awgn_idx = find(SNR_dB <= 12);
BER_awgn = zeros(size(awgn_idx));
for m = 1:numel(awgn_idx)
    kk    = awgn_idx(m);
    bits  = randi([0 1], 1, N);
    x     = map_16qam(bits, Eb);
    y     = x + gen_noise(numel(x), N0(kk));
    BER_awgn(m) = mean(demap_16qam(y, Eb) ~= bits);
end
a = sqrt(0.4 * SNR_lin(awgn_idx));
BER_awgn_th = 3/8*erfc(a) + 1/4*erfc(3*a) - 1/8*erfc(5*a);

% Rayleigh BER loop
for k = 1:numel(SNR_dB)
    bits  = randi([0 1], 1, N);
    x     = map_16qam(bits, Eb);
    h     = gen_channel(numel(x));
    n     = gen_noise(numel(x), N0(k));
    y     = h .* x + n;
    b_hat = demap_16qam(y ./ h, Eb);
    BER_16qam(k) = mean(b_hat ~= bits);
end

% Average each erfc term over the fading
g1 = 0.4*SNR_lin;  g3 = 9*g1;  g5 = 25*g1;
rf = @(g) 1 - sqrt(g ./ (1 + g));              % E[erfc(sqrt(g)*|h|)]
BER_16qam_th = 3/8*rf(g1) + 1/4*rf(g3) - 1/8*rf(g5);

% 16-QAM theory over AWGN only, for the full SNR range
BER_16qam_awgn = 3/8*erfc(sqrt(g1)) + 1/4*erfc(3*sqrt(g1)) - 1/8*erfc(5*sqrt(g1));

% QPSK: BER against SNR (QPSK per-bit theory is the same as BPSK)
plot_ber(SNR_dB, BER_qpsk, BER_bpsk_rayleigh, BER_bpsk_awgn, 'QPSK');

% 16-QAM: BER against SNR
plot_ber(SNR_dB, BER_16qam, BER_16qam_th, BER_16qam_awgn, '16-QAM');

%% Part 9: Final comparison
figure('Name','Final comparison');
semilogy(SNR_dB, BER_bpsk,  'bo-', 'LineWidth', 1.5); hold on;
semilogy(SNR_dB, BER_qpsk,  'gs-', 'LineWidth', 1.5);
semilogy(SNR_dB, BER_16qam, 'm^-', 'LineWidth', 1.5);
semilogy(SNR_dB, BER_bpsk_rayleigh, 'k--', 'LineWidth', 1);       % BPSK/QPSK theory
semilogy(SNR_dB, BER_16qam_th,      'k-.', 'LineWidth', 1);       % 16-QAM theory
grid on; xlabel('E_b/N_0 (dB)'); ylabel('Bit error rate'); ylim([1e-5 1]);
title('BER over Rayleigh flat fading: BPSK, QPSK, 16-QAM');
legend('BPSK (sim)', 'QPSK (sim)', '16-QAM (sim)', ...
       'BPSK/QPSK (theory)', '16-QAM (theory)', 'Location', 'southwest');

%% constellation plots
show_constellation(map_bpsk (randi([0 1], 1, 5000),  Eb), Eb, 15, 'BPSK',   3);
show_constellation(map_qpsk (randi([0 1], 1, 10000), Eb), Eb, 15, 'QPSK',   3);
show_constellation(map_16qam(randi([0 1], 1, 20000), Eb), Eb, 25, '16-QAM', 4);

%%  Local functions (must stay at the end of the file)

function plot_ber(snr_db, ber_sim, ber_rayleigh, ber_awgn, name)
% One BER figure with the same style for every modulation scheme
%   snr_db       : Eb/N0 in dB
%   ber_sim      : simulated BER over Rayleigh fading
%   ber_rayleigh : theoretical BER over Rayleigh fading
%   ber_awgn     : theoretical BER over AWGN only
%   name         : 'BPSK', 'QPSK' or '16-QAM'
    figure('Name', [name ' BER']);
    semilogy(snr_db, ber_sim,      'bo-', 'LineWidth', 1.5); hold on;
    semilogy(snr_db, ber_rayleigh, 'r--', 'LineWidth', 1.5);
    semilogy(snr_db, ber_awgn,     'k:',  'LineWidth', 1.5);
    grid on; xlabel('E_b/N_0 (dB)'); ylabel('BER'); ylim([1e-5 1]);
    title([name ' over Rayleigh flat fading']);
    legend('Simulated (Rayleigh)', 'Theory (Rayleigh)', 'Theory (AWGN)', 'Location', 'southwest');
end

function x = map_bpsk(bits, Eb)
% 0 -> -sqrt(Eb), 1 -> +sqrt(Eb)
    x = sqrt(Eb) * (2*bits - 1);
end

function b_hat = demap_bpsk(x_eq)
% Decision with threshold 0 on the real part
    b_hat = real(x_eq) > 0;
end

function h = gen_channel(N)
% hr, hi ~ N(0, 1/2)  ->  |h| is Rayleigh, phase is uniform, E[|h|^2] = 1
    hr = sqrt(1/2) * randn(1, N);
    hi = sqrt(1/2) * randn(1, N);
    h  = hr + 1j*hi;
end

function n = gen_noise(N, N0)
% nc, ns ~ N(0, N0/2) each  ->  total noise variance E[|n|^2] = N0
    nc = sqrt(N0/2) * randn(1, N);
    ns = sqrt(N0/2) * randn(1, N);
    n  = nc + 1j*ns;
end

function x = map_qpsk(bits, Eb)
% Gray QPSK: b0 -> I, b1 -> Q, (0 -> -1, 1 -> +1), scaled so Es = 2*Eb
    b0 = bits(1:2:end);
    b1 = bits(2:2:end);
    x  = sqrt(Eb) * ((2*b0 - 1) + 1j*(2*b1 - 1));
end

function bits_hat = demap_qpsk(x_eq)
% Threshold 0 on I and Q separately
    bits_hat = zeros(1, 2*numel(x_eq));
    bits_hat(1:2:end) = real(x_eq) > 0;     % b0
    bits_hat(2:2:end) = imag(x_eq) > 0;     % b1
end

function x = map_16qam(bits, Eb)
    d   = sqrt(0.4*Eb);
    lut = [-3 -1 3 1];                    % index = 2*first_bit + second_bit + 1
    b   = reshape(bits, 4, []);           % one column per symbol
    I   = lut(2*b(1,:) + b(2,:) + 1);
    Q   = lut(2*b(3,:) + b(4,:) + 1);
    x   = d * (I + 1j*Q);
end

function bits_hat = demap_16qam(x_eq, Eb)
% Thresholds at -2d, 0, +2d on each axis
    d   = sqrt(0.4*Eb);
    r_I = real(x_eq) / d;
    r_Q = imag(x_eq) / d;
    bits_hat = zeros(1, 4*numel(x_eq));
    bits_hat(1:4:end) = r_I > 0;
    bits_hat(2:4:end) = abs(r_I) < 2;
    bits_hat(3:4:end) = r_Q > 0;
    bits_hat(4:4:end) = abs(r_Q) < 2;
end

function show_constellation(x, Eb, snr_db, name, lim)
%   1) ideal transmitted symbols
%   2) received signal y = h*x + n
%   3) after channel inversion y/h

%   x       : transmitted symbols
%   Eb      : bit energy
%   snr_db  : Eb/N0 in dB
    Ns = numel(x);
    N0 = Eb / 10^(snr_db/10);
    h = sqrt(1/2) * (randn(1, Ns) + 1j*randn(1, Ns));
    n = sqrt(N0/2) * (randn(1, Ns) + 1j*randn(1, Ns));
    y    = h .* x + n;        % received, before inversion
    y_eq = y ./ h;            % after channel inversion
    ideal = unique(round(x, 6));   % ideal constellation points
    % Ideal points with their Gray bit labels
    bps      = log2(numel(ideal));
    all_bits = dec2bin(0:2^bps-1) - '0';
    all_bits_row = reshape(all_bits.', 1, []);
    switch bps
        case 1, ideal_sym = map_bpsk (all_bits_row, Eb);
        case 2, ideal_sym = map_qpsk (all_bits_row, Eb);
        case 4, ideal_sym = map_16qam(all_bits_row, Eb);
    end
    figure('Name', [name ' constellation'], 'Position', [100 100 1300 450]);

    % Panel 1: ideal symbols
    subplot(1,3,1);
    plot(real(ideal_sym), imag(ideal_sym), 'rx', 'MarkerSize', 10, 'LineWidth', 2);
    hold on;
    for i = 1:numel(ideal_sym)
        text(real(ideal_sym(i)) + 0.04*lim, imag(ideal_sym(i)) + 0.08*lim, ...
             sprintf('%d', all_bits(i,:)), 'FontSize', 10, 'FontWeight', 'bold');
    end
    grid on; axis equal; xlim([-lim lim]); ylim([-lim lim]);
    xlabel('I'); ylabel('Q');
    title([name ': ideal symbols (Gray bits)']);

    % Panel 2: received before channel inversion
    subplot(1,3,2);
    plot(real(y), imag(y), '.', 'MarkerSize', 8, 'Color', [0 0.35 0.7]);
    grid on; axis equal; xlim([-lim lim]); ylim([-lim lim]);
    xlabel('I'); ylabel('Q');
    title('Received y = hx + n (before inversion)');

    % Panel 3: after channel inversion
    subplot(1,3,3);
    h1 = plot(real(y_eq), imag(y_eq), '.', 'MarkerSize', 8, 'Color', [0 0.35 0.7]);
    hold on;
    h2 = plot(real(ideal), imag(ideal), 'rx', 'MarkerSize', 10, 'LineWidth', 2);
    grid on; axis equal; xlim([-lim lim]); ylim([-lim lim]);
    xlabel('I'); ylabel('Q');
    title('After channel inversion y/h');
    legend([h1 h2], 'Equalised samples', 'Ideal symbols', 'Location', 'northeast');
    sgtitle(sprintf('%s, E_b/N_0 = %g dB', name, snr_db));
end
