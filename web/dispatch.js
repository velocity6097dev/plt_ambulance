let dispatchCalls = [];
let currentDispatchIndex = 0;
let isDispatchDragging = false;
let dispatchOffset = { x: 0, y: 0 };
let isDispatchLocked = false;

$(document).ready(function() {
    // Make dispatch draggable
    const container = $('#dispatch-container');
    const handle = $('#dispatch-drag-handle');

    handle.on('mousedown', function(e) {
        if (isDispatchLocked) return;
        isDispatchDragging = true;
        dispatchOffset.x = e.clientX - container.offset().left;
        dispatchOffset.y = e.clientY - container.offset().top;
        container.css('cursor', 'grabbing');
    });

    $(document).on('mousemove', function(e) {
        if (!isDispatchDragging) return;
        
        let x = e.clientX - dispatchOffset.x;
        let y = e.clientY - dispatchOffset.y;

        container.css({
            left: x + 'px',
            top: y + 'px',
            right: 'auto'
        });
    });

    $(document).on('mouseup', function() {
        isDispatchDragging = false;
        container.css('cursor', 'default');
    });

    $(document).on('keydown', function(e) {
        if (!$('#dispatch-container').is(':visible')) return;
        if (!dispatchCalls.length) return;

        const tag = (e.target && e.target.tagName) ? e.target.tagName.toLowerCase() : '';
        if (tag === 'input' || tag === 'textarea') return;

        if (e.key === 'ArrowLeft') {
            e.preventDefault();
            setDispatchActiveIndex(currentDispatchIndex - 1);
            return;
        }

        if (e.key === 'ArrowRight') {
            e.preventDefault();
            setDispatchActiveIndex(currentDispatchIndex + 1);
            return;
        }

        const activeCall = dispatchCalls[currentDispatchIndex] || dispatchCalls[0];
        const x = activeCall.coords && typeof activeCall.coords.x === 'number' ? activeCall.coords.x : 0;
        const y = activeCall.coords && typeof activeCall.coords.y === 'number' ? activeCall.coords.y : 0;

        if (e.key === 'e' || e.key === 'E') {
            e.preventDefault();
            window.setDispatchGPS(x, y);
        } else if (e.key === 'y' || e.key === 'Y') {
            e.preventDefault();
            window.removeDispatchCall(activeCall.id);
        }
    });

    window.addEventListener('message', function(event) {
        const data = event.data;

        if (data.action === 'amb_toggleDispatch') {
            if (data.show) {
                $('#dispatch-container').fadeIn();
            } else {
                $('#dispatch-container').fadeOut();
            }
        } else if (data.action === 'amb_addDispatchCall') {
            addDispatchCall(data.call);
        } else if (data.action === 'amb_removeDispatchCall') {
            window.removeDispatchCall(data.id);
        } else if (data.action === 'amb_clearDispatchCalls') {
            window.clearAllDispatch();
        }
    });
});

function addDispatchCall(call) {
    if (!call) return;
    // Replace existing copy if it already exists, then prepend as newest.
    dispatchCalls = dispatchCalls.filter(c => c.id !== call.id);
    dispatchCalls.unshift(call);
    if (dispatchCalls.length > 20) dispatchCalls.pop();
    currentDispatchIndex = 0;

    renderDispatchCalls();
    
    // Play sound if possible (optional, handled by FiveM usually)
    // Send notification
    if (window.showNotification) {
        const items = [
            { label: window.ambT('ui_type', 'Type'), value: call.title },
            { label: window.ambT('ui_location', 'Location'), value: call.locationName || window.ambT('ui_unknown', 'Unknown') }
        ];
        if (call.injuryType) {
            const injuryLabel = call.injuryType === "fatal"
                ? window.ambT('ui_injury_fatal', 'Fatal (Downed)')
                : (call.injuryType === "severe" ? window.ambT('ui_injury_severe', 'Severe (Bleeding)') : window.ambT('ui_injury_minor', 'Minor'));
            items.push({ label: window.ambT('ui_injury', 'Injury'), value: injuryLabel });
        }
        window.showNotification(window.ambT('ui_incoming_call', 'INCOMING CALL'), items);
    }
}

function setDispatchActiveIndex(index) {
    if (!dispatchCalls.length) {
        currentDispatchIndex = 0;
        renderDispatchCalls();
        return;
    }

    const total = dispatchCalls.length;
    currentDispatchIndex = ((index % total) + total) % total;
    renderDispatchCalls();
}

