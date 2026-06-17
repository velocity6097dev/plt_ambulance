window.addEventListener('message', function(event) {
    if (event.data.action === 'amb_openDiagnosisUI') {
        if ($('#diagnosis-container').is(':hidden')) {
            $('#diagnosis-container').removeClass('hidden').fadeIn();
            $('#diagnosis-info-panel').hide();
            currentOpenedPart = null;
        }
        
        pharmacyData.isEMS = event.data.isEMS; // Share EMS status
        pharmacyData.isDowned = event.data.isDowned; // Share Downed status

        // Store dot positions and initial injury state
        if (event.data.dots) {
            updateDots(event.data.dots);
        }
        if (event.data.injuries) {
            updateDots(event.data.injuries);
        }

        // Refresh the currently selected part if info panel is visible
        if ($('#diagnosis-info-panel').is(':visible') && currentOpenedPart) {
            refreshPartDetail(currentOpenedPart);
        }
    } else if (event.data.action === 'amb_updateDiagnosisDots') {
        updateDots(event.data.dots);
    } else if (event.data.action === 'amb_receiveInjuries') {
        // Real-time damage recognition update
        updateDots(event.data.injuries);
        
        // If the info panel is open, refresh it so buttons/levels update instantly
        if ($('#diagnosis-info-panel').is(':visible') && currentOpenedPart) {
            refreshPartDetail(currentOpenedPart);
        }
    } else if (event.data.action === 'amb_refreshDiagnosisPart') {
        refreshPartDetail(event.data.part);
    } else if (event.data.action === 'amb_startBulletMinigame') {
        startBulletMinigame(event.data.targetSrc, event.data.part);
    } else if (event.data.action === 'amb_startBPMinigame') {
        startBPMinigame(event.data.targetSrc, event.data.part);
    } else if (event.data.action === 'amb_startBandageMinigame') {
        startBandageMinigame(event.data.targetSrc, event.data.part);
    } else if (event.data.action === 'amb_startClampMinigame') {
        startClampMinigame(event.data.targetSrc, event.data.part);
    } else if (event.data.action === 'amb_refreshDiagnosisPart') {
        $(`.diag-dot[data-part="${event.data.part}"]`).click();
    } else if (event.data.action === 'amb_startSutureMinigame') {
        startSutureMinigame(event.data.targetSrc, event.data.part);
    } else if (event.data.action === 'amb_hideDiagnosis') {
        $('#diagnosis-container').fadeOut();
        $('#diagnosis-info-panel').hide();
    } else if (event.data.action === 'amb_showDiagnosis') {
        $('#diagnosis-container').fadeIn();
    } else if (event.data.action === 'amb_receiveInjuries') {
        // Real-time damage recognition update
        updateDots(event.data.injuries);
        
        // If the info panel is open, refresh it so buttons/levels update instantly
        if ($('#diagnosis-info-panel').is(':visible')) {
            const currentPartLabel = $('#diag-part-name').text().toUpperCase().replace(' ', '_');
            refreshPartDetail(currentPartLabel);
        }
    }
});

let isBPActive = false;
let isBPDragging = false;

function updateTube() {
    if (!isBPActive) return;
    
    const machine = $('#bp-machine-display');
    const cuff = $('#bp-cuff-item');
    
    const mOffset = machine.offset();
    const cOffset = cuff.offset();
    
    // Machine attachment point (BOTTOM center)
    const x1 = mOffset.left + machine.width() / 2;
    const y1 = mOffset.top + machine.height() - (machine.height() * 0.05); 
    
    // Cuff attachment point (center)
    const x2 = cOffset.left + cuff.width() / 2;
    const y2 = cOffset.top + cuff.height() / 2;
    
    // Control points for a nice curve (Relative to screen height)
    const curveOffset = $(window).height() * 0.15;
    const cp1x = x1;
    const cp1y = y1 + curveOffset; 
    const cp2x = x2;
    const cp2y = y2 + curveOffset;
    
    const pathData = `M ${x1} ${y1} C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${x2} ${y2}`;
    
    $('#bp-tube-base').attr('d', pathData);
    $('#bp-tube-main').attr('d', pathData);
    $('#bp-tube-highlight').attr('d', pathData);
}

function startBPMinigame(targetSrc, part) {
    isBPActive = true;
    isBPDragging = false;
    $('#bp-minigame-container').css('display', 'flex').hide().fadeIn();
    
    const cuff = $('#bp-cuff-item');
    const area = $('#bp-game-area');
    const target = $('#bp-target-zone');
    const values = $('#bp-values');

    // Reset UI
    const windowW = $(window).width();
    const windowH = $(window).height();
    const cuffWidth = cuff.width() || 300;
    const cuffHeight = cuff.height() || 300;
    const startX = windowW / 2 - (cuffWidth / 2); // Center X
    const startY = windowH * 0.75 - (cuffHeight / 2); // 75% down (Bottom Middle)

    cuff.css({ 
        top: startY + 'px', 
        left: startX + 'px', 
        display: 'block',
        transform: 'rotate(148deg)' 
    });
    $('#systolic').text('--');
    $('#diastolic').text('--');
    $('#pulse-rate').text('--');
    values.hide();
    
    // Initial tube update
    setTimeout(updateTube, 100);

    let dragOffset = { x: 0, y: 0 };

    cuff.off('mousedown').on('mousedown', function(e) {
        if (!isBPActive) return;
        isBPDragging = true;
        cuff.css('cursor', 'grabbing');
        
        const pos = cuff.position();
        dragOffset.x = e.pageX - pos.left;
        dragOffset.y = e.pageY - pos.top;
    });

    let requestRef;
    const updateCuffPos = (e) => {
        if (!isBPDragging || !isBPActive) return;

        let x = e.pageX - dragOffset.x;
        let y = e.pageY - dragOffset.y;

        const curCuffWidth = cuff.width();
        const curCuffHeight = cuff.height();

        // Bounds
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x > $(window).width() - curCuffWidth) x = $(window).width() - curCuffWidth;
        if (y > $(window).height() - curCuffHeight) y = $(window).height() - curCuffHeight;

        cuff.css({ left: x + 'px', top: y + 'px' });
        
        // Cuff is now STILL (no dynamic rotation)
        cuff.css('transform', `rotate(148deg)`);
        
        updateTube(); // Update tube while dragging
        
        const targetOffset = target.offset();
        const dist = Math.sqrt(Math.pow(x - targetOffset.left, 2) + Math.pow(y - targetOffset.top, 2));
        const successDist = Math.max(80, windowW * 0.05);

        if (dist < successDist) {
            target.css('background', 'rgba(46, 204, 113, 0.6)');
            target.css('border-color', '#2ecc71');
        } else {
            target.css('background', 'rgba(52, 152, 219, 0.3)');
            target.css('border-color', 'rgba(255, 255, 255, 0.7)');
        }
        
        requestRef = requestAnimationFrame(() => {}); 
    };

    $(document).off('mousemove.bp').on('mousemove.bp', function(e) {
        if (!isBPDragging || !isBPActive) return;
        if (requestRef) cancelAnimationFrame(requestRef);
        requestRef = requestAnimationFrame(() => updateCuffPos(e));
    });

    $(document).off('mouseup.bp').on('mouseup.bp', function() {
        if (!isBPDragging || !isBPActive) return;
        isBPDragging = false;
        cuff.css('cursor', 'grab');
        if (requestRef) cancelAnimationFrame(requestRef);

        const cuffPos = cuff.offset();
        const targetPos = target.offset();
        const dist = Math.sqrt(Math.pow(cuffPos.left - targetPos.left, 2) + Math.pow(cuffPos.top - targetPos.top, 2));
        const successDist = Math.max(100, windowW * 0.08);

        if (dist < successDist) {
            cuff.animate({ 
                left: targetPos.left, 
                top: targetPos.top 
            }, {
                duration: 200,
                step: updateTube,
                complete: () => {
                    cuff.css('transform', 'rotate(148deg)');
                    updateTube();
                    finishBPMinigame(targetSrc, part);
                }
            });
        } else {
            const curCuffWidth = cuff.width();
            const curCuffHeight = cuff.height();
            const startX = windowW / 2 - (curCuffWidth / 2);
            const startY = windowH * 0.75 - (curCuffHeight / 2);

            cuff.animate({ 
                left: startX + 'px', 
                top: startY + 'px' 
            }, {
                duration: 300,
                step: updateTube,
                complete: () => {
                    cuff.css('transform', 'rotate(148deg)');
                    updateTube();
                }
            });
        }
    });

    // Escape listener
    const handleEscape = (e) => {
        if (e.key === "Escape" && isBPActive) {
            closeBPMinigame(false, targetSrc, part);
            window.removeEventListener('keydown', handleEscape);
        }
    };
    window.addEventListener('keydown', handleEscape);
}

