let nodes = [];
let connections = [];
let selectedNode = null;
let isDragging = false;
let isPanning = false;
let dragTarget = null;
let offset = { x: 0, y: 0 };

let pan = { x: 0, y: 0 };
let zoom = 1.0;
let lastMousePos = { x: 0, y: 0 };

let activePort = null;
let tempLine = null;

window.AMB_LOCALE = window.AMB_LOCALE || {};
window.ambT = function (key, fallback, vars) {
    let text = (window.AMB_LOCALE && window.AMB_LOCALE[key]) || fallback || key;
    if (vars) {
        Object.keys(vars).forEach((k) => {
            text = text.replace(new RegExp(`\\{${k}\\}`, 'g'), String(vars[k]));
        });
    }
    return text;
};

// Members UI Elements
const membersView = document.getElementById('members-view');
const playersList = document.getElementById('players-list');
const playerSearch = document.getElementById('player-search');
const memberEditor = document.getElementById('member-editor');
const selectedPlayerInfo = document.getElementById('selected-player-info');
const hireDeptSelect = document.getElementById('hire-dept-select');
const hireRankSelect = document.getElementById('hire-rank-select');

// Garage UI Elements
const garageView = document.getElementById('garage-view');
const garageVehiclesList = document.getElementById('garage-vehicles');
const garageDeptName = document.getElementById('garage-dept-name');
const garageSearchInput = document.getElementById('garage-search-input');
const vehicleCountStat = document.getElementById('vehicle-count-stat');
let currentGarageData = null;
let garageVehicles = [];

let onlinePlayers = [];
let selectedPlayer = null;
let currentTab = 'departments';
let currentEMSInvoice = null;

const canvas = document.getElementById('canvas');
const canvasContainer = document.querySelector('.canvas-container');
const canvasContent = document.getElementById('canvas-content');
const gridLayer = document.getElementById('grid-layer');
const svg = document.getElementById('connections-svg');
const app = document.getElementById('app');
const inspector = document.querySelector('.inspector');
const inspectorContent = document.getElementById('inspector-content');

function setBlurEnabled(enabled) {
    if (enabled === false) {
        document.body.classList.add('amb-disable-blur');
    } else {
        document.body.classList.remove('amb-disable-blur');
    }
}

// Message listener from FiveM
window.addEventListener('message', (event) => {
    const data = event.data;
    if (typeof data.blurEnabled === 'boolean') {
        setBlurEnabled(data.blurEnabled);
    }
    if (data.action === 'amb_setLocale') {
        window.AMB_LOCALE = data.locale || {};
    } else if (data.action === 'amb_setUISettings') {
        setBlurEnabled(data.blurEnabled !== false);
    } else if (data.action === 'amb_open') {
        app.classList.remove('hidden');
        app.style.setProperty('display', 'flex', 'important');
        if (inspector) inspector.classList.add('hidden');
        loadData(data.data);
    } else if (data.action === 'amb_placementDone') {
        app.classList.remove('hidden');
        app.style.setProperty('display', 'flex', 'important');
        const node = nodes.find(n => n.id === data.nodeId);
        if (node) {
            if (data.locType === 'spawn') {
                if (!node.spawnPoints) node.spawnPoints = [];
                node.spawnPoints[data.pointIndex] = data.coords;
            } else if (data.locType === 'delete') {
                if (!node.deletePoints) node.deletePoints = [];
                node.deletePoints[data.pointIndex] = data.coords;
            } else if (data.locType) {
                if (!node.coordsList) node.coordsList = {};
                if (node.type === 'check_in' && data.locType === 'bed' && data.pointIndex !== undefined && data.pointIndex !== null) {
                    if (!Array.isArray(node.coordsList.beds)) {
                        node.coordsList.beds = [];
                    }
                    node.coordsList.beds[data.pointIndex] = data.coords;
                    // Keep legacy single-bed key synced for backward compatibility.
                    node.coordsList.bed = node.coordsList.beds[0] || null;
                } else {
                    node.coordsList[data.locType] = data.coords;
                }

                // Store interaction type (ped or zone)
                if (data.interactionType) {
                    if (!node.interactionTypes) node.interactionTypes = {};
                    node.interactionTypes[data.locType] = data.interactionType;
                } else if (node.interactionTypes && node.interactionTypes[data.locType]) {
                    delete node.interactionTypes[data.locType];
                }
            } else {
                node.coords = data.coords;
            }
            if (selectedNode && selectedNode.id === node.id) renderInspector();
            renderCanvas();

            // Trigger local refresh so objects show up immediately for admin
            fetch(`https://${GetParentResourceName()}/amb_localRefresh`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ nodes: nodes, links: connections })
            });
        }
    } else if (data.action === 'amb_placementCancelled') {
        app.classList.remove('hidden');
        app.style.setProperty('display', 'flex', 'important');
    } else if (data.action === 'amb_doorPlacementDone') {
        app.classList.remove('hidden');
        app.style.setProperty('display', 'flex', 'important');
        const node = nodes.find(n => n.id === data.nodeId);
        if (node && node.doors && node.doors[data.doorIndex]) {
            node.doors[data.doorIndex].coords = data.coords;
            node.doors[data.doorIndex].hash = data.hash;
            if (selectedNode && selectedNode.id === node.id) renderInspector();
            renderCanvas();
        }
    } else if (data.action === 'amb_openGarage') {
        openGarage(data);
    } else if (data.action === 'amb_openBossMenu') {
        const container = document.getElementById('boss-menu-container');
        if (container) {
            container.style.setProperty('display', 'flex', 'important');
            container.classList.add('visible');
            if (typeof startMacBoot === 'function') startMacBoot();
        }
    } else if (data.action === 'amb_syncData') {
        if (data.data) loadData(data.data);
        if (data.members) window.syncedMembers = data.members;
        
        const deptWin = document.getElementById('mac-window-dept');
        if (deptWin && !deptWin.classList.contains('hidden')) {
            if (typeof window.renderDepartmentMembers === 'function') {
                window.renderDepartmentMembers(false);
            }
        }
    } else if (data.action === 'amb_showNotification') {
        window.showNotification(data.title, data.items, data.message);
    } else if (data.action === 'amb_openEMSInvoice') {
        window.openEMSInvoiceUI(data.invoice || {});
    } else if (data.action === 'amb_syncMembers') {
        window.syncedMembers = data.members;
    } else if (data.action === 'amb_syncNews') {
        window.syncedDeptNews = data.news;
    } else if (data.action === 'amb_togglePlacementHelp') {
        const container = document.getElementById('placement-help-container');
        if (container) {
            container.style.display = data.visible ? 'flex' : 'none';
            if (data.visible) {
                if (data.header) container.querySelector('.help-header span').innerText = data.header;
                if (data.confirmLabel) container.querySelector('.key-row:nth-child(1) .action').innerText = data.confirmLabel;
                if (data.rotateLabel) container.querySelector('.key-row:nth-child(2) .action').innerText = data.rotateLabel;
            }
        }
    }
});

function setEMSInvoiceText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value == null ? '' : String(value);
}

function formatEMSInvoiceMoney(value) {
    const amount = Number(value) || 0;
    return '$' + amount.toLocaleString('en-US');
}

function formatEMSInvoiceDate(timestamp) {
    const date = timestamp ? new Date(Number(timestamp) * 1000) : new Date();
    return date.toLocaleDateString('en-US', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit'
    });
}

window.openEMSInvoiceUI = function(invoice) {
    currentEMSInvoice = invoice || {};
    const container = document.getElementById('ems-invoice-container');
    if (!container) return;

    const invoiceId = currentEMSInvoice.id || '0000';
    const amount = formatEMSInvoiceMoney(currentEMSInvoice.amount);
    const dept = currentEMSInvoice.departmentLabel || currentEMSInvoice.dept || 'Emergency Medical Services';
    const reason = currentEMSInvoice.reason || 'Emergency medical care';
    const medicName = currentEMSInvoice.medicName || 'Authorized EMS Provider';

    setEMSInvoiceText('ems-invoice-number', '#' + invoiceId);
    setEMSInvoiceText('ems-invoice-date', formatEMSInvoiceDate(currentEMSInvoice.createdAt));
    setEMSInvoiceText('ems-invoice-department', dept + ' Billing Office');
    setEMSInvoiceText('ems-invoice-provider-dept', dept);
    setEMSInvoiceText('ems-invoice-patient', currentEMSInvoice.patientName || 'Patient');
    setEMSInvoiceText('ems-invoice-medic', medicName);
    setEMSInvoiceText('ems-invoice-expiry', currentEMSInvoice.expireMinutes ? `Expires in ${currentEMSInvoice.expireMinutes} minutes` : 'Due on receipt');
    setEMSInvoiceText('ems-invoice-reason', reason);
    setEMSInvoiceText('ems-invoice-code', 'EMS-' + String(invoiceId).padStart(4, '0'));
    setEMSInvoiceText('ems-invoice-line-amount', amount);
    setEMSInvoiceText('ems-invoice-total', amount);
    setEMSInvoiceText('ems-invoice-signature', medicName);

    container.classList.remove('hidden');
};

window.closeEMSInvoiceUI = function(sendClose) {
    const container = document.getElementById('ems-invoice-container');
    if (container) container.classList.add('hidden');
    if (sendClose !== false) {
        fetch(`https://${GetParentResourceName()}/amb_close`, {
            method: 'POST'
        });
    }
};

window.payEMSInvoiceUI = function() {
    if (!currentEMSInvoice || !currentEMSInvoice.id) return;
    const invoiceId = currentEMSInvoice.id;
    window.closeEMSInvoiceUI(false);
    fetch(`https://${GetParentResourceName()}/amb_payEMSInvoice`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ invoiceId })
    });
};

window.declineEMSInvoiceUI = function() {
    if (!currentEMSInvoice || !currentEMSInvoice.id) return;
    const invoiceId = currentEMSInvoice.id;
    window.closeEMSInvoiceUI(false);
    fetch(`https://${GetParentResourceName()}/amb_declineEMSInvoice`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ invoiceId })
    });
};

// --- NOTIFICATION SYSTEM ---
window.showNotification = function(title, items, message) {
    const container = document.getElementById('notification-container');
    if (!container) return;

    const notification = document.createElement('div');
    notification.className = 'custom-notification';
    
    let itemsHtml = '';
    if (items && Array.isArray(items) && items.length > 0) {
        itemsHtml = items.map(item => `
            <div class="notify-item">
                <label>${item.label}</label>
                <span>${item.value}</span>
            </div>
        `).join('');
    } else if (message) {
        itemsHtml = `<div class="notify-body-text">${message}</div>`;
    }

    notification.innerHTML = `
        <div class="notify-header">
            <i class="fas fa-kit-medical"></i>
            <span>MEDICAL DISPATCH</span>
        </div>
        <div class="notify-body">
            <div class="notify-title">${title}</div>
            ${itemsHtml}
        </div>
    `;

    container.appendChild(notification);

    // Auto-remove after 7 seconds
    setTimeout(() => {
        notification.classList.add('fadeOut');
        setTimeout(() => notification.remove(), 400);
    }, 7000);
};