function renderDispatchCalls() {
    const list = $('#dispatch-calls-list');
    const counter = $('#dispatch-counter');
    
    if (dispatchCalls.length === 0) {
        list.html(`
            <div class="dispatch-empty">
                <i class="fas fa-satellite-dish"></i>
                <p>${window.ambT('ui_station_clear', 'STATION CLEAR')}</p>
            </div>
        `);
        counter.text('0/0');
        syncActiveCallToClient(null);
        return;
    }

    if (currentDispatchIndex >= dispatchCalls.length) {
        currentDispatchIndex = dispatchCalls.length - 1;
    }
    if (currentDispatchIndex < 0) {
        currentDispatchIndex = 0;
    }

    const activeCall = dispatchCalls[currentDispatchIndex];
    counter.text(`${currentDispatchIndex + 1}/${dispatchCalls.length}`);
    list.empty();

    const x = activeCall.coords && typeof activeCall.coords.x === 'number' ? activeCall.coords.x : 0;
    const y = activeCall.coords && typeof activeCall.coords.y === 'number' ? activeCall.coords.y : 0;
    const code = activeCall.code || `10-${String(activeCall.id).slice(-2).padStart(2, '0')}`;
    const injuryBadge = activeCall.injuryType ? ` <span class="call-injury call-injury-${activeCall.injuryType}">${activeCall.injuryType.toUpperCase()}</span>` : '';
    const card = $(`
        <div class="dispatch-call-card active" data-id="${activeCall.id}">
            <div class="call-main">
                <div class="call-left">
                    <div class="call-code">${code}</div>
                    <div class="call-title">${activeCall.title || window.ambT('ui_unknown_call', 'Unknown Call')}${injuryBadge}</div>
                </div>
                <div class="call-right">
                    <div class="call-location">
                        <i class="fas fa-map-marker-alt"></i>
                        ${activeCall.locationName || window.ambT('ui_location_unknown', 'Location Unknown')}
                    </div>
                    <div class="call-time">
                        <i class="far fa-clock"></i>
                        ${activeCall.time || window.ambT('ui_now', 'NOW')}
                    </div>
                </div>
            </div>
            <div class="call-actions">
                <button class="call-btn gps" onclick="setDispatchGPS(${x}, ${y})">
                    ${window.ambT('ui_direction_key', 'E Direction')}
                </button>
                <button class="call-btn clear" onclick="removeDispatchCall('${activeCall.id}')">
                    ${window.ambT('ui_dismiss_key', 'Y Dismiss')}
                </button>
            </div>
        </div>
    `);
    list.append(card);
    syncActiveCallToClient(activeCall);
}

window.removeDispatchCall = function(id) {
    const removedIndex = dispatchCalls.findIndex(c => c.id === id);
    dispatchCalls = dispatchCalls.filter(c => c.id !== id);
    if (removedIndex !== -1 && currentDispatchIndex >= removedIndex) {
        currentDispatchIndex = Math.max(0, currentDispatchIndex - 1);
    }
    $.post(`https://${GetParentResourceName()}/dismissDispatchCall`, JSON.stringify({ id: id }));
    renderDispatchCalls();
};

window.clearAllDispatch = function() {
    dispatchCalls = [];
    currentDispatchIndex = 0;
    $.post(`https://${GetParentResourceName()}/dismissDispatchCall`, JSON.stringify({ id: null }));
    renderDispatchCalls();
};

function syncActiveCallToClient(call) {
    $.post(`https://${GetParentResourceName()}/setActiveDispatchCall`, JSON.stringify({ call: call || null }));
}

window.setDispatchGPS = function(x, y) {
    $.post(`https://${GetParentResourceName()}/setDispatchGPS`, JSON.stringify({ x, y }));
};

window.lockDispatch = function() {
    isDispatchLocked = !isDispatchLocked;
    const btn = $('.header-icon-btn i.fa-lock, .header-icon-btn i.fa-unlock-alt').parent();
    const icon = btn.find('i');
    
    if (isDispatchLocked) {
        icon.removeClass('fa-unlock-alt').addClass('fa-lock');
        btn.attr('title', 'Unlock Position');
        $.post(`https://${GetParentResourceName()}/lockDispatch`, JSON.stringify({ locked: true }));
    } else {
        icon.removeClass('fa-lock').addClass('fa-unlock-alt');
        btn.attr('title', 'Lock Position');
        $.post(`https://${GetParentResourceName()}/lockDispatch`, JSON.stringify({ locked: false }));
    }
};

window.toggleDispatch = function(show) {
    $.post(`https://${GetParentResourceName()}/toggleDispatch`, JSON.stringify({ show }));
};