function finishBPMinigame(targetSrc, part) {
    // Generate some "hunger death" values
    const sys = Math.floor(Math.random() * (90 - 70) + 70);
    const dia = Math.floor(Math.random() * (60 - 40) + 40);
    const pulse = Math.floor(Math.random() * (50 - 40) + 40);

    setTimeout(() => {
        $('#systolic').text(sys);
        $('#diastolic').text(dia);
        $('#pulse-rate').text(pulse);
        $('#bp-values').fadeIn();
        
        setTimeout(() => {
            closeBPMinigame(true, targetSrc, part);
        }, 4000); // Closes ~5s total with the 1s reveal delay above
    }, 1000);
}

function closeBPMinigame(success, targetSrc, part) {
    isBPActive = false;
    isBPDragging = false;
    $(document).off('mousemove.bp mouseup.bp');
    $('#bp-minigame-container').fadeOut();
    
    // Clear tube paths
    $('#bp-tube-base').attr('d', '');
    $('#bp-tube-main').attr('d', '');
    $('#bp-tube-highlight').attr('d', '');

    $.post(`https://${GetParentResourceName()}/bpMinigameResult`, JSON.stringify({
        success: success,
        targetSrc: targetSrc,
        part: part
    }));
}

let isClampActive = false;
let clampAnimRef = null;

// New Surgical Physical Vessel State
let vesselSegments = []; // { kind, leftPath, rightPath, isLinked, stitches: [] }
let activeVesselEnd = null; 
let currentVesselSuture = null; // { sIdx, stIdx }
let isVesselSuturing = false;

function areVesselsLinked() {
    return vesselSegments.length > 0 && vesselSegments.every(s => s.isLinked);
}

function areVesselsSutured() {
    return vesselSegments.length > 0 && vesselSegments.every(s => s.stitches.every(st => st.completed));
}