function openGarage(data) {
    currentGarageData = data;
    garageVehicles = data.vehicles || [];
    garageView.style.display = 'flex';
    garageView.classList.remove('hidden');
    garageDeptName.innerText = data.deptName;
    
    // Automatically use the first spawn point for now, or we could add a logic to find the free one
    currentGarageData.spawnPoint = data.spawnPoints && data.spawnPoints[0];
    
    renderGarageVehicles(garageVehicles);
}

function renderGarageVehicles(vehicles) {
    garageVehiclesList.innerHTML = '';
    if (vehicleCountStat) vehicleCountStat.innerText = `${vehicles.length} UNITS`;

    vehicles.forEach(veh => {
        const card = document.createElement('div');
        card.className = 'minimal-vehicle-card';
        
        const subtext = veh.isImpounded ? `OWNER: ${veh.owner}` : `CHASSIS: ${veh.model.toUpperCase()}`;
        const reasonText = veh.isImpounded ? `<div class="meta-info-small" style="color: rgba(255,255,255,0.4); margin-top: 2px;">REASON: ${veh.seizureReason || 'N/A'}</div>` : '';
        const feeText = veh.isImpounded && veh.seizurePrice > 0 ? `<div style="color: #ff9500; font-weight: bold; margin-top: 4px;" class="meta-info-small">RETRIEVAL FEE: $${veh.seizurePrice}</div>` : '';
        
        card.innerHTML = `
            <div class="vehicle-main-info">
                <span class="vehicle-label-text">${veh.label}</span>
                <span class="vehicle-model-text">${subtext}</span>
                ${reasonText}
                ${feeText}
            </div>
            <div class="vehicle-action-area">
                <div class="vehicle-status-minimal">${veh.isImpounded ? 'IMPOUNDED' : 'READY'}</div>
                <div class="spawn-icon-btn">
                    <i class="fas fa-chevron-right"></i>
                </div>
            </div>
        `;
        
        card.onclick = () => {
            spawnVehicle(veh);
        };
        
        garageVehiclesList.appendChild(card);
    });
}

if (garageSearchInput) {
    garageSearchInput.addEventListener('input', (e) => {
        const search = e.target.value.toLowerCase();
        const filtered = garageVehicles.filter(v => 
            v.label.toLowerCase().includes(search) || 
            v.model.toLowerCase().includes(search) ||
            (v.owner && v.owner.toLowerCase().includes(search)) ||
            (v.plate && v.plate.toLowerCase().includes(search))
        );
        renderGarageVehicles(filtered);
    });
}

if (document.getElementById('close-garage-btn-minimal')) {
    document.getElementById('close-garage-btn-minimal').onclick = closeGarage;
}
window.closeGarage = closeGarage;

function spawnVehicle(vehData) {
    // Find a free spawn point from the list
    fetch(`https://${GetParentResourceName()}/amb_spawnVehicle`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
            model: vehData.model,
            plate: vehData.plate,
            props: vehData.props,
            isImpounded: vehData.isImpounded,
            spawnPoints: currentGarageData.spawnPoints // Pass ALL points to find a free one
        })
    });
    closeGarage();
}

function closeGarage() {
    garageView.style.display = 'none';
    garageView.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/amb_close`, {
        method: 'POST'
    });
}

function saveData() {
    // Sanitize nodes before saving to prevent Lua [] vs {} confusion
    const sanitizedNodes = nodes.map(node => {
        if (node.type === 'permission') {
            if (!node.rankPerms || Array.isArray(node.rankPerms)) {
                node.rankPerms = {};
            }
            // Ensure every rank inside is also an object
            Object.keys(node.rankPerms).forEach(key => {
                if (Array.isArray(node.rankPerms[key])) {
                    node.rankPerms[key] = {};
                }
            });
        }
        return node;
    });
    
    const data = { ...currentFullData, nodes: sanitizedNodes, links: connections, pan };
    fetch(`https://${GetParentResourceName()}/amb_save`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    });
}

let currentFullData = {};

function loadData(data) {
    currentFullData = data || {};
    if (!data) {
        nodes = [];
        connections = [];
        pan = { x: 0, y: 0 };
    } else {
        nodes = data.nodes || [];
        connections = data.links || [];
        pan = data.pan || { x: 0, y: 0 };
    }
    
    zoom = 1.0;
    
    // Reset member selection UI on load
    selectedPlayer = null;
    if (selectedPlayerInfo) selectedPlayerInfo.style.display = 'flex';
    if (memberEditor) {
        memberEditor.classList.add('hidden');
        memberEditor.style.display = 'none';
    }
    
    updateCanvasTransform();
    renderCanvas();
}

function updateCanvasTransform() {
    if (canvasContent) {
        canvasContent.style.transform = `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`;
    }
    if (gridLayer) {
        gridLayer.style.transform = `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`;
    }
}

function renderCanvas() {
    canvasContent.querySelectorAll('.node').forEach(n => n.remove());
    nodes.forEach(node => createNodeElement(node));
    drawConnections();
}

function createNodeElement(node) {
    const el = document.createElement('div');
    el.className = 'node';
    el.id = `node-${node.id}`;
    el.style.left = `${node.x}px`;
    el.style.top = `${node.y}px`;
    
    let icon = 'building';
    if (node.type === 'rank') icon = 'id-badge';
    else if (node.type === 'permission') icon = 'key';
    else if (node.type === 'location') icon = 'map-marker-alt';
    else if (node.type === 'wardrobe') icon = 'tshirt';
    else if (node.type === 'inventory') icon = 'box-open';
    else if (node.type === 'boss_menu') icon = 'briefcase';
    else if (node.type === 'vehicle') icon = 'car-side';
    else if (node.type === 'helipad') icon = 'helicopter';
    else if (node.type === 'door') icon = 'door-open';
    else if (node.type === 'xray') icon = 'x-ray';
    else if (node.type === 'check_in') icon = 'user-md';
    else if (node.type === 'ceiling_monitor') icon = 'tv';
    
    let extraInfo = '';
    if (node.type === 'rank') {
        if (node.ranks && node.ranks.length > 0) {
            extraInfo = `<div class="node-info">${node.ranks.length} RANKS CONFIGURED</div>`;
        } else {
            extraInfo = `<div class="node-info">LVL ${node.level} | $${node.payment}</div>`;
        }
    } else if (node.type === 'permission') {
        extraInfo = `<div class="node-info">PERMISSIONS CONFIGURED</div>`;
    } else if (node.type === 'boss_menu') {
        const hasCoords = !!node.coords;
        extraInfo = `<div class="node-info">${hasCoords ? 'LOCATION SET' : 'NO LOCATION'}</div>`;
    } else if (node.type === 'inventory') {
        const hasCoords = !!node.coords;
        extraInfo = `<div class="node-info">${hasCoords ? 'LOCATION SET' : 'NO LOCATION'}</div>`;
    } else if (node.type === 'location') {
        const count = Object.keys(node.coordsList || {}).length;
        extraInfo = `<div class="node-info">${count} LOCATIONS SET</div>`;
    } else if (node.type === 'wardrobe') {
        const hasCoords = !!node.coords;
        const outfitCount = Object.keys(node.outfits || {}).length;
        extraInfo = `<div class="node-info">${hasCoords ? 'LOCATION SET' : 'NO LOCATION'} | ${outfitCount} OUTFITS</div>`;
    } else if (node.type === 'vehicle' || node.type === 'helipad') {
        const count = Object.keys(node.coordsList || {}).length;
        const vehCount = (node.vehicles || []).length;
        extraInfo = `<div class="node-info">${count} POINTS | ${vehCount} ${node.type === 'helipad' ? 'AIRCRAFT' : 'VEHICLES'}</div>`;
    } else if (node.type === 'door') {
        const count = (node.doors || []).length;
        extraInfo = `<div class="node-info">${count} DOORS CONFIGURED</div>`;
    } else if (node.type === 'xray') {
        const hasPC = !!(node.coordsList && node.coordsList.pc);
        const hasBed = !!(node.coordsList && node.coordsList.bed);
        extraInfo = `<div class="node-info">${hasPC ? 'PC' : 'NO PC'} | ${hasBed ? 'BED' : 'NO BED'}</div>`;
    }     else if (node.type === 'check_in') {
        const hasCheckin = !!(node.coordsList && node.coordsList.checkin);
        const bedCount = (node.coordsList && Array.isArray(node.coordsList.beds))
            ? node.coordsList.beds.filter(Boolean).length
            : (node.coordsList && node.coordsList.bed ? 1 : 0);
        extraInfo = `<div class="node-info">${hasCheckin ? 'CHECK-IN' : 'NO CHECK-IN'} | BEDS: ${bedCount}</div>`;
    } else if (node.type === 'ceiling_monitor') {
        const hasMonitor = !!(node.coordsList && node.coordsList.monitor);
        const hasBed = !!(node.coordsList && node.coordsList.bed);
        extraInfo = `<div class="node-info">${hasMonitor ? 'MONITOR' : 'NO MONITOR'} | ${hasBed ? 'BED' : 'NO BED'}</div>`;
    }

    const headerType = node.type === 'boss_menu' ? 'BOSS MENU' : (node.type === 'check_in' ? 'CHECK-IN' : node.type.toUpperCase());

    el.innerHTML = `
        <div class="node-header"><i class="fas fa-${icon}"></i> ${headerType}</div>
        <div class="node-content">
            <div class="node-label">${node.label}</div>
            ${extraInfo}
        </div>
        ${(node.type !== 'permission' && node.type !== 'vehicle' && node.type !== 'helipad' && node.type !== 'door' && node.type !== 'boss_menu') ? '<div class="port port-out" data-id="'+node.id+'"></div>' : ''}
        ${node.type !== 'department' ? '<div class="port port-in" data-id="'+node.id+'"></div>' : ''}
    `;

    // Add right-click to disconnect ports
    el.querySelectorAll('.port').forEach(port => {
        port.addEventListener('contextmenu', (e) => {
            e.preventDefault();
            e.stopPropagation();
            const portId = port.dataset.id;
            const isOut = port.classList.contains('port-out');
            
            if (isOut) {
                connections = connections.filter(c => c.from !== portId);
            } else {
                connections = connections.filter(c => c.to !== portId);
            }
            
            drawConnections();
        });
    });

    el.addEventListener('mousedown', (e) => {
        if (e.target.classList.contains('port')) return;
        e.stopPropagation();
        selectNode(node);
        isDragging = true;
        dragTarget = el;
        
        // Calculate offset in canvas space
        const rect = canvas.getBoundingClientRect();
        offset.x = (e.clientX - rect.left - pan.x) / zoom - node.x;
        offset.y = (e.clientY - rect.top - pan.y) / zoom - node.y;
    });

    canvasContent.appendChild(el);
}

function selectNode(node) {
    selectedNode = node;
    document.querySelectorAll('.node').forEach(n => n.classList.remove('selected'));
    const nodeEl = document.getElementById(`node-${node.id}`);
    if (nodeEl) nodeEl.classList.add('selected');
    
    if (inspector) inspector.classList.remove('hidden');
    renderInspector();
}

