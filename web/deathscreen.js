$(document).ready(function() {

    /*
     * Realistic PQRST waveform — SVG viewBox "0 0 340 80", baseline y=55.
     * Each pattern has TWO full cycles (cycle2 = cycle1 offset by +340 on X)
     * so the <g id="ecg-scroll"> can scroll from 0 → -340 and loop seamlessly.
     *
     * One cycle = 340px wide  →  3 beats, each ~110px apart.
     * P wave  : small gentle bump  (+8px above baseline)
     * Q       : tiny dip           (+4px below)
     * R spike : sharp peak         (50px above baseline — main QRS complex)
     * S       : overshoot below    (7px below baseline)
     * T wave  : rounded hump       (11px above baseline)
     */
    const CYCLE_W = 340; // width of one full waveform cycle

    // ── beat geometry helpers ──────────────────────────────────────────────────
    function beat(ox, oy, rPeak) {
        // ox = x-offset of beat start, oy = baseline y, rPeak = R-peak y
        const s  = (rPeak > 30) ? 4 : 2;   // S overshoot scale (weaker = less)
        const tp = oy - Math.round((oy - rPeak) * 0.22);  // T-peak
        return [
            [ox+0,  oy],          // baseline lead-in start
            [ox+8,  oy],          // flat before P
            [ox+12, oy-5],        // P wave rise
            [ox+16, oy-8],        // P wave peak
            [ox+20, oy-5],        // P wave fall
            [ox+24, oy],          // PR segment
            [ox+28, oy+4],        // Q dip
            [ox+32, rPeak],       // R spike  ← main peak
            [ox+36, oy+7],        // S overshoot below baseline
            [ox+42, oy],          // return to baseline
            [ox+50, tp],          // T wave peak
            [ox+62, oy],          // T wave end
        ].map(p => p.join(',')).join(' ');
    }

    function buildCycle(offsetX, rPeak) {
        // 3 beats spaced 110px apart within the 340px window
        const b1 = beat(offsetX +   0, 55, rPeak);
        const b2 = beat(offsetX + 110, 55, rPeak);
        const b3 = beat(offsetX + 220, 55, rPeak);
        // trailing flat back to end of cycle
        const tail = `${offsetX + 282},55 ${offsetX + CYCLE_W},55`;
        return b1 + ' ' + b2 + ' ' + b3 + ' ' + tail;
    }

    const ECG_PATTERNS = {
        // strong: sharp R at y=5 (50px above baseline)
        strong: {
            c1: buildCycle(0,       5),
            c2: buildCycle(CYCLE_W, 5),
        },
        // weak: shallow R at y=25 (30px above baseline)
        weak: {
            c1: buildCycle(0,       25),
            c2: buildCycle(CYCLE_W, 25),
        },
        // flatline: straight horizontal
        flatline: {
            c1: `0,55 ${CYCLE_W},55`,
            c2: `${CYCLE_W},55 ${CYCLE_W * 2},55`,
        },
    };

    // ── state ──────────────────────────────────────────────────────────────────
    const answers = { breath: null, pulse: null };
    let transportAvailable = false;
    let transportRemaining = 0;
    let transportTicker = null;

    function applyDeathMode(mode) {
        const normalized = (mode === 'unconscious') ? 'unconscious' : 'dead';
        const status = $('#death-status-text');
        const timerLabel = $('#ds-timer-label');
        if (normalized === 'unconscious') {
            status.html(`<span class="ds-status-prefix">${window.ambT('ui_you_are', 'YOU ARE')}</span> <span class="ds-status-keyword">${window.ambT('ui_unconscious', 'UNCONSCIOUS')}</span>`);
            timerLabel.text(window.ambT('ui_unconscious', 'UNCONSCIOUS'));
        } else {
            status.html(`<span class="ds-status-prefix">${window.ambT('ui_you_are', 'YOU ARE')}</span> <span class="ds-status-keyword">${window.ambT('ui_dead', 'DEAD')}</span>`);
            timerLabel.text(window.ambT('ui_critical', 'CRITICAL'));
        }
    }

    function resetQuestions() {
        answers.breath = 'no'; // Default for auto-show
        answers.pulse  = 'no';
        $('.ds-choice').removeClass('selected-yes selected-no');
        $('#death-ecg-panel').removeClass('hidden'); // Ensure visible
        $('#ecg-mode-label').text('—');
        applyEcgPattern('flatline', false);
        stopTransportCountdown();
        updateTransportButton(false, 0);
    }

    function updateTransportButton(available, remaining) {
        transportAvailable = !!available;
        transportRemaining = Math.max(0, Number(remaining) || 0);
        const btn = $('#ds-btn-go-hospital');
        if (transportAvailable) {
            btn.prop('disabled', false).html(`<i class="fas fa-truck-medical"></i> ${window.ambT('ui_go_hospital_key', 'GO TO HOSPITAL [Y]')}`);
        } else {
            btn.prop('disabled', true).html(`<i class="fas fa-truck-medical"></i> ${window.ambT('ui_go_hospital_wait', 'GO TO HOSPITAL ({seconds}s) [Y]', { seconds: transportRemaining })}`);
        }
    }

    function stopTransportCountdown() {
        if (transportTicker) {
            clearInterval(transportTicker);
            transportTicker = null;
        }
    }

    function startTransportCountdown(seconds) {
        stopTransportCountdown();
        updateTransportButton(seconds <= 0, seconds);
        if (seconds <= 0) return;
        transportTicker = setInterval(() => {
            transportRemaining = Math.max(0, transportRemaining - 1);
            updateTransportButton(transportRemaining <= 0, transportRemaining);
            if (transportRemaining <= 0) {
                stopTransportCountdown();
            }
        }, 1000);
    }

    function applyEcgPattern(name, isActive) {
        const pat   = ECG_PATTERNS[name];
        const isFl  = (name === 'flatline');
        $('#ecg-line').attr('points',  pat.c1).toggleClass('flatline', isFl);
        $('#ecg-line2').attr('points', pat.c2).toggleClass('flatline', isFl);
        // pause scroll animation for flatline, run for active pulse
        $('#ecg-scroll').toggleClass('paused', isFl);
    }

    function applyVitals(breathing, pulse) {
        if (!pulse) {
            applyEcgPattern('flatline', false);
            $('#ecg-mode-label').text(window.ambT('ui_no_pulse_flatline', 'NO PULSE — FLATLINE'));
            return;
        }
        if (breathing && pulse) {
            applyEcgPattern('strong', true);
            $('#ecg-mode-label').text(window.ambT('ui_stable_vitals', 'STABLE VITALS'));
        } else {
            applyEcgPattern('weak', true);
            $('#ecg-mode-label').text(window.ambT('ui_weak_pulse', 'WEAK PULSE'));
        }
    }

    function markChoice(question, answer) {
        const yes = $(`.ds-choice[data-question="${question}"][data-answer="yes"]`);
        const no  = $(`.ds-choice[data-question="${question}"][data-answer="no"]`);
        yes.removeClass('selected-yes selected-no');
        no.removeClass('selected-yes selected-no');
        if (answer === 'yes') yes.addClass('selected-yes');
        else                  no.addClass('selected-no');
    }

    function maybeShowEcg() {
        $('#death-ecg-panel').removeClass('hidden');
        applyVitals(answers.breath === 'yes', answers.pulse === 'yes');
    }

    // ── button clicks ──────────────────────────────────────────────────────────
    $(document).on('click', '.ds-choice', function() {
        const question = $(this).data('question');
        const answer   = $(this).data('answer');
        if (!question || !answer) return;
        answers[question] = answer;
        markChoice(question, answer);
        maybeShowEcg();
    });

    $('#ds-btn-call-ems').on('click', function() {
        fetch(`https://${GetParentResourceName()}/amb_callEMS`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
    });

    $('#ds-btn-go-hospital').on('click', function() {
        if (!transportAvailable) return;
        fetch(`https://${GetParentResourceName()}/amb_goHospital`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
    });

    // ── NUI messages ───────────────────────────────────────────────────────────
    window.addEventListener('message', function(event) {
        const data = event.data;

        if (data.action === 'amb_toggleDeathScreen') {
            if (data.show) {
                $('#death-screen-container').addClass('visible');
                updateDeathTimer(data.time);
                applyDeathMode(data.mode);
                $('.ds-hint').removeClass('called');
                $('#hint-medical .ds-hint-text').text(window.ambT('ui_notify_medics', 'Notify Medics'));
                resetQuestions();
                maybeShowEcg();
                startTransportCountdown(Number(data.transportDelay) || 0);
            } else {
                $('#death-screen-container').removeClass('visible');
                resetQuestions();
            }

        } else if (data.action === 'amb_updateDeathTimer') {
            updateDeathTimer(data.time);

        } else if (data.action === 'amb_emsCalled') {
            $('#hint-medical').addClass('called');
            $('#hint-medical .ds-hint-text').text(window.ambT('ui_ems_notified', 'EMS Notified'));
            if (answers.breath !== null && answers.pulse !== null) {
                applyVitals(true, true);
            }
        } else if (data.action === 'amb_transportState') {
            if (data.available) {
                stopTransportCountdown();
                updateTransportButton(true, 0);
            } else {
                startTransportCountdown(Number(data.remaining) || 0);
            }
        }
    });
});

function updateDeathTimer(seconds) {
    if (seconds == null) return;
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    $('#death-timer').text(
        `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`
    );
}