function drawClampMinigameScene(canvas, ctx, ms) {
    const w = canvas.width;
    const h = canvas.height;
    const centerY = h * 0.54;

    ctx.clearRect(0, 0, w, h);

    // 1. Deep Tissue & Wound Bed (Anatomical realism)
    const skin = ctx.createLinearGradient(0, 0, 0, h);
    skin.addColorStop(0, '#be8467');
    skin.addColorStop(0.5, '#a66d52');
    skin.addColorStop(1, '#8f5744');
    ctx.fillStyle = skin;
    ctx.fillRect(0, 0, w, h);

    const incisionW = w * 1.5; 
    const incisionH = h * 0.8;
    const cavity = ctx.createRadialGradient(w * 0.5, centerY, 50, w * 0.5, centerY, incisionW * 0.55);
    cavity.addColorStop(0, '#3d0606'); // Deep blood pool
    cavity.addColorStop(0.6, '#220303');
    cavity.addColorStop(1, '#110101');
    ctx.fillStyle = cavity;
    ctx.beginPath();
    ctx.ellipse(w * 0.5, centerY, incisionW * 0.5, incisionH * 0.5, 0, 0, Math.PI * 2);
    ctx.fill();

    // 2. BACKGROUND VESSEL MAP (The old design, static)
    const vesselBaseWidth = Math.max(10, w * 0.015);
    const vesselLines = [
        { kind: 'artery', pts: [[-0.03,0.50],[0.15,0.46],[0.30,0.42],[0.44,0.47],[0.58,0.40],[0.74,0.46],[1.03,0.44]], alpha: 0.25 },
        { kind: 'vein',   pts: [[-0.03,0.60],[0.16,0.57],[0.33,0.62],[0.49,0.55],[0.64,0.61],[0.81,0.57],[1.03,0.60]], alpha: 0.25 },
        { kind: 'artery', pts: [[-0.03,0.69],[0.20,0.66],[0.38,0.61],[0.54,0.69],[0.72,0.63],[1.03,0.67]], alpha: 0.5 },
        { kind: 'vein',   pts: [[-0.03,0.36],[0.18,0.39],[0.34,0.33],[0.52,0.37],[0.70,0.34],[1.03,0.36]], alpha: 0.5 }
    ];

    const strokePathSmooth = (pts) => {
        ctx.beginPath();
        const sx = pts[0][0] * w;
        const sy = pts[0][1] * h;
        ctx.moveTo(sx, sy);
        for (let i = 1; i < pts.length - 1; i++) {
            const x = pts[i][0] * w;
            const y = pts[i][1] * h;
            const nx = pts[i + 1][0] * w;
            const ny = pts[i + 1][1] * h;
            const cx = (x + nx) * 0.5;
            const cy = (y + ny) * 0.5;
            ctx.quadraticCurveTo(x, y, cx, cy);
        }
        const lx = pts[pts.length - 1][0] * w;
        const ly = pts[pts.length - 1][1] * h;
        ctx.lineTo(lx, ly);
    };

    vesselLines.forEach((line) => {
        const isArtery = line.kind === 'artery';
        const colorMain = isArtery ? '#9b111a' : '#254b8c';
        ctx.save();
        ctx.globalAlpha = line.alpha;
        strokePathSmooth(line.pts);
        ctx.strokeStyle = '#000';
        ctx.lineWidth = vesselBaseWidth + 4;
        ctx.stroke();
        strokePathSmooth(line.pts);
        ctx.strokeStyle = colorMain;
        ctx.lineWidth = vesselBaseWidth;
        ctx.stroke();
        ctx.restore();
    });

    // 3. INTERACTIVE SEVERED VESSELS (Detailed 3D design)
    const pulse = 0.55 + 0.45 * Math.sin(ms * 0.015);
    const activeVesselWidth = Math.max(18, w * 0.025);

    vesselSegments.forEach((seg, idx) => {
        const isArtery = seg.kind === 'artery';
        const colorMain = isArtery ? '#c0392b' : '#2980b9';
        const colorDeep = isArtery ? '#7b241c' : '#1a5276';
        
        const drawSegmentBody = (points, side) => {
            if (points.length < 2) return;
            
            // 3D Shadow
            ctx.beginPath();
            ctx.moveTo(points[0].x, points[0].y);
            for(let i=1; i<points.length; i++) ctx.lineTo(points[i].x, points[i].y);
            ctx.strokeStyle = '#000';
            ctx.lineWidth = activeVesselWidth + 8;
            ctx.globalAlpha = 0.6;
            ctx.stroke();
            ctx.globalAlpha = 1.0;

            // Main Tube
            const grad = ctx.createLinearGradient(points[0].x, points[0].y, points[points.length-1].x, points[points.length-1].y);
            grad.addColorStop(0, colorDeep);
            grad.addColorStop(0.5, colorMain);
            grad.addColorStop(1, colorDeep);
            
            ctx.beginPath();
            ctx.moveTo(points[0].x, points[0].y);
            for(let i=1; i<points.length; i++) ctx.lineTo(points[i].x, points[i].y);
            ctx.strokeStyle = grad;
            ctx.lineWidth = activeVesselWidth;
            ctx.lineCap = 'round';
            ctx.lineJoin = 'round';
            ctx.stroke();

            // Anatomical Sheen
            ctx.beginPath();
            ctx.moveTo(points[0].x, points[0].y - 4);
            for(let i=1; i<points.length; i++) ctx.lineTo(points[i].x, points[i].y - 4);
            ctx.strokeStyle = 'rgba(255,255,255,0.35)';
            ctx.lineWidth = activeVesselWidth * 0.35;
            ctx.stroke();

            // Severed End (The Lumen)
            if (!seg.isLinked) {
                const end = side === 'left' ? points[points.length-1] : points[0];
                
                // Rim highlight for the cut edge
                ctx.beginPath();
                ctx.arc(end.x, end.y, activeVesselWidth/2 + 2, 0, Math.PI * 2);
                ctx.strokeStyle = 'rgba(255, 255, 255, 0.2)';
                ctx.lineWidth = 1;
                ctx.stroke();

                // Dark internal hole
                ctx.fillStyle = '#000';
                ctx.beginPath();
                ctx.arc(end.x, end.y, activeVesselWidth/2, 0, Math.PI * 2);
                ctx.fill();
                
                // Wet cut edge (blood soaked)
                ctx.strokeStyle = '#f00';
                ctx.lineWidth = 4;
                ctx.stroke();

                // Realistic Blood Pooling (Removed splashes)
                if (side === 'left') { 
                    const spurt = 10 + 20 * pulse;
                    const bGrad = ctx.createRadialGradient(end.x, end.y, 2, end.x, end.y, spurt);
                    bGrad.addColorStop(0, `rgba(225, 20, 30, ${0.8 + 0.1 * pulse})`);
                    bGrad.addColorStop(1, 'rgba(150, 0, 0, 0)');
                    ctx.fillStyle = bGrad;
                    ctx.beginPath();
                    ctx.arc(end.x, end.y, spurt, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
        };

        if (seg.isLinked) {
            const combined = [...seg.leftPath, ...seg.rightPath];
            drawSegmentBody(combined, 'linked');

            // Draw Suture Points at the junction
            seg.stitches.forEach(st => {
                // Entry hole
                ctx.beginPath();
                ctx.arc(st.x, st.yTop, 4, 0, Math.PI * 2);
                ctx.fillStyle = '#1a0202';
                ctx.fill();
                
                // Exit hole
                ctx.beginPath();
                ctx.arc(st.x, st.yBottom, 4, 0, Math.PI * 2);
                ctx.fillStyle = '#1a0202';
                ctx.fill();

                if (st.completed) {
                    ctx.beginPath();
                    ctx.moveTo(st.x, st.yTop);
                    ctx.quadraticCurveTo(st.x + 4, (st.yTop + st.yBottom)/2, st.x, st.yBottom);
                    ctx.strokeStyle = '#fff'; // White suture line
                    ctx.lineWidth = 2.5;
                    ctx.stroke();
                } else if (isVesselSuturing && st.active) {
                    ctx.beginPath();
                    ctx.arc(st.x, st.yTop, 8, 0, Math.PI * 2);
                    ctx.strokeStyle = 'rgba(255, 255, 255, 0.6)';
                    ctx.lineWidth = 2;
                    ctx.stroke();
                }
            });
        } else {
            drawSegmentBody(seg.leftPath, 'left');
            drawSegmentBody(seg.rightPath, 'right');
        }
    });
}

function startClampMinigame(targetSrc, part) {
    isClampActive = true;
    isVesselSuturing = false;
    $('#clamp-minigame-container').css('display', 'flex').hide().fadeIn();

    const area = $('#clamp-canvas-area');
    const canvas = document.getElementById('clamp-canvas');
    const ctx = canvas.getContext('2d');
    const needle = $('#vessel-suture-needle');
    canvas.width = area.width();
    canvas.height = area.height();

    const midX = canvas.width * 0.5;
    const gap = 140;
    const h = canvas.height;

    vesselSegments = [
        {
            kind: 'artery',
            isLinked: false,
            leftPath: [{x: -100, y: h*0.4}, {x: midX - gap, y: h*0.42}],
            rightPath: [{x: midX + gap, y: h*0.42}, {x: canvas.width + 100, y: h*0.4}],
            stitches: []
        },
        {
            kind: 'vein',
            isLinked: false,
            leftPath: [{x: -100, y: h*0.6}, {x: midX - gap, y: h*0.58}],
            rightPath: [{x: midX + gap, y: h*0.58}, {x: canvas.width + 100, y: h*0.6}],
            stitches: []
        }
    ];

    activeVesselEnd = null;
    currentVesselSuture = null;

    const clampHint = $('#clamp-hint');
    clampHint.text('GRAB SEVERED VESSEL ENDS AND JOIN THEM');

    // Hide clamps (they are replaced by suture)
    $('.clamp-tool').hide();
    needle.hide();

    const animate = (t) => {
        if (!isClampActive) return;
        drawClampMinigameScene(canvas, ctx, t || 0);
        clampAnimRef = requestAnimationFrame(animate);
    };
    clampAnimRef = requestAnimationFrame(animate);

    // Vessel Interaction
    area.off('mousedown.vessel mousemove.vessel mouseup.vessel');
    
    let isDraggingNeedle = false;

    area.on('mousedown.vessel', function(e) {
        if (!isClampActive) return;
        const offset = area.offset();
        const mx = e.pageX - offset.left;
        const my = e.pageY - offset.top;

        if (!areVesselsLinked()) {
            vesselSegments.forEach((seg, sIdx) => {
                if (seg.isLinked) return;
                const endL = seg.leftPath[seg.leftPath.length - 1];
                if (Math.hypot(mx - endL.x, my - endL.y) < 50) {
                    activeVesselEnd = { sIdx, side: 'left' };
                }
            });
        } else if (isVesselSuturing) {
            // Suture interaction
            vesselSegments.forEach((seg, sIdx) => {
                seg.stitches.forEach((st, stIdx) => {
                    if (st.active && Math.hypot(mx - st.x, my - st.yTop) < 20) {
                        isDraggingNeedle = true;
                        currentVesselSuture = { sIdx, stIdx };
                    }
                });
            });
        }
    });

    $(document).off('mousemove.vessel mouseup.vessel');
    $(document).on('mousemove.vessel', function(e) {
        if (!isClampActive) return;
        const offset = area.offset();
        const mx = e.pageX - offset.left;
        const my = e.pageY - offset.top;

        if (activeVesselEnd) {
            const seg = vesselSegments[activeVesselEnd.sIdx];
            const endL = seg.leftPath[seg.leftPath.length - 1];
            endL.x = mx;
            endL.y = my;

            const endR = seg.rightPath[0];
            if (Math.hypot(mx - endR.x, my - endR.y) < 50) {
                seg.isLinked = true;
                activeVesselEnd = null;
                endL.x = endR.x;
                endL.y = endR.y;

                // Create suture points for this vessel junction
                const stitchCount = 3;
                const stitchSpacing = 15;
                for(let i=0; i<stitchCount; i++) {
                    seg.stitches.push({
                        x: endR.x - (stitchSpacing) + (i * stitchSpacing),
                        yTop: endR.y - 20,
                        yBottom: endR.y + 20,
                        completed: false,
                        active: i === 0
                    });
                }

                if (areVesselsLinked()) {
                    isVesselSuturing = true;
                    needle.show();
                    area.css('cursor', 'none'); // Hide real cursor when suturing
                    clampHint.text('VESSELS JOINED. SUTURE THE JUNCTIONS.');
                }
            }
        }

        if (isVesselSuturing) {
            // Position needle so Bottom-Left corner is at mouse position
            const needleHeight = needle.height();
            needle.css({ 
                left: mx + 'px', 
                top: (my - needleHeight) + 'px' 
            });
        }
    });

    $(document).on('mouseup.vessel', function(e) {
        if (!isClampActive) return;
        activeVesselEnd = null;

        if (isDraggingNeedle && currentVesselSuture) {
            const offset = area.offset();
            const mx = e.pageX - offset.left;
            const my = e.pageY - offset.top;
            
            const seg = vesselSegments[currentVesselSuture.sIdx];
            const st = seg.stitches[currentVesselSuture.stIdx];
            
            if (Math.hypot(mx - st.x, my - st.yBottom) < 25) {
                st.completed = true;
                st.active = false;
                if (currentVesselSuture.stIdx < seg.stitches.length - 1) {
                    seg.stitches[currentVesselSuture.stIdx + 1].active = true;
                } else {
                    // Try to find next vessel to suture
                    const nextVessel = vesselSegments.find(s => s.stitches.some(st => !st.completed));
                    if (nextVessel) {
                        const nextStitch = nextVessel.stitches.find(st => !st.completed);
                        if (nextStitch) nextStitch.active = true;
                    }
                }
            }
            isDraggingNeedle = false;
            
            if (areVesselsSutured()) {
                setTimeout(() => closeClampMinigame(true, targetSrc, part), 800);
            }
        }
    });

    const onEsc = (e) => {
        if (e.key === 'Escape' && isClampActive) closeClampMinigame(false, targetSrc, part);
    };
    window.addEventListener('keydown', onEsc);
}

function closeClampMinigame(success, targetSrc, part) {
    isClampActive = false;
    isVesselSuturing = false;
    if (clampAnimRef) {
        cancelAnimationFrame(clampAnimRef);
        clampAnimRef = null;
    }
    $('#suture-needle, #vessel-suture-needle').hide();
    $('#clamp-canvas-area').off('mousedown.vessel').css('cursor', 'crosshair');
    $(document).off('mousemove.vessel mouseup.vessel');
    $('#clamp-minigame-container').fadeOut();

    $.post(`https://${GetParentResourceName()}/clampMinigameResult`, JSON.stringify({
        success: success,
        targetSrc: targetSrc,
        part: part
    }));
}

let isSutureActive = false;
let currentStitch = 0;
const totalStitchesNeeded = 8;

    function startSutureMinigame(targetSrc, part) {
    isSutureActive = true;
    currentStitch = 0;
    $('#suture-minigame-container').css('display', 'flex').hide().fadeIn();
    $('#suture-fill').css('width', '0%');
    $('#suture-needle').show(); // Always show needle in minigame
    
    const canvas = document.getElementById('suture-canvas');
    const ctx = canvas.getContext('2d');
    const area = $('#suture-canvas-area');
    const needle = $('#suture-needle');

    canvas.width = area.width();
    canvas.height = area.height();

    const points = [];
    const centerY = canvas.height / 2;
    const spacing = (canvas.width - 100) / (totalStitchesNeeded - 1);

    for (let i = 0; i < totalStitchesNeeded; i++) {
        points.push({
            x: 50 + i * spacing,
            yTop: centerY - 40,
            yBottom: centerY + 40,
            completed: false,
            active: i === 0
        });
    }

    function drawWound() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        // 1. Realistic Skin Texture
        const skinGrd = ctx.createRadialGradient(canvas.width/2, centerY, 50, canvas.width/2, centerY, canvas.width/2);
        skinGrd.addColorStop(0, '#d3a68d');
        skinGrd.addColorStop(1, '#8d5543');
        ctx.fillStyle = skinGrd;
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        // 2. Diffuse Bruising around the wound
        const bruiseGrd = ctx.createRadialGradient(canvas.width/2, centerY, 20, canvas.width/2, centerY, 150);
        bruiseGrd.addColorStop(0, 'rgba(100, 20, 40, 0.4)');
        bruiseGrd.addColorStop(0.5, 'rgba(60, 10, 60, 0.2)');
        bruiseGrd.addColorStop(1, 'rgba(0, 0, 0, 0)');
        ctx.fillStyle = bruiseGrd;
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        // 3. Dynamic Wound Fissure (Closes progressively from left to right with a smooth gradient)
        const lastStitchX = currentStitch > 0 ? points[currentStitch - 1].x : 30;
        const transitionWidth = spacing * 1.5; // Smooth fade over 1.5 stitches
        
        // --- Part A: The "Scar" (Closed part of the wound) ---
        ctx.beginPath();
        ctx.moveTo(30, centerY);
        ctx.bezierCurveTo(canvas.width/3, centerY - 25, 2*canvas.width/3, centerY + 25, canvas.width - 30, centerY);
        ctx.lineWidth = 2;
        ctx.strokeStyle = 'rgba(74, 8, 8, 0.4)';
        ctx.lineCap = 'round';
        ctx.stroke();

        // --- Part B: The "Open" Wound (Fades in gradiently) ---
        if (currentStitch < totalStitchesNeeded) {
            ctx.save();
            ctx.beginPath();
            ctx.moveTo(30, centerY);
            ctx.bezierCurveTo(canvas.width/3, centerY - 25, 2*canvas.width/3, centerY + 25, canvas.width - 30, centerY);
            
            // Outer wound edges (darker, raw)
            const outerGrd = ctx.createLinearGradient(lastStitchX - (transitionWidth/2), 0, lastStitchX + (transitionWidth/2), 0);
            outerGrd.addColorStop(0, 'rgba(74, 8, 8, 0)');
            outerGrd.addColorStop(1, 'rgba(74, 8, 8, 1)');
            ctx.lineWidth = 12;
            ctx.strokeStyle = outerGrd;
            ctx.stroke();
            
            // Inner deep tissue (bloody)
            const innerGrd = ctx.createLinearGradient(lastStitchX - (transitionWidth/2), 0, lastStitchX + (transitionWidth/2), 0);
            innerGrd.addColorStop(0, 'rgba(128, 0, 0, 0)');
            innerGrd.addColorStop(1, 'rgba(128, 0, 0, 1)');
            ctx.lineWidth = 6;
            ctx.strokeStyle = innerGrd;
            ctx.stroke();

            ctx.restore();
        }

        // 4. Draw Stitch Points (Entry/Exit)
        points.forEach((p, i) => {
            // Entry hole (Small dark circle)
            ctx.beginPath();
            ctx.arc(p.x, p.yTop, 4, 0, Math.PI * 2);
            ctx.fillStyle = '#2a0505';
            ctx.fill();
            
            // Highlight active/completed points
            if (p.active) {
                ctx.beginPath();
                ctx.arc(p.x, p.yTop, 8, 0, Math.PI * 2);
                ctx.strokeStyle = 'rgba(255, 255, 255, 0.6)';
                ctx.lineWidth = 2;
                ctx.stroke();
            }

            // Exit hole
            ctx.beginPath();
            ctx.arc(p.x, p.yBottom, 4, 0, Math.PI * 2);
            ctx.fillStyle = '#2a0505';
            ctx.fill();

            // 5. Draw completed suture thread (Surgical Silk style)
            if (p.completed) {
                ctx.beginPath();
                ctx.moveTo(p.x, p.yTop);
                // Curve the thread slightly for realism
                ctx.quadraticCurveTo(p.x + 5, centerY, p.x, p.yBottom);
                ctx.lineWidth = 3;
                ctx.strokeStyle = '#fff'; // White suture line
                ctx.stroke();
                
                // Add "knots" at the entry points
                ctx.beginPath();
                ctx.arc(p.x, p.yTop, 3, 0, Math.PI * 2);
                ctx.fillStyle = '#fff';
                ctx.fill();
            }
        });
    }

    drawWound();

    let isDragging = false;
    let startPoint = null;

    area.off('mousedown').on('mousedown', function(e) {
        if (!isSutureActive) return;
        const offset = area.offset();
        const mouseX = e.pageX - offset.left;
        const mouseY = e.pageY - offset.top;

        // Detection at the point (Bottom-Left of needle image)
        const p = points[currentStitch];
        const dist = Math.sqrt(Math.pow(mouseX - p.x, 2) + Math.pow(mouseY - p.yTop, 2));
        
        if (dist < 20) {
            isDragging = true;
            startPoint = { x: p.x, y: p.yTop };
        }
    });

    $(document).off('mousemove.suture').on('mousemove.suture', function(e) {
        if (!isSutureActive) return;
        const offset = area.offset();
        const mouseX = e.pageX - offset.left;
        const mouseY = e.pageY - offset.top;

        // Position needle so Bottom-Left corner is at mouse position
        const needleHeight = needle.height();
        needle.css({ 
            left: (mouseX) + 'px', 
            top: (mouseY - needleHeight) + 'px' 
        });

        if (isDragging) {
            drawWound();
        }
    });

    $(document).off('mouseup.suture').on('mouseup.suture', function(e) {
        if (!isSutureActive || !isDragging) return;
        isDragging = false;

        const offset = area.offset();
        const mouseX = e.pageX - offset.left;
        const mouseY = e.pageY - offset.top;

        const p = points[currentStitch];
        const dist = Math.sqrt(Math.pow(mouseX - p.x, 2) + Math.pow(mouseY - p.yBottom, 2));
        
        if (dist < 25) {
            p.completed = true;
            p.active = false;
            currentStitch++;
            
            const progress = (currentStitch / totalStitchesNeeded) * 100;
            $('#suture-fill').css('width', progress + '%');

            if (currentStitch < totalStitchesNeeded) {
                points[currentStitch].active = true;
            } else {
                // Success!
                setTimeout(() => {
                    closeSutureMinigame(true, targetSrc, part);
                }, 500);
            }
        }
        drawWound();
    });

    const handleEscape = (e) => {
        if (e.key === "Escape" && isSutureActive) {
            closeSutureMinigame(false, targetSrc, part);
            window.removeEventListener('keydown', handleEscape);
        }
    };
    window.addEventListener('keydown', handleEscape);
}

function closeSutureMinigame(success, targetSrc, part) {
    isSutureActive = false;
    $('#suture-needle').hide();
    $(document).off('mousemove.suture mouseup.suture');
    $('#suture-minigame-container').fadeOut();
    
    $.post(`https://${GetParentResourceName()}/sutureMinigameResult`, JSON.stringify({
        success: success,
        targetSrc: targetSrc,
        part: part
    }));
}

let isSurgeryActive = false;
let isSurgeryDragging = false;

function startBulletMinigame(targetSrc, part) {
    isSurgeryActive = true;
    isSurgeryDragging = false;
    $('#bullet-minigame-container').css('display', 'flex').hide().fadeIn();
    
    const canvas = document.getElementById('extraction-canvas');
    const ctx = canvas.getContext('2d');
    const bullet = $('#extraction-bullet');
    const area = $('#extraction-canvas-area');

    // Set canvas size
    canvas.width = area.width();
    canvas.height = area.height();

    // Reset bullet position
    bullet.css({ top: '20px', left: '20px' });

    // Draw the "Artery Path"
    function drawPath() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        // Define Relative Path Points (%)
        const relPoints = [
            {x: 0.06, y: 0.08},
            {x: 0.23, y: 0.22},
            {x: 0.16, y: 0.52},
            {x: 0.44, y: 0.42},
            {x: 0.66, y: 0.32},
            {x: 0.58, y: 0.72},
            {x: 0.92, y: 0.88} // Far exit
        ];

        // Convert to absolute
        const points = relPoints.map(p => ({
            x: p.x * canvas.width,
            y: p.y * canvas.height
        }));

        // 1. Artery Wall (The Background)
        const wallGrd = ctx.createRadialGradient(canvas.width/2, canvas.height/2, canvas.width/6, canvas.width/2, canvas.height/2, canvas.width);
        wallGrd.addColorStop(0, '#500000');
        wallGrd.addColorStop(1, '#200000');
        ctx.fillStyle = wallGrd;
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        // Add fleshy textures
        for(let i=0; i<40; i++) {
            ctx.fillStyle = `rgba(100, 0, 0, ${Math.random() * 0.3})`;
            ctx.beginPath();
            ctx.arc(Math.random()*canvas.width, Math.random()*canvas.height, (canvas.width/20)+Math.random()*(canvas.width/10), 0, Math.PI*2);
            ctx.fill();
        }

        // 2. Artery Border (The Edge)
        ctx.beginPath();
        ctx.lineWidth = clampValue(canvas.width * 0.15, 80, 150); // Relative width
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.strokeStyle = '#400000';
        ctx.moveTo(points[0].x, points[0].y);
        for(let i=1; i<points.length; i++) ctx.lineTo(points[i].x, points[i].y);
        ctx.stroke();

        // 3. The Artery Lumen (The Safe Path)
        ctx.beginPath();
        ctx.lineWidth = clampValue(canvas.width * 0.11, 60, 110); 
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.strokeStyle = '#ff3333'; 
        ctx.moveTo(points[0].x, points[0].y);
        for(let i=1; i<points.length; i++) ctx.lineTo(points[i].x, points[i].y);
        ctx.stroke();

        // 4. Blood Flow Highlights
        ctx.strokeStyle = 'rgba(255, 100, 100, 0.2)';
        ctx.lineWidth = clampValue(canvas.width * 0.07, 40, 80);
        ctx.stroke();
    }

    function clampValue(val, min, max) {
        return Math.min(Math.max(val, min), max);
    }

    drawPath();

    // Reset bullet position to start of path
    const startX = (0.06 * canvas.width) - 30;
    const startY = (0.08 * canvas.height) - 30;
    bullet.css({ top: startY + 'px', left: startX + 'px' });

    // Position the Exit Target Div dynamically to match the path end
    const exitTarget = $('#extraction-target');
    const targetRelX = 0.92;
    const targetRelY = 0.88;
    exitTarget.css({
        left: (targetRelX * canvas.width - (exitTarget.width() / 2)) + 'px',
        top: (targetRelY * canvas.height - (exitTarget.height() / 2)) + 'px',
        right: 'auto',
        bottom: 'auto'
    });

    // Collision Detection Logic
    function checkCollision(x, y) {
        const centerX = x + 30;
        const centerY = y + 30;
        
        if (centerX < 0 || centerX >= canvas.width || centerY < 0 || centerY >= canvas.height) return true;
        
        // Read color at center
        const pixel = ctx.getImageData(centerX, centerY, 1, 1).data;
        if (pixel[0] < 120) return true; 
        
        return false;
    }

    let dragOffset = { x: 0, y: 0 };

    bullet.off('mousedown').on('mousedown', function(e) {
        if (!isSurgeryActive) return;
        e.preventDefault();
        isSurgeryDragging = true;
        bullet.addClass('dragging');
        
        const pos = bullet.position();
        dragOffset.x = e.pageX - pos.left;
        dragOffset.y = e.pageY - pos.top;
    });

    $(document).off('mousemove.minigame').on('mousemove.minigame', function(e) {
        if (!isSurgeryDragging || !isSurgeryActive) return;
        e.preventDefault();

        let x = e.pageX - dragOffset.x;
        let y = e.pageY - dragOffset.y;

        // Keep within bounds
        if (x < -20) x = -20;
        if (y < -20) y = -20;
        if (x > canvas.width - 40) x = canvas.width - 40;
        if (y > canvas.height - 40) y = canvas.height - 40;

        // Check for collision
        if (checkCollision(x, y)) {
            isSurgeryDragging = false;
            bullet.removeClass('dragging');
            const resetX = (0.06 * canvas.width) - 30;
            const resetY = (0.08 * canvas.height) - 30;
            bullet.css({ top: resetY + 'px', left: resetX + 'px' });
            
            area.css('background', 'rgba(255, 0, 0, 0.3)');
            setTimeout(() => area.css('background', 'transparent'), 200);
            return;
        }

        bullet.css({ left: x + 'px', top: y + 'px' });

        // Check if reached target (Relative to canvas size)
        const exitX = 0.92 * canvas.width;
        const exitY = 0.88 * canvas.height;
        const distToExit = Math.sqrt(Math.pow((x + 30) - exitX, 2) + Math.pow((y + 30) - exitY, 2));

        if (distToExit < (canvas.width * 0.08)) {
            isSurgeryActive = false;
            isSurgeryDragging = false;
            $('#bullet-minigame-container').fadeOut();
            $(document).off('mousemove.minigame');
            
            $.post(`https://${GetParentResourceName()}/bulletMinigameResult`, JSON.stringify({
                success: true,
                targetSrc: targetSrc,
                part: part
            }));
        }
    });

    $(document).off('mouseup.minigame').on('mouseup.minigame', function() {
        isSurgeryDragging = false;
        bullet.removeClass('dragging');
    });

    // Escape listener
    const handleEscape = (e) => {
        if (e.key === "Escape" && isSurgeryActive) {
            isSurgeryActive = false;
            isSurgeryDragging = false;
            $(document).off('mousemove.minigame mouseup.minigame');
            $('#bullet-minigame-container').fadeOut();
            $.post(`https://${GetParentResourceName()}/bulletMinigameResult`, JSON.stringify({
                success: false,
                targetSrc: targetSrc,
                part: part
            }));
            window.removeEventListener('keydown', handleEscape);
        }
    };
    window.addEventListener('keydown', handleEscape);
}

let dotDefinitions = [];

function updateDots(injuries) {
    if (!injuries) return;
    const container = $('#diagnosis-dots');
    
    // CASE 1: Array of dots (Sent by the Lua 30fps Loop)
    // This array contains {name, x, y, hasHits, isFractured}
    if (Array.isArray(injuries)) {
        dotDefinitions = injuries;
        
        injuries.forEach(dot => {
            let dotElement = $(`.diag-dot[data-part="${dot.name}"]`);
            if (dotElement.length === 0) {
                dotElement = $(`<div class="diag-dot" data-part="${dot.name}"></div>`);
                dotElement.on('click', function() {
                    refreshPartDetail(dot.name);
                });
                container.append(dotElement);
            }

            // Update Position
            dotElement.show().css({
                left: dot.x + '%',
                top: dot.y + '%'
            });

            // Apply Classes (Calculated in Lua)
            if (dot.isFractured) {
                dotElement.addClass('fractured').removeClass('has-hits has-bullet');
            } else if (dot.hasBullet) {
                dotElement.addClass('has-bullet').removeClass('fractured has-hits');
            } else if (dot.hasHits) {
                dotElement.addClass('has-hits').removeClass('fractured has-bullet');
            } else {
                dotElement.removeClass('has-hits fractured has-bullet');
            }
        });
        return;
    }

    // CASE 2: Injury Data Object (Sent by amb_openDiagnosisUI or Real-time push)
    // This is the full { head: {level: 0}, ... } object
    dotDefinitions.forEach(dot => {
        let dotElement = $(`.diag-dot[data-part="${dot.name}"]`);
        if (dotElement.length === 0) return; // Should already be created by the loop

        const injury = injuries[dot.name];
        let hasHits = false;
        let hasBullet = false;
        let isFractured = false;

        if (injury) {
            if (typeof injury === 'object' && injury !== null) {
                hasBullet = (injury.bullet === true);
                hasHits = (injury.level && injury.level > 0) || hasBullet;
                isFractured = injury.level && (injury.level >= 4) || injury.isFractured;
            } else {
                hasHits = injury > 0;
            }
        }

        // Apply classes for color coding
        if (isFractured) {
            dotElement.addClass('fractured').removeClass('has-hits has-bullet');
        } else if (hasBullet) {
            dotElement.addClass('has-bullet').removeClass('fractured has-hits');
        } else if (hasHits) {
            dotElement.addClass('has-hits').removeClass('fractured has-bullet');
        } else {
            dotElement.removeClass('has-hits fractured has-bullet');
        }
    });
}

let currentOpenedPart = null;

function refreshPartDetail(partName) {
    currentOpenedPart = partName;
    $.post(`https://${GetParentResourceName()}/getPartDetail`, JSON.stringify({ part: partName }), function(data) {
        $('#diag-part-name').text(data.label);
        
        let infoHtml = data.info;
        let actionsHtml = "";
        let themeClass = "theme-trauma"; // Default red

        // PRIORITY 1: Clothing Removal
        if (data.needsClothingRemoval) {
            infoHtml = `<span style="color: #f1c40f; font-weight: 800;">[CLOTHING INTERFERENCE]</span><br>` + infoHtml;
            actionsHtml += `<button class="diag-action-btn" onclick="removeClothes('${partName}', '${data.clothingType}')">REMOVE ${data.clothingType}</button>`;
        }
        
        const canTreatThisPart = (data.isPrimaryTreatmentPart === true);

        // PRIORITY 2: Medical Treatment (Wounds, Bullets, Special Conditions)
        if (canTreatThisPart && (data.level > 0 || data.hasBullet || data.needsFludro || data.isHunger || data.isBleeding)) {
            if (data.needsFludro && data.label.includes("HEAD")) {
                themeClass = "theme-heal";
                actionsHtml += `<button class="diag-action-btn heal" onclick="startTreatment('${partName}', 'fludro')">GIVE FLUDROCORTISONE</button>`;
            } else if (data.isHunger && data.label.includes("RIGHT ARM")) {
                themeClass = "theme-trauma";
                actionsHtml += `<button class="diag-action-btn bullet" onclick="startTreatment('${partName}', 'bp')">CHECK BLOOD PRESSURE</button>`;
            } else if (data.isBleeding) {
                themeClass = "theme-trauma";
                actionsHtml += `<button class="diag-action-btn bullet" onclick="startTreatment('${partName}', 'clamp')">CLAMP BLEEDING</button>`;
            } else if (data.hasBullet) {
                themeClass = "theme-trauma";
                // Force clothing removal for bullet extraction (logic handled in LUA too)
                if (!data.needsClothingRemoval) {
                    actionsHtml += `<button class="diag-action-btn bullet" onclick="startTreatment('${partName}', 'bullet')">EXTRACT BULLET</button>`;
                }
            } else {
                themeClass = "theme-heal";
                // Only show "TREAT INJURY" if NOT blocked by clothing
                if (!data.needsClothingRemoval) {
                    actionsHtml += `<button class="diag-action-btn heal" onclick="startTreatment('${partName}', 'heal')">TREAT INJURY</button>`;
                }
            }
        } else if (!canTreatThisPart && data.primaryTreatmentPart) {
            const focusPart = String(data.primaryTreatmentPart).replace('_', ' ').toUpperCase();
            infoHtml += `<br><span style="color:#f1c40f;font-weight:700;">FOCUS TREATMENT ON: ${focusPart}</span>`;
        }
        // PRIORITY 3: Bandaging (Only if no active wounds/bullets)
        if (!data.isPatientBandaged && canTreatThisPart) {
            themeClass = "theme-bandage";
            actionsHtml += `<button class="diag-action-btn bandage" onclick="applyBandage('${partName}')">APPLY BANDAGE</button>`;
        }

        // CPR/Revive is only for downed/dead patients.
        if (data.targetDowned && !actionsHtml.includes("performCPR()")) {
            themeClass = "theme-cpr";
            actionsHtml += `<button class="diag-action-btn cpr" onclick="performCPR()">PERFORM CPR (REVIVE)</button>`;
        }

        // Apply Dynamic Theme
        $('#diagnosis-info-panel').removeClass('theme-trauma theme-heal theme-bandage theme-cpr').addClass(themeClass);

        $('#diag-part-info').html(infoHtml);
        $('.injury-level-fill').css('width', (data.level / 5 * 100) + '%');
        
        // Append actions to the container if they exist
        $('#diag-part-info-container .diag-action-btn').remove(); // Clear old buttons
        if (actionsHtml !== "") {
            $('#diag-part-info-container').append(actionsHtml);
        }

        // Show prescription writer button only for ALIVE patients & EMS
        if (pharmacyData.isEMS && !pharmacyData.isDowned) {
            $('#diag-prescription-btn-container').removeClass('hidden');
        } else {
            $('#diag-prescription-btn-container').addClass('hidden');
        }

        $('#diagnosis-info-panel').fadeIn(300);
    });
}

$('#write-prescription-btn').on('click', function() {
    // Only if we are diagnosing someone
    if (currentOpenedPart) {
        $.post(`https://${GetParentResourceName()}/openPrescriptionWriter`, JSON.stringify({}));
    }
});

$('#close-diagnosis').on('click', function() {
    $('#diagnosis-container').fadeOut();
    $('#diagnosis-info-panel').hide();
    $.post(`https://${GetParentResourceName()}/closeDiagnosis`);
});

window.removeClothes = function(part, type) {
    $.post(`https://${GetParentResourceName()}/removePatientClothes`, JSON.stringify({ part: part, type: type }), function(data) {
        $(`.diag-dot[data-part="${part}"]`).click();
    });
};

window.startTreatment = function(part, type) {
    // Removed immediate fadeOut to prevent getting stuck if item check fails
    $.post(`https://${GetParentResourceName()}/startTreatment`, JSON.stringify({ part: part, type: type }));
};

window.applyBandage = function(part) {
    // Removed immediate fadeOut to prevent getting stuck if item check fails
    $.post(`https://${GetParentResourceName()}/applyBandage`, JSON.stringify({ part: part }));
};

window.performCPR = function() {
    $.post(`https://${GetParentResourceName()}/performCPR`);
};

// --- New Realistic Trauma Dressing Minigame ---
let currentDressingStep = 1;
let activeTool = null;
let woundCleanliness = 0;
let gauzePlaced = false;
let tapeCount = 0;
let dressingTargetSrc = null;
let dressingPart = null;
let isBandageActive = false;
let bandageEscapeHandler = null;

function startBandageMinigame(targetSrc, part) {
    currentDressingStep = 1;
    activeTool = null;
    woundCleanliness = 0;
    gauzePlaced = false;
    tapeCount = 0;
    isBandageActive = true;
    dressingTargetSrc = targetSrc;
    dressingPart = part;

    $('#bandage-minigame-container').css('display', 'flex').hide().fadeIn();
    resetDressingUI();
    initDressingCanvas();

    if (bandageEscapeHandler) {
        window.removeEventListener('keydown', bandageEscapeHandler);
    }
    bandageEscapeHandler = (e) => {
        if (e.key === "Escape" && isBandageActive) {
            closeBandageMinigame(false);
        }
    };
    window.addEventListener('keydown', bandageEscapeHandler);
}

function resetDressingUI() {
    $('.step-indicator').removeClass('active complete');
    $('#step-clean').addClass('active');
    $('.tool-item').addClass('disabled').removeClass('active');
    $('#tool-swab').removeClass('disabled');
    $('#gauze-target, #placed-gauze, #bandage-finish-btn').addClass('hidden').hide();
    $('#tape-container').empty();
    $('#dressing-instruction').text("Select the ANTISEPTIC to clean the wound area.");
}

function initDressingCanvas() {
    const canvas = document.getElementById('dressing-base-canvas');
    const ctx = canvas.getContext('2d');
    const area = $('#dressing-canvas-area');
    canvas.width = area.width();
    canvas.height = area.height();

    const centerX = canvas.width / 2;
    const centerY = canvas.height / 2;

    // Set gauze and target positions to center of wound
    $('#gauze-target, #placed-gauze').css({
        left: centerX + 'px',
        top: centerY + 'px'
    });

    // Define dimensions in outer scope for access in event handlers
    const limbWidth = Math.min(canvas.width * 0.3, 400); 
    const limbHeight = Math.min(canvas.height * 0.7, 800);
    const woundScale = limbWidth / 260;

    function drawLimb() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        // 1. Limb Visual (Relative to canvas size)
        const limbX = centerX - (limbWidth / 2);
        const limbY = centerY - (limbHeight / 2);
        const limbRadius = limbWidth * 0.1;

        const limbGrd = ctx.createLinearGradient(limbX, centerY, limbX + limbWidth, centerY);
        limbGrd.addColorStop(0, '#8d5543');
        limbGrd.addColorStop(0.3, '#d3a68d');
        limbGrd.addColorStop(0.7, '#d3a68d');
        limbGrd.addColorStop(1, '#8d5543');

        ctx.fillStyle = limbGrd;
        ctx.beginPath();
        ctx.moveTo(limbX + limbRadius, limbY);
        ctx.lineTo(limbX + limbWidth - limbRadius, limbY);
        ctx.quadraticCurveTo(limbX + limbWidth, limbY, limbX + limbWidth, limbY + limbRadius);
        ctx.lineTo(limbX + limbWidth, limbY + limbHeight - limbRadius);
        ctx.quadraticCurveTo(limbX + limbWidth, limbY + limbHeight, limbX + limbWidth - limbRadius, limbY + limbHeight);
        ctx.lineTo(limbX + limbRadius, limbY + limbHeight);
        ctx.quadraticCurveTo(limbX, limbY + limbHeight, limbX, limbY + limbHeight - limbRadius);
        ctx.lineTo(limbX, limbY + limbRadius);
        ctx.quadraticCurveTo(limbX, limbY, limbX + limbRadius, limbY);
        ctx.closePath();
        ctx.fill();

        // 2. Realistic Trauma Wound (Relative sizes)
        const opacity = 1.0; 
        const dirtOpacity = 1 - (woundCleanliness / 100);
        
        // Outer bruising
        const bruiseGrd = ctx.createRadialGradient(centerX, centerY, 10 * woundScale, centerX, centerY, 90 * woundScale);
        bruiseGrd.addColorStop(0, `rgba(80, 0, 40, ${0.4 + (0.1 * dirtOpacity)})`);
        bruiseGrd.addColorStop(0.4, `rgba(50, 0, 80, ${0.2 + (0.1 * dirtOpacity)})`);
        bruiseGrd.addColorStop(1, `rgba(0, 0, 0, 0)`);
        ctx.fillStyle = bruiseGrd;
        ctx.beginPath();
        ctx.ellipse(centerX, centerY, 80 * woundScale, 110 * woundScale, 0, 0, Math.PI * 2);
        ctx.fill();

        // Inner deep wound
        ctx.fillStyle = `rgba(50, 0, 0, 0.9)`;
        ctx.beginPath();
        ctx.ellipse(centerX, centerY, 20 * woundScale, 40 * woundScale, 0.2, 0, Math.PI * 2);
        ctx.fill();
        
        // Wet Blood Sheen
        ctx.strokeStyle = `rgba(255, 200, 200, 0.2)`;
        ctx.lineWidth = 2 * woundScale;
        ctx.beginPath();
        ctx.arc(centerX - 5 * woundScale, centerY - 15 * woundScale, 10 * woundScale, -0.5, 0.5);
        ctx.stroke();

        // Bacteria / Infection
        if (dirtOpacity > 0) {
            for(let i=0; i<12; i++) {
                const angle = (i / 12) * Math.PI * 2;
                const dist = (10 + Math.random() * 30) * woundScale;
                const bx = centerX + Math.cos(angle) * dist;
                const by = centerY + Math.sin(angle) * dist;
                
                ctx.fillStyle = `rgba(180, 190, 40, ${0.6 * dirtOpacity})`;
                ctx.beginPath();
                ctx.arc(bx, by, (2 + Math.random() * 3) * woundScale, 0, Math.PI * 2);
                ctx.fill();
            }
        }

        // Fresh Blood Drips
        ctx.fillStyle = `rgba(160, 0, 0, 0.85)`;
        for(let i=0; i<5; i++) {
            const dx = centerX + (Math.random() - 0.5) * 40 * woundScale;
            const dy = centerY + (10 + Math.random() * 40) * woundScale;
            ctx.beginPath();
            ctx.ellipse(dx, dy, 3 * woundScale, 8 * woundScale, 0, 0, Math.PI * 2);
            ctx.fill();
        }
    }

    drawLimb();

    // Event Listeners for Interaction
    area.off('mousemove').on('mousemove', function(e) {
        const offset = area.offset();
        const x = e.pageX - offset.left;
        const y = e.pageY - offset.top;

        // Tool Cursor
        if (activeTool) {
            $('#active-tool-cursor').css({ left: e.pageX - (($('#active-tool-cursor').width() || 60) / 2), top: e.pageY - (($('#active-tool-cursor').height() || 60) / 2) }).removeClass('hidden').show();
        } else {
            $('#active-tool-cursor').addClass('hidden').hide();
        }

        // Step 1: Enhanced Cleaning
        if (currentDressingStep === 1 && activeTool === 'swab' && e.buttons === 1) {
            const dist = Math.sqrt(Math.pow(x - centerX, 2) + Math.pow(y - centerY, 2));
            const cleaningRadius = (limbWidth / 260) * 90; // Relative to wound size
            
            if (dist < cleaningRadius) {
                $('#active-tool-cursor').addClass('scrubbing');
                woundCleanliness = Math.min(100, woundCleanliness + 2.5); // Slightly faster
                
                // Add "Foam" effect (Relative size)
                const foamSize = Math.max(20, canvas.width * 0.025);
                const foam = $('<div class="foam-layer"></div>');
                foam.css({
                    left: (x - (foamSize / 2)) + 'px',
                    top: (y - (foamSize / 2)) + 'px',
                    width: foamSize + 'px',
                    height: foamSize + 'px',
                    opacity: 0.4
                });
                $('#limb-visual-container').append(foam);
                foam.fadeOut(1000, function() { $(this).remove(); });

                // Create Particles
                for(let i=0; i<3; i++) {
                    const particle = $('<div class="cleaning-particle"></div>');
                    const tx = (Math.random() - 0.5) * 100;
                    const ty = (Math.random() - 0.5) * 100;
                    particle.css({
                        left: x + 'px',
                        top: y + 'px',
                        '--tx': tx + 'px',
                        '--ty': ty + 'px'
                    });
                    $('#limb-visual-container').append(particle);
                    setTimeout(() => particle.remove(), 600);
                }

                drawLimb();
                if (woundCleanliness >= 100) {
                    $('#active-tool-cursor').removeClass('scrubbing');
                    completeStep1();
                }
            } else {
                $('#active-tool-cursor').removeClass('scrubbing');
            }
        } else {
            $('#active-tool-cursor').removeClass('scrubbing');
        }
    });

    $('.tool-item').off('click').on('click', function() {
        const step = parseInt($(this).data('step'));
        if (step !== currentDressingStep || $(this).hasClass('disabled')) return;

        $('.tool-item').removeClass('active');
        $(this).addClass('active');
        activeTool = $(this).attr('id').split('-')[1];
        
        if (activeTool === 'swab') {
            $('#active-tool-cursor').html(`<img src="img/cotton.png" style="width: clamp(60px, 6vw, 120px); height: clamp(60px, 6vw, 120px); object-fit: contain;">`);
        } else {
            const iconClass = $(this).find('i').attr('class');
            $('#active-tool-cursor').html(`<i class="${iconClass}"></i>`);
        }

        if (currentDressingStep === 2) $('#gauze-target').removeClass('hidden').show();
    });

    area.off('mousedown').on('mousedown', function(e) {
        if (currentDressingStep === 2 && activeTool === 'gauze') {
            const offset = area.offset();
            const x = e.pageX - offset.left;
            const y = e.pageY - offset.top;
            const dist = Math.sqrt(Math.pow(x - centerX, 2) + Math.pow(y - centerY, 2));
            
            const gauzePlaceRadius = ($('#gauze-target').width() / 2) || 80;
            if (dist < gauzePlaceRadius) {
                $('#placed-gauze').addClass('gauze-placement-anim');
                completeStep2();
            }
        } else if (currentDressingStep === 3 && activeTool === 'tape') {
            const offset = area.offset();
            const x = e.pageX - offset.left;
            const y = e.pageY - offset.top;
            placeTape(x, y);
        }
    });
}