function renderInspector() {
    if (!selectedNode) return;
    
    let html = `
        <div class="field">
            <label>Display Name</label>
            <input type="text" value="${selectedNode.label}" onchange="updateNode('label', this.value)">
        </div>
    `;

    if (selectedNode.type === 'department') {
        html += `
            <div class="field">
                <label>Framework Job (QB/ESX)</label>
                <input type="text" value="${selectedNode.frameworkJob || ''}" placeholder="e.g. ambulance, fire" onchange="updateNode('frameworkJob', this.value)">
            </div>
            <div class="field">
                <label>Blip Name</label>
                <input type="text" value="${selectedNode.blipName || selectedNode.label}" onchange="updateNode('blipName', this.value)">
            </div>
            <div class="field">
                <label>ICON SELECT</label>
                <div class="blip-grid">
                    ${[60, 58, 61, 526, 487, 175, 525, 429, 410, 408, 188, 570].map(id => `
                        <div class="blip-item ${selectedNode.blipId === id ? 'active' : ''}" onclick="updateNode('blipId', ${id})">
                            <img src="img/${id}.png" onerror="this.src='img/fallback.webp'">
                        </div>
                    `).join('')}
                </div>
            </div>
            <div class="field">
                <label>COLOR PALETTE</label>
                <div class="color-grid">
                    ${[3, 38, 5, 2, 1, 18, 17, 21, 25, 29, 31, 35].map(color => `
                        <div class="color-item blip-color-${color} ${selectedNode.blipColor === color ? 'active' : ''}" 
                             style="background-color: ${getBlipHex(color)}; color: ${getBlipHex(color)}"
                             onclick="updateNode('blipColor', ${color})">
                        </div>
                    `).join('')}
                </div>
            </div>
            <div class="field">
                <label>Location (Vector3)</label>
                <div class="input-with-btn">
                    <input type="text" id="node-coords" value="${selectedNode.coords ? `${selectedNode.coords.x.toFixed(2)}, ${selectedNode.coords.y.toFixed(2)}, ${selectedNode.coords.z.toFixed(2)}${selectedNode.coords.h ? `, H: ${selectedNode.coords.h.toFixed(1)}` : ''}` : '0, 0, 0'}" readonly>
                    <button class="pick-btn-small" onclick="pickLocation()"><i class="fas fa-crosshairs"></i></button>
                </div>
            </div>
        `;
    }

    if (selectedNode.type === 'rank') {
        html += `<div class="rank-list-editor">
            <label class="field-label-small">Department Ranks</label>`;
        
        if (selectedNode.ranks) {
            selectedNode.ranks.forEach((rank, index) => {
            html += `
                <div class="rank-row-editable">
                    <div class="field field-name">
                        <input type="text" value="${rank.name}" placeholder="Name" onchange="updateRank(${index}, 'name', this.value)">
                    </div>
                    <div class="field field-level">
                        <input type="number" value="${rank.level}" placeholder="LVL" onchange="updateRank(${index}, 'level', parseInt(this.value))">
                    </div>
                    <div class="field field-pay">
                        <input type="number" value="${rank.pay}" placeholder="Pay" onchange="updateRank(${index}, 'pay', parseInt(this.value))">
                    </div>
                    <button class="delete-rank-btn" onclick="deleteRank(${index})"><i class="fas fa-times"></i></button>
                </div>
            `;
        });

        html += `
            <div class="add-preset-btn" onclick="addRankToList()" style="margin-top: 15px;">
                <i class="fas fa-plus"></i> ADD NEW RANK
            </div>
        </div>`;

        // Boss Menu Permissions Category
        html += `
            <div class="perm-rank-list" style="margin-top: 25px; border-top: 1px solid var(--border); padding-top: 20px;">
                <label class="field-label-small" style="margin-bottom: 15px;">BOSS MENU PERMISSIONS</label>
                <div class="behavior-flags" style="display: flex; flex-direction: column; gap: 10px;">
                    ${selectedNode.ranks.map((rank, index) => `
                        <div class="flag-item ${rank.bossMenu ? 'active' : ''}" onclick="toggleRankBossMenu(${index})" style="background: rgba(255,255,255,0.02); padding: 10px; border-radius: 6px; justify-content: space-between;">
                            <div class="flag-label" style="font-weight: bold; color: #fff;">${rank.name || 'Rank ' + index}</div>
                            <div style="display: flex; align-items: center; gap: 10px;">
                                <span class="meta-info-small" style="font-weight: bold; color: var(--accent); opacity: 0.8;">BOSS ACCESS</span>
                                <div class="checkbox-custom">${rank.bossMenu ? 'X' : ''}</div>
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
        }
    }

    // --- NEW PERMISSION NODE INSPECTOR ---
    if (selectedNode.type === 'permission') {
        const linkedRankNode = findLinkedRankNode(selectedNode.id);
        
        if (!linkedRankNode) {
            html += `
                <div class="info-box" style="border-color: #ffb70044; color: #ffb700; background: rgba(255, 183, 0, 0.05);">
                    <i class="fas fa-link"></i> LINK A RANK NODE TO MANAGE PERMISSIONS
                </div>
            `;
        } else if (linkedRankNode.ranks && linkedRankNode.ranks.length > 0) {
            html += `<div class="perm-rank-list">
                <label class="field-label-small">RANK ACCESS CONTROL</label>`;
            
            // Define the core features
            const featureList = ['Duty', 'Garage', 'Inventory', 'Stash', 'Boss Menu', 'X-Ray'];
            
            // Ensure rankPerms is a clean object
            if (!selectedNode.rankPerms || Array.isArray(selectedNode.rankPerms)) {
                selectedNode.rankPerms = {};
            }

            linkedRankNode.ranks.forEach(rank => {
                const rankKey = `rank_${rank.level}`; 
                // CRITICAL: Ensure rank entry is an object, not an array
                if (!selectedNode.rankPerms[rankKey] || Array.isArray(selectedNode.rankPerms[rankKey])) {
                    selectedNode.rankPerms[rankKey] = {};
                }
                
                html += `
                    <div class="perm-rank-group" style="margin-bottom: 20px; background: rgba(0,0,0,0.2); padding: 12px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.03);">
                        <div style="font-weight: bold; color: var(--accent); margin-bottom: 10px; font-size: 11px; display: flex; justify-content: space-between;">
                            <span>${rank.name.toUpperCase()}</span>
                            <span style="color: var(--text-dim);">LVL ${rank.level}</span>
                        </div>
                        <div class="behavior-flags" style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px;">
                            ${featureList.map(feature => {
                                const isChecked = selectedNode.rankPerms[rankKey][feature] === true;
                                return `
                                    <div class="flag-item ${isChecked ? 'active' : ''}" 
                                         onclick="toggleNewPermission('${selectedNode.id}', '${rankKey}', '${feature}')"
                                         style="padding: 6px 10px; font-size: 10px;">
                                        <div class="checkbox-custom">${isChecked ? 'X' : ''}</div>
                                        <div class="flag-label">${feature}</div>
                                    </div>
                                `;
                            }).join('')}
                        </div>
                    </div>
                `;
            });
            html += `</div>`;
        }
    }

    if (selectedNode.type === 'pharmacy') {
        const coordStr = selectedNode.coords ? `${selectedNode.coords.x.toFixed(1)}, ${selectedNode.coords.y.toFixed(1)}, ${selectedNode.coords.z.toFixed(1)}` : 'NO LOCATION SET';
        
        html += `
            <div class="field">
                <label>PHARMACY TERMINAL LOCATION</label>
                <div class="input-with-btn">
                    <input type="text" value="${coordStr}" readonly class="coord-input-small">
                    <button class="pick-btn-small" onclick="pickLocation()">
                        <i class="fas fa-crosshairs"></i>
                    </button>
                </div>
            </div>
            <div class="info-box" style="margin-top: 10px;">
                <i class="fas fa-info-circle"></i> Revenue from this pharmacy will be sent to the linked department's finance system.
            </div>
        `;
    }

    if (selectedNode.type === 'wardrobe') {
        const coordStr = selectedNode.coords ? `${selectedNode.coords.x.toFixed(1)}, ${selectedNode.coords.y.toFixed(1)}, ${selectedNode.coords.z.toFixed(1)}` : 'NO LOCATION SET';
        
        html += `
            <div class="field">
                <label>WARDROBE LOCATION</label>
                <div class="input-with-btn">
                    <input type="text" value="${coordStr}" readonly class="coord-input-small">
                    <button class="pick-btn-small" onclick="pickLocation()">
                        <i class="fas fa-crosshairs"></i>
                    </button>
                </div>
            </div>
        `;

        const linkedRank = findLinkedRankNode(selectedNode.id);
        if (!linkedRank) {
            html += `<div class="info-box">Link a Rank node to this node to manage rank-specific outfits.</div>`;
        } else if (linkedRank.ranks && linkedRank.ranks.length > 0) {
            if (!selectedNode.outfits || Array.isArray(selectedNode.outfits)) selectedNode.outfits = {};
            
            html += `<div class="rank-list-editor" style="margin-top: 20px;">
                <label class="field-label-small">RANK OUTFITS</label>`;
            
            linkedRank.ranks.forEach((rank, index) => {
                const rankKey = `rank_${rank.level}`;
                const outfit = selectedNode.outfits[rankKey] || {};
                const hasOutfit = Object.keys(outfit).length > 0;
                
                html += `
                    <div class="door-config-item" style="margin-bottom: 15px; padding: 12px; background: rgba(0,0,0,0.2); border-radius: 8px; border: 1px solid ${hasOutfit ? 'var(--accent)' : 'rgba(255,255,255,0.03)'};">
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
                            <span style="font-weight: bold; color: #fff;">${rank.name}</span>
                            <span class="meta-info-small">LEVEL ${rank.level}</span>
                        </div>
                        
                        <div class="field" style="margin-bottom: 10px;">
                            <label class="field-label-tiny">PANTS (Component 4)</label>
                            <div style="display: flex; gap: 5px;">
                                <input type="number" value="${outfit.pants?.item || 0}" placeholder="ID" onchange="updateOutfit('${rankKey}', 'pants', 'item', this.value)" style="flex: 1;">
                                <input type="number" value="${outfit.pants?.texture || 0}" placeholder="Tex" onchange="updateOutfit('${rankKey}', 'pants', 'texture', this.value)" style="flex: 1;">
                            </div>
                        </div>
                        
                        <div class="field" style="margin-bottom: 10px;">
                            <label class="field-label-tiny">SHIRT (Component 11)</label>
                            <div style="display: flex; gap: 5px;">
                                <input type="number" value="${outfit.shirt?.item || 0}" placeholder="ID" onchange="updateOutfit('${rankKey}', 'shirt', 'item', this.value)" style="flex: 1;">
                                <input type="number" value="${outfit.shirt?.texture || 0}" placeholder="Tex" onchange="updateOutfit('${rankKey}', 'shirt', 'texture', this.value)" style="flex: 1;">
                            </div>
                        </div>

                        <div class="field" style="margin-bottom: 10px;">
                            <label class="field-label-tiny">VEST (Component 9)</label>
                            <div style="display: flex; gap: 5px;">
                                <input type="number" value="${outfit.vest?.item || 0}" placeholder="ID" onchange="updateOutfit('${rankKey}', 'vest', 'item', this.value)" style="flex: 1;">
                                <input type="number" value="${outfit.vest?.texture || 0}" placeholder="Tex" onchange="updateOutfit('${rankKey}', 'vest', 'texture', this.value)" style="flex: 1;">
                            </div>
                        </div>

                        <div class="field" style="margin-bottom: 10px;">
                            <label class="field-label-tiny">SHOES (Component 6)</label>
                            <div style="display: flex; gap: 5px;">
                                <input type="number" value="${outfit.shoes?.item || 0}" placeholder="ID" onchange="updateOutfit('${rankKey}', 'shoes', 'item', this.value)" style="flex: 1;">
                                <input type="number" value="${outfit.shoes?.texture || 0}" placeholder="Tex" onchange="updateOutfit('${rankKey}', 'shoes', 'texture', this.value)" style="flex: 1;">
                            </div>
                        </div>

                        <div class="field" style="margin-bottom: 0;">
                            <label class="field-label-tiny">HAT (Prop 0)</label>
                            <div style="display: flex; gap: 5px;">
                                <input type="number" value="${outfit.hat?.item || -1}" placeholder="ID" onchange="updateOutfit('${rankKey}', 'hat', 'item', this.value)" style="flex: 1;">
                                <input type="number" value="${outfit.hat?.texture || 0}" placeholder="Tex" onchange="updateOutfit('${rankKey}', 'hat', 'texture', this.value)" style="flex: 1;">
                            </div>
                        </div>
                    </div>
                `;
            });
            html += `</div>`;
        }
    }

    if (selectedNode.type === 'location') {
        const locations = [
            { id: 'duty', label: 'DUTY TOGGLE', icon: 'user-shield' },
            { id: 'stash', label: 'STASH', icon: 'box-open' },
            { id: 'garage', label: 'GARAGE MENU', icon: 'car' },
            { id: 'helipad', label: 'HELIPAD MENU', icon: 'helicopter' },
            { id: 'inventory', label: 'INVENTORY', icon: 'box-open' },
            { id: 'boss_menu', label: 'BOSS MENU', icon: 'briefcase' }
        ];

        if (!selectedNode.coordsList || Array.isArray(selectedNode.coordsList)) selectedNode.coordsList = {};

        html += locations.map(loc => {
            const coords = selectedNode.coordsList[loc.id];
            const coordStr = coords ? `${coords.x.toFixed(1)}, ${coords.y.toFixed(1)}, ${coords.z.toFixed(1)}${coords.h ? ` | H: ${coords.h.toFixed(1)}` : ''}` : 'NO LOCATION SET';
            const interactionType = (selectedNode.interactionTypes && selectedNode.interactionTypes[loc.id]) || 'zone';
            
            return `
                <div class="field">
                    <label>${loc.label} ${interactionType === 'ped' ? '<span style="color:var(--accent); font-size:9px;">(PED)</span>' : ''}</label>
                    <div class="input-with-btn">
                        <input type="text" value="${coordStr}" readonly class="coord-input-small">
                        <button class="pick-btn-small" onclick="pickLocation('${loc.id}')" title="Set Zone Interaction">
                            <i class="fas fa-crosshairs"></i>
                        </button>
                        <button class="pick-btn-small ${interactionType === 'ped' ? 'active' : ''}" onclick="pickLocation('${loc.id}', null, 'ped')" title="Set Ped Interaction">
                            <i class="fas fa-user-shield"></i>
                        </button>
                    </div>
                </div>
            `;
        }).join('');

        // Link Status for Garage
        const isLinkedToVehicle = connections.some(c => {
            const node = nodes.find(n => n.id === c.from || n.id === c.to);
            return (c.from === selectedNode.id || c.to === selectedNode.id) && 
                   nodes.some(n => (n.id === c.from || n.id === c.to) && (n.type === 'vehicle' || n.type === 'helipad'));
        });

        if (!isLinkedToVehicle) {
            html += `
                <div class="info-box" style="margin-top: 10px; border-color: #ff444444; color: #ff4444; background: rgba(255, 68, 68, 0.05);">
                    <i class="fas fa-exclamation-triangle"></i> LINK TO VEHICLE/HELIPAD NODE FOR MENU TO WORK
                </div>
            `;
        } else {
            html += `
                <div class="info-box" style="margin-top: 10px; border-color: var(--accent); color: var(--accent); background: var(--accent-dim);">
                    <i class="fas fa-check-circle"></i> VEHICLE/HELIPAD NODE LINKED
                </div>
            `;
        }
    }

    if (selectedNode.type === 'boss_menu') {
        const coordStr = selectedNode.coords ? `${selectedNode.coords.x.toFixed(1)}, ${selectedNode.coords.y.toFixed(1)}, ${selectedNode.coords.z.toFixed(1)}${selectedNode.coords.h ? ` | H: ${selectedNode.coords.h.toFixed(1)}` : ''}` : 'NO LOCATION SET';
        html += `
            <div class="field">
                <label>Boss Menu Location</label>
                <div class="input-with-btn">
                    <input type="text" value="${coordStr}" readonly class="coord-input-small">
                    <button class="pick-btn-small" onclick="pickLocation()"><i class="fas fa-crosshairs"></i></button>
                </div>
            </div>
            <div class="info-box" style="margin-top: 10px; border-color: var(--accent); color: var(--accent); background: var(--accent-dim);">
                <i class="fas fa-info-circle"></i> Place the interaction point for the Boss Menu (iMac).
            </div>
        `;
    }

    if (selectedNode.type === 'inventory') {
        const coordStr = selectedNode.coords ? `${selectedNode.coords.x.toFixed(1)}, ${selectedNode.coords.y.toFixed(1)}, ${selectedNode.coords.z.toFixed(1)}` : 'NO LOCATION SET';
        
            html += `
            <div class="field">
                <label>Inventory Location</label>
                        <div class="input-with-btn">
                    <input type="text" value="${coordStr}" readonly class="coord-input-small">
                    <button class="pick-btn-small" onclick="pickLocation()"><i class="fas fa-crosshairs"></i></button>
                    </div>
                </div>
            `;

        // Find the department this inventory is linked to
        const getLinkedDepartment = (nodeId) => {
            const visited = new Set([nodeId]);
            const queue = [nodeId];
            while (queue.length > 0) {
                const current = queue.shift();
                const neighbors = connections
                    .filter(c => c.from === current || c.to === current)
                    .map(c => c.from === current ? c.to : c.from);
                
                for (const neighborId of neighbors) {
                    if (!visited.has(neighborId)) {
                        const node = nodes.find(n => n.id === neighborId);
                        if (node) {
                            if (node.type === 'department') return node;
                            visited.add(neighborId);
                            queue.push(neighborId);
                        }
                    }
                }
            }
            return null;
        };

        const linkedDept = getLinkedDepartment(selectedNode.id);

        if (!linkedDept) {
            html += `
                <div class="info-box" style="margin-top: 10px; border-color: #ff444444; color: #ff4444; background: rgba(255, 68, 68, 0.05);">
                    <i class="fas fa-exclamation-triangle"></i> NOT LINKED TO A DEPARTMENT
                </div>
            `;
        } else {
        html += `
            <div class="info-box" style="margin-top: 10px; border-color: var(--accent); color: var(--accent); background: var(--accent-dim);">
                    <i class="fas fa-check-circle"></i> LINKED TO: ${linkedDept.label.toUpperCase()}
            </div>
        `;
        }
    }

    if (selectedNode.type === 'vehicle' || selectedNode.type === 'helipad') {
        if (!selectedNode.coordsList || Array.isArray(selectedNode.coordsList)) selectedNode.coordsList = {};
        if (!selectedNode.spawnPoints) selectedNode.spawnPoints = [];
        if (!selectedNode.deletePoints) selectedNode.deletePoints = [];

        html += `
            <div class="rank-list-editor" style="margin-top: 10px;">
                <label class="field-label-small" style="margin-bottom: 15px;">REGULAR SPAWN LOCATIONS</label>
                ${selectedNode.spawnPoints.map((p, index) => {
                    const coordStr = p ? `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}` : 'NO LOCATION SET';
                    return `
                        <div class="door-config-item" style="margin-bottom: 15px; padding: 12px; background: rgba(0,0,0,0.2); border-radius: 8px; border: 1px solid rgba(255,255,255,0.03);">
                            <div class="field" style="margin-bottom: 0;">
                                <label class="field-label-tiny">WORLD POSITION (POINT ${index + 1})</label>
                                <div class="input-with-btn">
                                    <input type="text" value="${coordStr}" readonly class="coord-input-small">
                                    <button class="pick-btn-small" onclick="pickLocation('spawn', ${index})"><i class="fas fa-crosshairs"></i></button>
                                    <button class="delete-rank-btn" onclick="deletePoint('spawn', ${index})" style="margin-left: 8px;"><i class="fas fa-trash"></i></button>
                                </div>
                            </div>
                        </div>
                    `;
                }).join('')}
                <div class="add-preset-btn" onclick="addPoint('spawn')" style="margin-top: 5px;">
                    <i class="fas fa-plus"></i> ADD SPAWN POINT
                </div>
            </div>

            <div class="rank-list-editor" style="margin-top: 25px;">
                <label class="field-label-small" style="margin-bottom: 15px;">STORE LOCATIONS (DELETE)</label>
                ${selectedNode.deletePoints.map((p, index) => {
                    const coordStr = p ? `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}` : 'NO LOCATION SET';
                    return `
                        <div class="door-config-item" style="margin-bottom: 15px; padding: 12px; background: rgba(0,0,0,0.2); border-radius: 8px; border: 1px solid rgba(255,255,255,0.03);">
                            <div class="field" style="margin-bottom: 0;">
                                <label class="field-label-tiny">STORE POINT ${index + 1}</label>
                                <div class="input-with-btn">
                                    <input type="text" value="${coordStr}" readonly class="coord-input-small">
                                    <button class="pick-btn-small" onclick="pickLocation('delete', ${index})"><i class="fas fa-crosshairs"></i></button>
                                    <button class="delete-rank-btn" onclick="deletePoint('delete', ${index})" style="margin-left: 8px;"><i class="fas fa-trash"></i></button>
                                </div>
                            </div>
                        </div>
                    `;
                }).join('')}
                <div class="add-preset-btn" onclick="addPoint('delete')" style="margin-top: 5px;">
                    <i class="fas fa-plus"></i> ADD STORE POINT
                </div>
            </div>
        `;

        // Vehicle List Management
        if (!selectedNode.vehicles) selectedNode.vehicles = [];
        
        html += `<div class="rank-list-editor" style="margin-top: 20px;">
            <label class="field-label-small">DEPARTMENT ${selectedNode.type === 'helipad' ? 'AIRCRAFT' : 'VEHICLES'}</label>`;
        
        selectedNode.vehicles.forEach((veh, index) => {
            html += `
                <div class="door-config-item" style="margin-bottom: 20px; padding: 12px; background: rgba(0,0,0,0.2); border-radius: 8px; border: 1px solid rgba(255,255,255,0.03);">
                    <div class="field" style="margin-bottom: 10px;">
                        <label class="field-label-tiny">VEHICLE LABEL</label>
                        <input type="text" value="${veh.label}" placeholder="Example: Crown Victoria" onchange="updateVehicleInfo(${index}, 'label', this.value)">
                    </div>
                    <div class="field" style="margin-bottom: 0;">
                        <label class="field-label-tiny">SPAWN CODE / MODEL</label>
                        <div class="input-with-btn">
                            <input type="text" value="${veh.model}" placeholder="Example: vic" onchange="updateVehicleInfo(${index}, 'model', this.value)">
                            <button class="delete-rank-btn" onclick="deleteVehicleFromNode(${index})" style="margin-left: 8px; width: 38px; height: 38px;">
                                <i class="fas fa-trash"></i>
                            </button>
                        </div>
                    </div>
                </div>
            `;
        });

        html += `
            <div class="add-preset-btn" onclick="addVehicleToNode()" style="margin-top: 15px;">
                <i class="fas fa-plus"></i> ADD NEW VEHICLE
            </div>
        </div>`;
    }

    if (selectedNode.type === 'door') {
        if (!selectedNode.doors) selectedNode.doors = [];
        
        html += `<div class="rank-list-editor">
            <label class="field-label-small" style="margin-bottom: 15px;">CONFIGURED DOORS</label>`;
        
        selectedNode.doors.forEach((door, index) => {
            const coordStr = door.coords ? `${door.coords.x.toFixed(1)}, ${door.coords.y.toFixed(1)}, ${door.coords.z.toFixed(1)}` : 'NO DOOR SELECTED';
            html += `
                <div class="door-config-item" style="margin-bottom: 25px; padding: 12px; background: rgba(0,0,0,0.2); border-radius: 8px; border: 1px solid rgba(255,255,255,0.03);">
                    <div class="field" style="margin-bottom: 10px;">
                        <label class="field-label-tiny">DOOR LABEL</label>
                        <input type="text" value="${door.label || 'Door ' + (index + 1)}" placeholder="Example: Front Entrance" onchange="updateDoorInfo(${index}, 'label', this.value)" style="height: 38px;">
                    </div>
                    <div class="field" style="margin-bottom: 0;">
                        <label class="field-label-tiny">WORLD POSITION & SELECTION</label>
                        <div class="input-with-btn">
                            <input type="text" value="${coordStr}" readonly class="coord-input-small" style="height: 38px;">
                            <button class="pick-btn-small" onclick="pickDoorLocation(${index})" style="width: 38px; height: 38px;">
                                <i class="fas fa-crosshairs"></i>
                            </button>
                            <button class="delete-rank-btn" onclick="deleteDoorFromNode(${index})" style="margin-left: 8px; width: 38px; height: 38px;">
                                <i class="fas fa-trash"></i>
                            </button>
                        </div>
                    </div>
                    ${door.hash ? `<div class="meta-info-small" style="color: var(--accent); margin-top: 8px; opacity: 0.6; font-family: monospace;">HASH: ${door.hash}</div>` : ''}
                </div>
            `;
        });

        html += `
            <div class="add-preset-btn" onclick="addDoorToNode()" style="margin-top: 10px;">
                <i class="fas fa-plus"></i> ADD NEW DOOR
            </div>
        </div>`;
    }

    if (selectedNode.type === 'xray') {
        const locations = [
            { id: 'pc', label: 'X-RAY COMPUTER', icon: 'desktop' },
            { id: 'bed', label: 'SCAN BED / ROOM', icon: 'bed' }
        ];

        if (!selectedNode.coordsList || Array.isArray(selectedNode.coordsList)) selectedNode.coordsList = {};

        html += locations.map(loc => {
            const coords = selectedNode.coordsList[loc.id];
            const coordStr = coords ? `${coords.x.toFixed(1)}, ${coords.y.toFixed(1)}, ${coords.z.toFixed(1)}${coords.h ? ` | H: ${coords.h.toFixed(1)}` : ''}` : 'NO LOCATION SET';
            
            return `
                <div class="field">
                    <label>${loc.label}</label>
                    <div class="input-with-btn">
                        <input type="text" value="${coordStr}" readonly class="coord-input-small">
                        <button class="pick-btn-small" onclick="pickLocation('${loc.id}')" title="Set Location">
                            <i class="fas fa-crosshairs"></i>
                        </button>
                    </div>
                </div>
            `;
        }).join('');

        html += `
            <div class="info-box" style="margin-top: 10px;">
                <i class="fas fa-info-circle"></i> Place the X-Ray terminal and the scan area.
            </div>
        `;
    }

    if (selectedNode.type === 'check_in') {
        if (!selectedNode.coordsList || Array.isArray(selectedNode.coordsList)) selectedNode.coordsList = {};
        if (!Array.isArray(selectedNode.coordsList.beds)) {
            if (selectedNode.coordsList.bed) {
                selectedNode.coordsList.beds = [selectedNode.coordsList.bed];
            } else {
                selectedNode.coordsList.beds = [];
            }
        }
        selectedNode.coordsList.bed = selectedNode.coordsList.beds[0] || null;
        if (selectedNode.minEMS === undefined) selectedNode.minEMS = 1;

        html += `
            <div class="field">
                <label>EMS AVAILABILITY THRESHOLD</label>
                <div class="input-with-btn">
                    <input type="number" value="${selectedNode.minEMS}" onchange="updateNode('minEMS', this.value)" placeholder="e.g. 1" style="text-align: center;">
                </div>
                <div class="field-description">
                    The Local Doctor provides treatment <span style="color: var(--accent);">ONLY</span> if there are <span style="color: white; font-weight: bold;">fewer than ${selectedNode.minEMS}</span> medics on duty.
                </div>
            </div>
        `;
        const checkinCoords = selectedNode.coordsList.checkin;
        const checkinCoordStr = checkinCoords ? `${checkinCoords.x.toFixed(1)}, ${checkinCoords.y.toFixed(1)}, ${checkinCoords.z.toFixed(1)}${checkinCoords.h ? ` | H: ${checkinCoords.h.toFixed(1)}` : ''}` : 'NO LOCATION SET';
        html += `
            <div class="field">
                <label>CHECK-IN (Local Doctor)</label>
                <div class="input-with-btn">
                    <input type="text" value="${checkinCoordStr}" readonly class="coord-input-small">
                    <button class="pick-btn-small" onclick="pickLocation('checkin')" title="Set Location">
                        <i class="fas fa-crosshairs"></i>
                    </button>
                </div>
            </div>
        `;

        html += `
            <div class="rank-list-editor" style="margin-top: 20px;">
                <label class="field-label-small" style="margin-bottom: 15px;">TREATMENT BEDS</label>
                ${selectedNode.coordsList.beds.map((b, index) => {
                    const coordStr = b ? `${b.x.toFixed(1)}, ${b.y.toFixed(1)}, ${b.z.toFixed(1)}${b.h ? ` | H: ${b.h.toFixed(1)}` : ''}` : 'NO LOCATION SET';
                    return `
                        <div class="door-config-item" style="margin-bottom: 15px; padding: 12px; background: rgba(0,0,0,0.2); border-radius: 8px; border: 1px solid rgba(255,255,255,0.03);">
                            <div class="field" style="margin-bottom: 0;">
                                <label class="field-label-tiny">BED ${index + 1}</label>
                                <div class="input-with-btn">
                                    <input type="text" value="${coordStr}" readonly class="coord-input-small">
                                    <button class="pick-btn-small" onclick="pickLocation('bed', ${index})" title="Set Bed Location">
                                        <i class="fas fa-crosshairs"></i>
                                    </button>
                                    <button class="delete-rank-btn" onclick="deleteCheckInBed(${index})" style="margin-left: 8px;">
                                        <i class="fas fa-trash"></i>
                                    </button>
                                </div>
                            </div>
                        </div>
                    `;
                }).join('')}
                <div class="add-preset-btn" onclick="addCheckInBed()" style="margin-top: 5px;">
                    <i class="fas fa-plus"></i> ADD TREATMENT BED
                </div>
            </div>
        `;

        html += `
            <div class="info-box" style="margin-top: 10px; border-color: var(--accent); color: var(--accent); background: var(--accent-dim);">
                <i class="fas fa-info-circle"></i> Link this node to a Location node. Check-in shows when EMS are off duty. Set the check-in spot and add one or more treatment beds.
            </div>
        `;
    }

    if (selectedNode.type === 'ceiling_monitor') {
        const locations = [
            { id: 'monitor', label: 'Vitals Monitor Prop', icon: 'tv' },
            { id: 'bed', label: 'LINKED TREATMENT BED', icon: 'bed' }
        ];

        if (!selectedNode.coordsList || Array.isArray(selectedNode.coordsList)) selectedNode.coordsList = {};

        html += locations.map(loc => {
            const coords = selectedNode.coordsList[loc.id];
            const coordStr = coords ? `${coords.x.toFixed(1)}, ${coords.y.toFixed(1)}, ${coords.z.toFixed(1)}${coords.h ? ` | H: ${coords.h.toFixed(1)}` : ''}` : 'NO LOCATION SET';
            
            return `
                <div class="field">
                    <label>${loc.label}</label>
                    <div class="input-with-btn">
                        <input type="text" value="${coordStr}" readonly class="coord-input-small">
                        <button class="pick-btn-small" onclick="pickLocation('${loc.id}')" title="Set Location">
                            <i class="fas fa-crosshairs"></i>
                        </button>
                    </div>
                </div>
            `;
        }).join('');

        html += `
            <div class="info-box" style="margin-top: 10px; border-color: var(--accent); color: var(--accent); background: var(--accent-dim);">
                <i class="fas fa-info-circle"></i> Link this to a Location node. Set the monitor prop location and the bed it should monitor.
            </div>
        `;
    }

    inspectorContent.innerHTML = html;
}

window.updateDoorInfo = function(index, key, value) {
    if (selectedNode && selectedNode.doors) {
        selectedNode.doors[index][key] = value;
    }
}

window.deleteDoorFromNode = function(index) {
    if (selectedNode && selectedNode.doors) {
        selectedNode.doors.splice(index, 1);
        renderInspector();
        renderCanvas();
    }
}

window.addDoorToNode = function() {
    if (selectedNode) {
        if (!selectedNode.doors) selectedNode.doors = [];
        selectedNode.doors.push({ label: 'New Door', coords: null, hash: null });
        renderInspector();
        renderCanvas();
    }
}

window.pickDoorLocation = function(index) {
    if (!selectedNode) return;
    app.classList.add('hidden');
    app.style.removeProperty('display'); // Fix: Ensure the UI actually disappears
    fetch(`https://${GetParentResourceName()}/startDoorPlacement`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
            nodeId: selectedNode.id,
            doorIndex: index
        })
    });
}

window.updateOutfit = function(rankKey, component, subkey, value) {
    if (selectedNode && selectedNode.type === 'wardrobe') {
        if (!selectedNode.outfits || Array.isArray(selectedNode.outfits)) selectedNode.outfits = {};
        if (!selectedNode.outfits[rankKey]) selectedNode.outfits[rankKey] = {};
        if (!selectedNode.outfits[rankKey][component]) selectedNode.outfits[rankKey][component] = {};
        
        selectedNode.outfits[rankKey][component][subkey] = parseInt(value);
    }
}