function completeStep1() {
    currentDressingStep = 2;
    activeTool = null;
    $('#step-clean').removeClass('active').addClass('complete');
    $('#step-apply').addClass('active');
    $('#tool-swab').addClass('disabled').removeClass('active');
    $('#tool-gauze').removeClass('disabled');
    $('#active-tool-cursor').addClass('hidden').hide();
    $('#dressing-instruction').html('<i class="fas fa-check-circle"></i> AREA STERILIZED. Place the GAUZE PAD now.');
}

function completeStep2() {
    currentDressingStep = 3;
    activeTool = null;
    gauzePlaced = true;
    $('#step-apply').removeClass('active').addClass('complete');
    $('#step-secure').addClass('active');
    $('#tool-gauze').addClass('disabled').removeClass('active');
    $('#tool-tape').removeClass('disabled');
    $('#gauze-target').hide().addClass('hidden');
    $('#placed-gauze').show().removeClass('hidden').css('display', 'block');
    $('#active-tool-cursor').addClass('hidden').hide();
    $('#dressing-instruction').html('<i class="fas fa-tape"></i> GAUZE APPLIED. Secure all edges with SURGICAL TAPE.');
}

function placeTape(x, y) {
    tapeCount++;
    const tape = $('<div class="tape-strip tape-placement-anim"></div>');
    $('#tape-container').append(tape);
    
    // Precise Alignment for the Tape Strips relative to the wound center
    const area = $('#dressing-canvas-area');
    const centerX = area.width() / 2;
    const centerY = area.height() / 2;
    
    const gauze = $('#placed-gauze');
    const gauzeWidth = gauze.width();
    const gauzeHeight = gauze.height();
    const tapeThickness = tape.height(); 
    
    const margin = gauzeWidth * 0.05; 
    let top, left, width, rotate;

    // Everything is centered with transform(-50%, -50%), so the visual edges 
    // are at centerX/centerY +/- (gauzeWidth/gauzeHeight)/2
    if (tapeCount === 1) { // Top Edge
        top = centerY - (gauzeHeight / 2);
        left = centerX;
        width = gauzeWidth + (margin * 2); 
        rotate = 0;
    } else if (tapeCount === 2) { // Bottom Edge
        top = centerY + (gauzeHeight / 2);
        left = centerX;
        width = gauzeWidth + (margin * 2); 
        rotate = 0;
    } else if (tapeCount === 3) { // Left Edge
        top = centerY;
        left = centerX - (gauzeWidth / 2);
        width = gauzeHeight + (margin * 2); 
        rotate = 90;
    } else if (tapeCount === 4) { // Right Edge
        top = centerY;
        left = centerX + (gauzeWidth / 2);
        width = gauzeHeight + (margin * 2); 
        rotate = 90;
    }

    tape.css({
        top: top + 'px',
        left: left + 'px',
        width: width + 'px',
        transform: `translate(-50%, -50%) rotate(${rotate}deg)`,
        opacity: 0
    });

    tape.animate({ opacity: 1 }, 200);

    if (tapeCount >= 4) {
        completeStep3();
    }
}

function completeStep3() {
    $('#step-secure').removeClass('active').addClass('complete');
    $('#tool-tape').addClass('disabled').removeClass('active');
    activeTool = null;
    $('#active-tool-cursor').addClass('hidden').hide();
    $('#bandage-finish-btn').removeClass('hidden').show();
    $('#dressing-instruction').text("Procedure complete. Secure the dressing.");
}

window.finishDressingProcedure = function() {
    closeBandageMinigame(true);
};

function closeBandageMinigame(success) {
    isBandageActive = false;
    $(document).off('mousemove.bandage mouseup.bandage');
    $('#bandage-minigame-container').fadeOut();
    $('#active-tool-cursor').addClass('hidden');
    if (bandageEscapeHandler) {
        window.removeEventListener('keydown', bandageEscapeHandler);
        bandageEscapeHandler = null;
    }
    
    $.post(`https://${GetParentResourceName()}/bandageMinigameResult`, JSON.stringify({
        success: success,
        targetSrc: dressingTargetSrc,
        part: dressingPart
    }));
    dressingTargetSrc = null;
    dressingPart = null;
}