window.updateNode = function(key, value) {
    if (selectedNode) {
        selectedNode[key] = value;
        renderCanvas();
        renderInspector();
    }
}

window.toggleNewPermission = function(nodeId, rankKey, feature) {
    const node = nodes.find(n => n.id === nodeId);
    if (!node) return;

    // CRITICAL: If rankPerms is an array (from Lua []), force it to an Object {}
    if (!node.rankPerms || Array.isArray(node.rankPerms)) {
        node.rankPerms = {};
    }
    
    // CRITICAL: If the specific rank is an array, force it to an Object {}
    if (!node.rankPerms[rankKey] || Array.isArray(node.rankPerms[rankKey])) {
        node.rankPerms[rankKey] = {};
    }

    // Toggle value
    node.rankPerms[rankKey][feature] = !node.rankPerms[rankKey][feature];

    // Refresh and Save
    renderInspector();
    renderCanvas();
    saveData();
};

window.updateRank = function(index, key, value) {
    if (selectedNode && selectedNode.ranks) {
        selectedNode.ranks[index][key] = value;
        renderCanvas();
        refreshLinkedPermissionNodes(selectedNode.id);
    }
}

window.toggleRankBossMenu = function(index) {
    if (selectedNode && selectedNode.ranks) {
        selectedNode.ranks[index].bossMenu = !selectedNode.ranks[index].bossMenu;
        renderInspector();
    }
}

window.deleteRank = function(index) {
    if (selectedNode && selectedNode.ranks) {
        selectedNode.ranks.splice(index, 1);
        renderCanvas();
        renderInspector();
        refreshLinkedPermissionNodes(selectedNode.id);
    }
}

window.addRankToList = function() {
    if (selectedNode) {
        if (!selectedNode.ranks) selectedNode.ranks = [];
        selectedNode.ranks.push({ name: 'New Rank', level: 0, pay: 500 });
        renderCanvas();
        renderInspector();
        refreshLinkedPermissionNodes(selectedNode.id);
    }
}

window.updateVehicleInfo = function(index, key, value) {
    if (selectedNode && selectedNode.vehicles) {
        selectedNode.vehicles[index][key] = value;
    }
}

window.deleteVehicleFromNode = function(index) {
    if (selectedNode && selectedNode.vehicles) {
        selectedNode.vehicles.splice(index, 1);
        renderInspector();
    }
}

window.addVehicleToNode = function() {
    if (selectedNode) {
        if (!selectedNode.vehicles) selectedNode.vehicles = [];
        selectedNode.vehicles.push({ model: '', label: '' });
        renderInspector();
    }
}

window.addPoint = function(type) {
    if (selectedNode) {
        if (type === 'spawn') {
            if (!selectedNode.spawnPoints) selectedNode.spawnPoints = [];
            selectedNode.spawnPoints.push(null);
        } else {
            if (!selectedNode.deletePoints) selectedNode.deletePoints = [];
            selectedNode.deletePoints.push(null);
        }
        renderInspector();
    }
}

window.deletePoint = function(type, index) {
    if (selectedNode) {
        if (type === 'spawn') selectedNode.spawnPoints.splice(index, 1);
        else selectedNode.deletePoints.splice(index, 1);
        renderInspector();
    }
}

window.addCheckInBed = function() {
    if (!selectedNode || selectedNode.type !== 'check_in') return;
    if (!selectedNode.coordsList || Array.isArray(selectedNode.coordsList)) selectedNode.coordsList = {};
    if (!Array.isArray(selectedNode.coordsList.beds)) {
        selectedNode.coordsList.beds = [];
    }
    selectedNode.coordsList.beds.push(null);
    renderInspector();
}

window.deleteCheckInBed = function(index) {
    if (!selectedNode || selectedNode.type !== 'check_in') return;
    if (!selectedNode.coordsList || Array.isArray(selectedNode.coordsList)) selectedNode.coordsList = {};
    if (!Array.isArray(selectedNode.coordsList.beds)) {
        selectedNode.coordsList.beds = [];
    }
    selectedNode.coordsList.beds.splice(index, 1);
    selectedNode.coordsList.bed = selectedNode.coordsList.beds[0] || null;
    renderInspector();
}

window.pickLocation = function(overrideLocType, pointIndex, interactionType) {
    if (!selectedNode) return;
    
    let currentLocType = overrideLocType || selectedNode.locType;
    
    app.classList.add('hidden');
    app.style.removeProperty('display');
    
    fetch(`https://${GetParentResourceName()}/startPlacement`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
            nodeId: selectedNode.id,
            type: selectedNode.type,
            blipId: selectedNode.blipId,
            blipColor: selectedNode.blipColor,
            blipName: selectedNode.blipName || selectedNode.label,
            locType: currentLocType,
            pointIndex: pointIndex,
            interactionType: interactionType
        })
    });
}

// Listen for Escape key to close
window.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
        const invoiceContainer = document.getElementById('ems-invoice-container');
        if (invoiceContainer && !invoiceContainer.classList.contains('hidden')) {
            window.closeEMSInvoiceUI();
            return;
        }

        if (!app.classList.contains('hidden')) {
            app.classList.add('hidden');
            app.style.removeProperty('display');
            fetch(`https://${GetParentResourceName()}/amb_close`, {
                method: 'POST'
            });
        }
    }
});

// Canvas Interaction Logic
canvas.addEventListener('mousedown', (e) => {
    if (e.target === canvas || e.target === canvasContent || e.target === svg) {
        isPanning = true;
        lastMousePos = { x: e.clientX, y: e.clientY };
    }
});

let drawRequested = false;
function requestDraw() {
    if (!drawRequested) {
        drawRequested = true;
        requestAnimationFrame(() => {
            drawConnections();
            drawRequested = false;
        });
    }
}

document.addEventListener('mousemove', (e) => {
    if (isDragging && dragTarget && selectedNode) {
        const rect = canvas.getBoundingClientRect();
        const x = (e.clientX - rect.left - pan.x) / zoom - offset.x;
        const y = (e.clientY - rect.top - pan.y) / zoom - offset.y;
        
        dragTarget.style.left = `${x}px`;
        dragTarget.style.top = `${y}px`;
        selectedNode.x = x;
        selectedNode.y = y;
        requestDraw();
    } else if (isPanning) {
        const dx = e.clientX - lastMousePos.x;
        const dy = e.clientY - lastMousePos.y;
        pan.x += dx;
        pan.y += dy;
        lastMousePos = { x: e.clientX, y: e.clientY };
        updateCanvasTransform();
    }

    if (activePort && tempLine) {
        const fromNode = nodes.find(n => String(n.id) === String(activePort.id));
        const fromEl = document.getElementById(`node-${activePort.id}`);
        if (fromNode && fromEl) {
            // Adjust for port-out offset (20px outside node)
            const x1 = (fromNode.x || 0) + (fromEl.offsetWidth > 0 ? fromEl.offsetWidth : 160) + 20;
            const y1 = (fromNode.y || 0) + (fromEl.offsetHeight > 0 ? fromEl.offsetHeight : 80) / 2;
            const rect = canvas.getBoundingClientRect();
            const x2 = (e.clientX - rect.left - pan.x) / zoom;
            const y2 = (e.clientY - rect.top - pan.y) / zoom;
            const cp1x = x1 + (x2 - x1) / 2;
            const cp2x = x1 + (x2 - x1) / 2;
            tempLine.setAttribute('d', `M ${x1} ${y1} C ${cp1x} ${y1}, ${cp2x} ${y2}, ${x2} ${y2}`);
            tempLine.style.stroke = '#ffffff';
            tempLine.style.strokeWidth = '2px';
            tempLine.style.strokeDasharray = '5,5';
            tempLine.style.fill = 'none';
        }
    }
});

document.addEventListener('mouseup', (e) => {
    if (activePort && tempLine) {
        const portIn = e.target.closest('.port-in');
        if (portIn) {
            const toId = portIn.dataset.id;
            const exists = connections.some(c => c.from === activePort.id && c.to === toId);
            if (activePort.id !== toId && !exists) {
                connections.push({ from: activePort.id, to: toId });
            }
        }
        tempLine.remove();
        tempLine = null;
        activePort = null;
        drawConnections();
        // Refresh inspector if the connection was to a permission node
        if (selectedNode && selectedNode.type === 'permission') {
            renderInspector();
        }
    }
    isDragging = false;
    isPanning = false;
    dragTarget = null;
});

canvasContent.addEventListener('mousedown', (e) => {
    if (e.target.classList.contains('port-out')) {
        e.stopPropagation();
        activePort = { id: e.target.dataset.id };
        tempLine = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        tempLine.setAttribute('class', 'connection temp');
        tempLine.style.stroke = '#ffffff';
        tempLine.style.strokeWidth = '2px';
        tempLine.style.strokeDasharray = '5,5';
        tempLine.style.fill = 'none';
        svg.appendChild(tempLine);
    }
});

function drawConnections() {
    if (!svg) return;
    
    // Ensure SVG is the last child so it stays on top of nodes
    if (svg.parentElement) {
        svg.parentElement.appendChild(svg);
    }
    
    svg.innerHTML = '';
    
    // Use a single string for connections to avoid ID type issues
    connections.forEach(conn => {
        const fromId = String(conn.from);
        const toId = String(conn.to);
        
        const fromNode = nodes.find(n => String(n.id) === fromId);
        const toNode = nodes.find(n => String(n.id) === toId);
        
        if (fromNode && toNode) {
            const fromEl = document.getElementById(`node-${fromId}`);
            const toEl = document.getElementById(`node-${toId}`);
            
            // Default sizes if elements aren't fully rendered
            const fromW = fromEl ? fromEl.offsetWidth : 160;
            const fromH = fromEl ? fromEl.offsetHeight : 80;
            const toH = toEl ? toEl.offsetHeight : 80;
            
            const x1 = (fromNode.x || 0) + (fromW > 0 ? fromW : 160) + 20;
            const y1 = (fromNode.y || 0) + (fromH > 0 ? fromH : 80) / 2;
            const x2 = (toNode.x || 0) - 20;
            const y2 = (toNode.y || 0) + (toH > 0 ? toH : 80) / 2;
            
            if (isNaN(x1) || isNaN(y1) || isNaN(x2) || isNaN(y2)) return;
            
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            const cp1x = x1 + (x2 - x1) / 2;
            const cp2x = x1 + (x2 - x1) / 2;
            path.setAttribute('d', `M ${x1} ${y1} C ${cp1x} ${y1}, ${cp2x} ${y2}, ${x2} ${y2}`);
            path.setAttribute('class', 'connection');
            
            // Explicitly set styles to ensure visibility
            path.style.stroke = 'var(--accent)';
            path.style.strokeWidth = '2px';
            path.style.fill = 'none';
            path.style.pointerEvents = 'auto';
            
            path.addEventListener('click', (e) => {
                e.stopPropagation();
                connections = connections.filter(c => c !== conn);
                drawConnections();
            });
            svg.appendChild(path);
        }
    });
}

function getBlipHex(colorId) {
    const colors = {
        1: '#ff0000', 2: '#00ff00', 3: '#0000ff', 4: '#ffffff', 5: '#ffff00', 
        17: '#ff8000', 18: '#ff00ff', 21: '#ff0080', 25: '#00ff80', 29: '#8000ff', 
        31: '#80ff00', 35: '#0080ff', 38: '#00ffff'
    };
    return colors[colorId] || '#ffffff';
}

function findLinkedRankNode(permNodeId) {
    const link = connections.find(c => c.to === permNodeId);
    if (!link) return null;
    return nodes.find(n => n.id === link.from && n.type === 'rank');
}

function refreshLinkedPermissionNodes(rankNodeId) {
    const linkedPermLinks = connections.filter(c => c.from === rankNodeId);
    linkedPermLinks.forEach(link => {
        const permNode = nodes.find(n => n.id === link.to && n.type === 'permission');
        if (permNode && selectedNode && selectedNode.id === permNode.id) {
            renderInspector();
        }
    });
}

document.addEventListener('click', (e) => {
    const nodeItem = e.target.closest('.node-item');
    if (nodeItem) {
        const type = nodeItem.dataset.type;
        if (!type) return;

        if (type === 'preset') {
            const presetId = nodeItem.dataset.id;
            if (presetId === 'ems_full') {
                const presetData = {"links":[{"from":"ambulance_1775749976734","to":"rank_1775750018871"},{"from":"rank_1775750018871","to":"permission_1775750029019"},{"from":"ambulance_1775749976734","to":"inventory_1775750080574"},{"from":"ambulance_1775749976734","to":"location_1775750256112"},{"from":"location_1775750256112","to":"ceiling_monitor_1773491802550"},{"from":"ambulance_1775749976734","to":"xray_1775752150622"},{"from":"location_1775750256112","to":"vehicle_1775753537129"},{"from":"location_1775750256112","to":"helipad_1775753687163"},{"from":"ambulance_1775749976734","to":"pharmacy_1775755761280"}],"pan":{"y":-1510.769092540554,"x":341.2171914970706},"nodes":[{"y":2665.1230123321125,"label":"New ceiling_monitor","coordsList":{"bed":{"h":68.31973266601562,"x":108.5020523071289,"y":-385.3170776367188,"z":43.80730438232422},"monitor":{"h":212.70208740234375,"x":109.04956817626952,"y":-385.4734497070313,"z":46.11379623413086}},"x":1133.132297740617,"type":"ceiling_monitor","id":"ceiling_monitor_1773491802550"},{"coords":{"x":65.28755187988281,"y":-398.5303649902344,"z":38.3393440246582},"blipId":61,"blipColor":1,"type":"department","y":3330.344979682455,"label":"Ambulance","x":94.36567940426056,"frameworkJob":"ambulance","id":"ambulance_1775749976734"},{"ranks":[{"pay":500,"name":"Trainee","level":0},{"pay":750,"name":"Medic","level":1},{"pay":1000,"name":"Paramedic","level":2},{"pay":1250,"name":"Senior Medic","level":3},{"pay":1500,"name":"Doctor","bossMenu":true,"level":4},{"pay":2000,"name":"Chief of Medicine","bossMenu":true,"level":5}],"payment":500,"y":3554.3389276046205,"label":"New Rank","level":0,"x":709.8340579756215,"type":"rank","id":"rank_1775750018871"},{"permType":"duty","y":3683.3617234508874,"label":"New permission","rankPerms":{"rank_3":{},"rank_5":{"Inventory":true,"Boss Menu":true,"Duty":true,"Stash":true,"X-Ray":true,"Garage":true},"rank_1":{},"rank_4":{},"rank_0":{"Duty":true},"rank_2":{}},"x":1151.794805021274,"type":"permission","id":"permission_1775750029019"},{"coords":{"x":49.29799270629883,"y":-350.771240234375,"z":44.13398361206055},"y":3174.821318490354,"label":"New inventory","x":691.0781133103034,"type":"inventory","id":"inventory_1775750080574"},{"locType":"garage","label":"New location","y":2971.8029467949564,"coordsList":{"duty":{"h":159.51165771484375,"x":64.4984359741211,"y":-362.4805603027344,"z":42.93470001220703},"boss_menu":{"x":57.88290023803711,"y":-349.65081787109375,"z":44.15483474731445}},"interactionTypes":{"duty":"ped"},"x":603.7652459853697,"type":"location","id":"location_1775750256112"},{"locType":"pc","label":"New xray","y":3763.7004955782104,"coordsList":{"bed":{"h":158.78575134277344,"x":113.75897979736328,"y":-381.3411254882813,"z":39.3869514465332},"pc":{"pitch":-5.5,"y":-376.0128173828125,"z":39.58840942382812,"h":147.44467163085938,"x":114.72154998779295}},"xray":[],"x":592.2640581540402,"type":"xray","id":"xray_1775752150622"},{"spawnPoints":[{"h":433.678955078125,"x":78.77032470703125,"y":-431.9244689941406,"z":38.37868881225586}],"coordsList":{},"locType":"spawn","type":"vehicle","y":2836.1176848194928,"vehicles":[],"label":"New vehicle","x":1150.5738710591047,"id":"vehicle_1775753537129","deletePoints":[]},{"spawnPoints":[{"h":245.56912231445312,"x":95.0845184326172,"y":-420.7569580078125,"z":85.30015563964844}],"coordsList":{},"locType":"spawn","type":"helipad","y":3040.471862685031,"vehicles":[],"label":"New helipad","x":1121.9631766435798,"id":"helipad_1775753687163","deletePoints":[]},{"coords":{"x":76.140869140625,"y":-364.0973205566406,"z":39.58733367919922},"y":3374.2097511618217,"label":"New pharmacy","pharmacy":{"heading":0},"x":740.0289462858219,"type":"pharmacy","id":"pharmacy_1775755761280"}]};
                
                // Reuse existing import logic but with preset data
                const textarea = document.getElementById('import-textarea');
                if (textarea) {
                    textarea.value = JSON.stringify(presetData);
                    window.confirmImport();
                }
            }
            return;
        }

        const deptId = nodeItem.dataset.id;
        const deptLabel = nodeItem.dataset.label;
        const canvasRect = canvas.getBoundingClientRect();
        const centerX = (canvasRect.width / 2 - pan.x) / zoom - 80;
        const centerY = (canvasRect.height / 2 - pan.y) / zoom - 40;
        const newNode = {
            id: (deptId || type) + '_' + Date.now(),
            type: type,
            label: deptLabel || (type === 'rank' ? 'New Rank' : (type === 'boss_menu' ? 'Boss Menu' : 'New ' + type)),
            x: centerX,
            y: centerY,
            level: type === 'rank' ? 0 : undefined,
            payment: type === 'rank' ? 500 : undefined,
            permType: type === 'permission' ? 'duty' : undefined,
            locType: (type === 'location') ? 'garage' : ((type === 'vehicle' || type === 'helipad') ? 'spawn' : (type === 'xray' ? 'pc' : (type === 'check_in' ? 'checkin' : undefined))),
            coordsList: (type === 'location' || type === 'vehicle' || type === 'helipad' || type === 'xray' || type === 'check_in') ? {} : undefined,
            coords: (type === 'boss_menu' || type === 'wardrobe' || type === 'inventory') ? null : undefined,
            spawnCoords: undefined,
            outfits: type === 'wardrobe' ? {} : undefined,
            vehicles: (type === 'vehicle' || type === 'helipad') ? [] : undefined,
            doors: type === 'door' ? [] : undefined,
            xray: type === 'xray' ? { pc: null, bed: null } : undefined,
            check_in: type === 'check_in' ? { checkin: null, bed: null } : undefined,
            minEMS: type === 'check_in' ? 1 : undefined,
            spawnPoints: (type === 'vehicle' || type === 'helipad') ? [] : undefined,
            deletePoints: (type === 'vehicle' || type === 'helipad') ? [] : undefined,
            pharmacy: type === 'pharmacy' ? { coords: null, heading: 0 } : undefined,
            ranks: type === 'rank' ? [
                { name: 'Trainee', level: 0, pay: 500 },
                { name: 'Medic', level: 1, pay: 750 },
                { name: 'Paramedic', level: 2, pay: 1000 },
                { name: 'Senior Medic', level: 3, pay: 1250 },
                { name: 'Doctor', level: 4, pay: 1500 },
                { name: 'Chief of Medicine', level: 5, pay: 2000 }
            ] : undefined
        };
        nodes.push(newNode);
        renderCanvas();
        selectNode(newNode);
        return;
    }

    const categoryHeader = e.target.closest('.category-header');
    if (categoryHeader) {
        const category = categoryHeader.parentElement;
        const content = category.querySelector('.category-content');
        const icon = categoryHeader.querySelector('i');
        const isHidden = content.classList.toggle('hidden');
        category.classList.toggle('active', !isHidden);
        if (isHidden) {
            icon.className = 'fas fa-chevron-down';
        } else {
            icon.className = 'fas fa-chevron-up';
        }
    }
});

document.getElementById('close-inspector').addEventListener('click', () => {
    if (inspector) inspector.classList.add('hidden');
    selectedNode = null;
    document.querySelectorAll('.node').forEach(n => n.classList.remove('selected'));
});

// Prevent mouse wheel on number inputs from changing values, and handle zooming
document.addEventListener('wheel', function(e) {
    // If Boss Menu is open, don't handle zoom
    const bossMenu = document.getElementById('boss-menu-container');
    if (bossMenu && bossMenu.classList.contains('visible')) return;

    if (document.activeElement.type === 'number') {
        document.activeElement.blur();
    }

    // Only zoom if the mouse is over the canvas area
    const canvasRect = canvasContainer.getBoundingClientRect();
    if (e.clientX >= canvasRect.left && e.clientX <= canvasRect.right && 
        e.clientY >= canvasRect.top && e.clientY <= canvasRect.bottom) {
        
        const delta = e.deltaY > 0 ? 0.9 : 1.1;
        const newZoom = Math.min(Math.max(zoom * delta, 0.2), 3.0);
        
        if (newZoom !== zoom) {
            // Zoom centered on mouse position
            const mouseX = e.clientX - canvasRect.left;
            const mouseY = e.clientY - canvasRect.top;
            
            pan.x = mouseX - (mouseX - pan.x) * (newZoom / zoom);
            pan.y = mouseY - (mouseY - pan.y) * (newZoom / zoom);
            
            zoom = newZoom;
            updateCanvasTransform();
        }
    }
});

document.getElementById('save-btn').addEventListener('click', () => {
    saveData();
});

document.getElementById('export-btn').addEventListener('click', () => {
    const sanitizedNodes = nodes.map(node => {
        const newNode = { ...node };
        if (newNode.type === 'permission' && newNode.rankPerms) {
            const newPerms = {};
            Object.keys(newNode.rankPerms).forEach(rk => {
                newPerms[rk] = { ...newNode.rankPerms[rk] };
            });
            newNode.rankPerms = newPerms;
        }
        return newNode;
    });

    const data = JSON.stringify({ ...currentFullData, nodes: sanitizedNodes, links: connections, pan });
    const textarea = document.getElementById('import-textarea');
    const container = document.getElementById('import-modal-container');
    const title = container.querySelector('.fine-input-header span');
    const label = container.querySelector('.fine-field label');
    const confirmBtn = container.querySelector('.fine-confirm-btn');

    if (container && textarea) {
        textarea.value = data;
        title.innerText = "EXPORT CONFIGURATION";
        label.innerText = "COPY THIS JSON DATA";
        confirmBtn.style.display = 'none'; // Hide confirm button for export
        
        container.classList.add('visible');
        textarea.focus();
        textarea.select();
        
    try {
        document.execCommand('copy');
        window.showNotification("Configuration Exported", [{ label: "Status", value: "Copied to Clipboard!" }]);
    } catch (err) {
            console.error("Copy failed", err);
    }
    }
});

document.getElementById('import-btn').addEventListener('click', () => {
    const textarea = document.getElementById('import-textarea');
    const container = document.getElementById('import-modal-container');
    const title = container.querySelector('.fine-input-header span');
    const label = container.querySelector('.fine-field label');
    const confirmBtn = container.querySelector('.fine-confirm-btn');

    if (container && textarea) {
        textarea.value = '';
        title.innerText = "IMPORT CONFIGURATION";
        label.innerText = "PASTE JSON DATA HERE";
        confirmBtn.style.display = 'block';
        
        container.classList.add('visible');
        textarea.focus();
    }
});

window.closeImportModal = function() {
    const container = document.getElementById('import-modal-container');
    if (container) container.classList.remove('visible');
};

window.confirmImport = function() {
    const input = document.getElementById('import-textarea').value;
    if (!input) return;

    try {
        const data = JSON.parse(input);
        const importedNodes = data.nodes || [];
        const importedLinks = data.links || data.connections || [];

        if (importedNodes.length > 0) {
            // Calculate centering offset to place the imported nodes in the middle of the CURRENT view
            const containerRect = canvasContainer.getBoundingClientRect();
            // Center of the visible container in canvas coordinates
            const viewCenterX = (containerRect.width / 2 - pan.x) / zoom;
            const viewCenterY = (containerRect.height / 2 - pan.y) / zoom;

            // Find center of imported nodes
            let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
            importedNodes.forEach(n => {
                minX = Math.min(minX, n.x);
                maxX = Math.max(maxX, n.x);
                minY = Math.min(minY, n.y);
                maxY = Math.max(maxY, n.y);
            });
            const importedCenterX = (minX + maxX) / 2;
            const importedCenterY = (minY + maxY) / 2;

            const offsetX = viewCenterX - importedCenterX;
            const offsetY = viewCenterY - importedCenterY;

            // Map old IDs to new unique IDs to avoid overwriting existing nodes
            const idMap = {};
            const timestamp = Date.now();

            importedNodes.forEach((node, index) => {
                const oldId = node.id;
                // Generate a truly unique ID for this instance
                const newId = `${node.type}_${Date.now()}_${index}_${Math.floor(Math.random() * 1000000)}`;
                idMap[oldId] = newId;
                
                // Update node data
                node.id = newId;
                node.x = (node.x || 0) + offsetX;
                node.y = (node.y || 0) + offsetY;
                
                nodes.push(node);
            });

            // Add links with updated IDs
            importedLinks.forEach(link => {
                const oldFrom = String(link.from || link.fromNode || "");
                const oldTo = String(link.to || link.toNode || "");
                const newFrom = idMap[oldFrom];
                const newTo = idMap[oldTo];
                if (newFrom && newTo) {
                    connections.push({ from: newFrom, to: newTo });
                }
            });

            saveData();
            renderCanvas();
            
            // Second pass for connections to ensure DOM is ready and offsets are calculated
            setTimeout(() => {
                drawConnections();
            }, 100);

            window.showNotification("Configuration Appended", [{ label: "Status", value: "Nodes and links pasted into view!" }]);
            window.closeImportModal();
        } else {
            window.showNotification("Import Failed", [{ label: "Error", value: "Invalid configuration format (no nodes found)" }]);
        }
    } catch (e) {
        console.error("Import Error:", e);
        window.showNotification("Import Failed", [{ label: "Error", value: "Invalid JSON string" }]);
    }
};

document.getElementById('close-btn').addEventListener('click', () => {
    app.classList.add('hidden');
    app.style.removeProperty('display');
    fetch(`https://${GetParentResourceName()}/amb_close`, {
        method: 'POST'
    });
});

document.getElementById('delete-node-btn').addEventListener('click', () => {
    if (selectedNode) {
        nodes = nodes.filter(n => n.id !== selectedNode.id);
        connections = connections.filter(c => c.from !== selectedNode.id && c.to !== selectedNode.id);
        selectedNode = null;
        renderCanvas();
        if (inspector) inspector.classList.add('hidden');
    }
});

// Tab Switching
document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
        const tabName = tab.dataset.tab;
        if (tabName === currentTab) return;

        // Update active tab UI
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        tab.classList.add('active');

        // Toggle views
        document.querySelectorAll('.tab-view').forEach(view => {
            view.classList.add('hidden');
        });

        if (tabName === 'members') {
            document.getElementById('members-tab').classList.remove('hidden');
            // Reset player selection when switching to members tab
            selectedPlayer = null;
            selectedPlayerInfo.style.display = 'flex';
            memberEditor.classList.add('hidden');
            memberEditor.style.display = 'none';
            refreshPlayersList();
        } else if (tabName === 'departments') {
            document.getElementById('departments-tab').classList.remove('hidden');
            renderCanvas();
        }

        currentTab = tabName;
    });
});

// Members Logic
function refreshPlayersList() {
    fetch(`https://${GetParentResourceName()}/amb_getPlayers`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).then(resp => resp.json()).then(data => {
        onlinePlayers = data;
        
        // Update selected player data if they are still online
        if (selectedPlayer) {
            const updated = onlinePlayers.find(p => p.id === selectedPlayer.id);
            if (updated) {
                selectedPlayer = updated;
                // Re-render editor with new data
                document.getElementById('edit-player-name').innerText = selectedPlayer.name;
                document.getElementById('edit-player-id').innerText = `ID: ${selectedPlayer.id}`;
                // Refresh rank select based on possibly new job
                const currentJob = selectedPlayer.jobName;
                const depts = nodes.filter(n => n.type === 'department');
                if (depts.find(d => d.id === currentJob)) {
                    hireDeptSelect.value = currentJob;
                    updateRankSelect(currentJob, selectedPlayer.jobGradeLevel);
                }
            } else {
                // Player went offline
                selectedPlayer = null;
                selectedPlayerInfo.style.display = 'flex';
                memberEditor.classList.add('hidden');
                memberEditor.style.display = 'none';
            }
        }
        
        renderPlayersList();
    });
}

function renderPlayersList() {
    const searchTerm = playerSearch.value.toLowerCase();
    playersList.innerHTML = '';
    
    const filtered = onlinePlayers.filter(p => 
        p.name.toLowerCase().includes(searchTerm) || 
        p.id.toString().includes(searchTerm)
    );

    filtered.forEach(player => {
        const card = document.createElement('div');
        card.className = `player-card ${selectedPlayer && selectedPlayer.id === player.id ? 'active' : ''}`;
        card.innerHTML = `
            <div class="player-icon"><i class="fas fa-user"></i></div>
            <div class="player-info">
                <span class="player-name">${player.name}</span>
                <span class="player-job">${player.jobLabel} (${player.jobGradeLabel})</span>
            </div>
        `;
        card.addEventListener('click', () => selectPlayer(player));
        playersList.appendChild(card);
    });
}

function selectPlayer(player) {
    selectedPlayer = player;
    renderPlayersList();
    
    selectedPlayerInfo.style.display = 'none';
    memberEditor.classList.remove('hidden');
    memberEditor.style.display = 'block';
    
    document.getElementById('edit-player-name').innerText = player.name;
    document.getElementById('edit-player-id').innerText = `ID: ${player.id}`;
    
    // Load departments into select
    hireDeptSelect.innerHTML = '<option value="" disabled selected>Select a department...</option>';
    const depts = nodes.filter(n => n.type === 'department');
    depts.forEach(dept => {
        const option = document.createElement('option');
        option.value = dept.id;
        option.innerText = dept.label;
        hireDeptSelect.appendChild(option);
    });

    // If player already in a managed dept, select it
    const currentJob = player.jobName;
    if (depts.find(d => d.id === currentJob)) {
        hireDeptSelect.value = currentJob;
        updateRankSelect(currentJob, player.jobGradeLevel);
    } else {
        hireRankSelect.innerHTML = '<option value="" disabled selected>Select department first...</option>';
    }
}

function updateRankSelect(deptId, currentGrade = null) {
    hireRankSelect.innerHTML = '';
    
    // Find rank node linked to this department (Search ALL links from this dept)
    const rankLink = connections.find(c => {
        if (c.from !== deptId) return false;
        const targetNode = nodes.find(n => n.id === c.to);
        return targetNode && targetNode.type === 'rank';
    });

    if (!rankLink) {
        hireRankSelect.innerHTML = '<option value="" disabled>No ranks configured for this department</option>';
        return;
    }

    const rankNode = nodes.find(n => n.id === rankLink.to && n.type === 'rank');
    if (!rankNode || !rankNode.ranks) {
        hireRankSelect.innerHTML = '<option value="" disabled>No ranks found</option>';
        return;
    }

    rankNode.ranks.forEach(rank => {
        const option = document.createElement('option');
        option.value = rank.level;
        option.innerText = `${rank.name} (Level ${rank.level})`;
        if (currentGrade !== null && rank.level === currentGrade) {
            option.selected = true;
        }
        hireRankSelect.appendChild(option);
    });
}

hireDeptSelect.addEventListener('change', () => {
    updateRankSelect(hireDeptSelect.value);
});

playerSearch.addEventListener('input', renderPlayersList);
document.getElementById('refresh-players-btn').addEventListener('click', refreshPlayersList);

document.getElementById('confirm-hire-btn').addEventListener('click', () => {
    if (!selectedPlayer || !hireDeptSelect.value || hireRankSelect.value === '') return;
    
    fetch(`https://${GetParentResourceName()}/amb_hirePlayer`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            playerId: selectedPlayer.id,
            job: hireDeptSelect.value,
            grade: parseInt(hireRankSelect.value)
        })
    }).then(() => {
        refreshPlayersList();
    });
});

document.getElementById('fire-member-btn').addEventListener('click', () => {
    if (!selectedPlayer) return;
    
    fetch(`https://${GetParentResourceName()}/amb_hirePlayer`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            playerId: selectedPlayer.id,
            job: 'unemployed',
            grade: 0
        })
    }).then(() => {
        refreshPlayersList();
    });
});

